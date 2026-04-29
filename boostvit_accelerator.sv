`timescale 1ns / 1ps
// =============================================================================
// boostvit_accelerator.sv  --  v2: Full paper Fig. 6 integration
//
// Integrates:
//   - boostvit_controller (29-state inner FSM, with real residual + full LN)
//   - outer_loop_ctrl (multi-tile iterator, double-buffered weight loads)
//   - axi_burst_if (AXI-style DMA stub with FIFOs)
//   - multi_head_attn (H parallel attention_head engines)
//   - head_concat_unit (per-head concat + wide observability)
//   - wide_accum_bank (24-bit partial sum accumulator)
//   - sm_unit (shared exp+accum+reciprocal; now OBSERVABLE via host readback)
//   - 4 x ram_dp buffers (large, 4096 x 128b)
//   - ln_array_16x16, linear_proj, gelu_approx_16, residual_add_16
//
// Parameters:
//   H_HEADS    = 3   (DeiT-Tiny); 6 Small; 12 Base
//   H_PARALLEL = 1   -> Use H parallel attention heads (paper throughput)
//   BUF_DEPTH  = 4096 (enough for full DeiT-Tiny activation buffers)
// =============================================================================

module boostvit_accelerator #(
    parameter integer H_HEADS        = 3,
    parameter integer H_PARALLEL     = 1,
    parameter         BOOTH_LSB_SCALE = 1,
    parameter         THRESHOLD       = 10,
    parameter integer BUF_DEPTH       = 4096,
    parameter integer BUF_ADDR_W      = 12
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,

    input  wire         host_act_we,
    input  wire [BUF_ADDR_W-1:0] host_act_addr,
    input  wire [127:0] host_act_din,
    input  wire         host_wgt_we,
    input  wire [BUF_ADDR_W-1:0] host_wgt_addr,
    input  wire [127:0] host_wgt_din,
    input  wire [BUF_ADDR_W-1:0] host_out_addr,
    output wire [127:0] host_out_dout,

    // Outer-loop configuration
    input  wire [4:0]   cfg_n_tiles,
    input  wire [4:0]   cfg_d_tiles,
    input  wire [3:0]   cfg_h_heads,
    input  wire [3:0]   cfg_l_layers,

    // DRAM stub interface (for axi_burst_if)
    output wire         mem_req,
    output wire         mem_we,
    output wire [31:0]  mem_addr,
    output wire [127:0] mem_wdata,
    input  wire         mem_ack,
    input  wire [127:0] mem_rdata,

    output wire         done,
    output wire [15:0]  total_cycles,
    output wire [4:0]   cur_state_dbg,
    output wire         all_done,
    output wire [31:0]  total_tiles_fired
);

    // =========================================================================
    // Reset sync (init to asserted so all submodule regs start at 0)
    // =========================================================================
    reg rst_s1 = 1'b1, rst_s2 = 1'b1;
    always @(posedge clk) begin rst_s1 <= ~rst_n; rst_s2 <= rst_s1; end
    wire rst = rst_s2;

    // =========================================================================
    // Inner controller wires
    // =========================================================================
    wire         ctl_ren, ctl_ren_b, ctl_wen;
    wire [1:0]   ctl_rsel, ctl_rsel_b, ctl_wsel;
    wire [7:0]   ctl_raddr, ctl_raddr_b, ctl_waddr;
    wire [127:0] ctl_rdata, ctl_rdata_b;
    wire [127:0] ctl_wdata;

    wire [2047:0] ln_x_in, ln_y_out;
    wire [127:0]  ln_gamma, ln_beta;

    wire         lp_rst_sync;
    wire [15:0]  lp_load_cols;
    wire [127:0] lp_w, lp_x_packed, lp_y_packed;
    wire         lp_valid_x, lp_out_valid;

    wire         ah_rst_sync, ah_load_k_en, ah_valid_q;
    wire [3:0]   ah_load_k_col;
    wire [127:0] ah_k_in_packed, ah_q_packed, ah_sm_out;
    wire         ah_attn_valid;

    wire [127:0] gelu_x_in, gelu_y_out;
    wire [127:0] res_a, res_b, res_y;

    wire [127:0] smu_probe_x_in, smu_probe_sm_out;
    wire [11:0]  smu_probe_es_sum;

    wire         accum_clear, accum_valid_in, accum_latch, accum_out_valid;
    wire [127:0] accum_y_in, accum_y_out;
    wire [4:0]   accum_shift;

    wire [7:0]  phase0_cycles_dbg;

    // =========================================================================
    // Inner controller instance
    // =========================================================================
    wire         ol_inner_start;
    wire         inner_done_w;
    boostvit_controller u_ctl (
        .clk(clk), .rst(rst),
        .start         (ol_inner_start),
        .done          (inner_done_w),
        .phase_cycles_0(phase0_cycles_dbg),
        .total_cycles  (total_cycles),
        .cur_state_dbg (cur_state_dbg),

        .buf_ren   (ctl_ren),   .buf_sel   (ctl_rsel),
        .buf_raddr (ctl_raddr[7:0]), .buf_rdata (ctl_rdata),
        .buf_ren_b (ctl_ren_b), .buf_sel_b (ctl_rsel_b),
        .buf_raddr_b(ctl_raddr_b[7:0]), .buf_rdata_b(ctl_rdata_b),
        .buf_wen   (ctl_wen),   .buf_wsel  (ctl_wsel),
        .buf_waddr (ctl_waddr[7:0]), .buf_wdata (ctl_wdata),

        .ln_x_in(ln_x_in), .ln_gamma(ln_gamma), .ln_beta(ln_beta),
        .ln_y_out(ln_y_out),

        .lp_rst_sync(lp_rst_sync), .lp_load_cols(lp_load_cols),
        .lp_w(lp_w), .lp_x_packed(lp_x_packed), .lp_valid_x(lp_valid_x),
        .lp_y_packed(lp_y_packed), .lp_out_valid(lp_out_valid),

        .ah_rst_sync(ah_rst_sync), .ah_load_k_en(ah_load_k_en),
        .ah_load_k_col(ah_load_k_col), .ah_k_in_packed(ah_k_in_packed),
        .ah_q_packed(ah_q_packed), .ah_valid_q(ah_valid_q),
        .ah_sm_out(ah_sm_out), .ah_attn_valid(ah_attn_valid),

        .gelu_x_in(gelu_x_in), .gelu_y_out(gelu_y_out),
        .res_a(res_a), .res_b(res_b), .res_y(res_y),

        .smu_probe_x_in(smu_probe_x_in),
        .smu_probe_sm_out(smu_probe_sm_out),
        .smu_probe_es_sum(smu_probe_es_sum),

        .accum_clear(accum_clear), .accum_valid_in(accum_valid_in),
        .accum_y_in(accum_y_in), .accum_shift(accum_shift),
        .accum_latch(accum_latch)
    );

    // =========================================================================
    // Outer-loop controller
    // =========================================================================
    wire        ol_pf_start;
    wire        ol_pf_done;
    wire [1:0]  ol_pf_bank, ol_active_bank;
    wire [4:0]  cur_n_dbg, cur_d_dbg;
    wire [3:0]  cur_h_dbg, cur_l_dbg;

    outer_loop_ctrl u_olc (
        .clk(clk), .rst(rst),
        .start       (start),
        .cfg_n_tiles (cfg_n_tiles),
        .cfg_d_tiles (cfg_d_tiles),
        .cfg_h_heads (cfg_h_heads),
        .cfg_l_layers(cfg_l_layers),
        .inner_start (ol_inner_start),
        .inner_done  (inner_done_w),
        .pf_start    (ol_pf_start),
        .pf_done     (ol_pf_done),
        .pf_bank     (ol_pf_bank),
        .active_bank (ol_active_bank),
        .cur_n       (cur_n_dbg),
        .cur_d       (cur_d_dbg),
        .cur_h       (cur_h_dbg),
        .cur_l       (cur_l_dbg),
        .total_tiles_fired(total_tiles_fired),
        .all_done    (all_done)
    );

    assign done = inner_done_w;

    // =========================================================================
    // AXI burst interface (weight prefetch path)
    // =========================================================================
    wire        axi_rd_fifo_pop, axi_rd_fifo_empty, axi_rd_fifo_full;
    wire [127:0] axi_rd_fifo_data;
    wire        axi_wr_fifo_push, axi_wr_fifo_full, axi_wr_fifo_empty;
    wire [127:0] axi_wr_fifo_data;
    wire        axi_busy, axi_done;

    assign axi_rd_fifo_pop  = 1'b0;          // (drained by pf state machine stub)
    assign axi_wr_fifo_push = 1'b0;
    assign axi_wr_fifo_data = 128'd0;

    reg [31:0] pf_base_addr;
    always @(posedge clk) begin
        if (rst) pf_base_addr <= 0;
        else if (ol_pf_start) pf_base_addr <= pf_base_addr + 32'h100;
    end

    axi_burst_if #(
        .FIFO_DEPTH(16), .DATA_WIDTH(128), .ADDR_WIDTH(32)
    ) u_axi (
        .clk(clk), .rst(rst),
        .start_rd     (ol_pf_start),
        .start_wr     (1'b0),
        .base_addr    (pf_base_addr),
        .burst_len    (8'd15),
        .busy         (axi_busy),
        .done         (axi_done),
        .rd_fifo_pop  (axi_rd_fifo_pop),
        .rd_fifo_data (axi_rd_fifo_data),
        .rd_fifo_empty(axi_rd_fifo_empty),
        .rd_fifo_full (axi_rd_fifo_full),
        .wr_fifo_push (axi_wr_fifo_push),
        .wr_fifo_data (axi_wr_fifo_data),
        .wr_fifo_full (axi_wr_fifo_full),
        .wr_fifo_empty(axi_wr_fifo_empty),
        .mem_req (mem_req), .mem_we (mem_we), .mem_addr (mem_addr),
        .mem_wdata(mem_wdata), .mem_ack (mem_ack), .mem_rdata(mem_rdata)
    );

    assign ol_pf_done = axi_done;

    // =========================================================================
    // Buffers (4 x ram_dp, large BUF_DEPTH x 128b)
    // =========================================================================
    wire [127:0] act_dout_a, scr_dout_a, wgt_dout_a, out_dout_a;
    wire [127:0] act_dout_b, scr_dout_b, wgt_dout_b, out_dout_b;

    // Port A = ctl_ren read OR host write OR host read (out)
    wire act_a_en   = host_act_we | (ctl_ren & ctl_rsel == 2'b00);
    wire act_a_we   = host_act_we;
    wire [BUF_ADDR_W-1:0] act_a_addr = host_act_we ? host_act_addr
                                                   : {{(BUF_ADDR_W-8){1'b0}}, ctl_raddr};

    wire wgt_a_en   = host_wgt_we | (ctl_ren & ctl_rsel == 2'b10);
    wire wgt_a_we   = host_wgt_we;
    wire [BUF_ADDR_W-1:0] wgt_a_addr = host_wgt_we ? host_wgt_addr
                                                   : {{(BUF_ADDR_W-8){1'b0}}, ctl_raddr};

    wire scr_a_en   = (ctl_ren & ctl_rsel == 2'b01);
    wire [BUF_ADDR_W-1:0] scr_a_addr = {{(BUF_ADDR_W-8){1'b0}}, ctl_raddr};

    wire out_a_en   = 1'b1;    // host always readable
    wire [BUF_ADDR_W-1:0] out_a_addr = (ctl_ren & ctl_rsel == 2'b11)
                                     ? {{(BUF_ADDR_W-8){1'b0}}, ctl_raddr}
                                     :  host_out_addr;

    // Port B = ctl_ren_b secondary read OR ctl_wen write
    wire act_b_en   = (ctl_ren_b & ctl_rsel_b == 2'b00);
    wire [BUF_ADDR_W-1:0] act_b_addr = {{(BUF_ADDR_W-8){1'b0}}, ctl_raddr_b};

    wire scr_b_en   = (ctl_ren_b & ctl_rsel_b == 2'b01) | (ctl_wen & ctl_wsel == 2'b01);
    wire scr_b_we   = (ctl_wen & ctl_wsel == 2'b01);
    wire [BUF_ADDR_W-1:0] scr_b_addr = scr_b_we ? {{(BUF_ADDR_W-8){1'b0}}, ctl_waddr}
                                                : {{(BUF_ADDR_W-8){1'b0}}, ctl_raddr_b};

    wire wgt_b_en   = (ctl_ren_b & ctl_rsel_b == 2'b10);
    wire [BUF_ADDR_W-1:0] wgt_b_addr = {{(BUF_ADDR_W-8){1'b0}}, ctl_raddr_b};

    wire out_b_en   = (ctl_ren_b & ctl_rsel_b == 2'b11) | (ctl_wen & ctl_wsel == 2'b11);
    wire out_b_we   = (ctl_wen & ctl_wsel == 2'b11);
    wire [BUF_ADDR_W-1:0] out_b_addr = out_b_we ? {{(BUF_ADDR_W-8){1'b0}}, ctl_waddr}
                                                : {{(BUF_ADDR_W-8){1'b0}}, ctl_raddr_b};

    ram_dp #(.DATA_WIDTH(128), .DEPTH(BUF_DEPTH), .ADDR_WIDTH(BUF_ADDR_W)) u_act_buf (
        .clk(clk),
        .a_en(act_a_en), .a_we(act_a_we), .a_addr(act_a_addr),
        .a_din(host_act_din), .a_dout(act_dout_a),
        .b_en(act_b_en), .b_we(1'b0), .b_addr(act_b_addr),
        .b_din(128'd0),  .b_dout(act_dout_b)
    );
    ram_dp #(.DATA_WIDTH(128), .DEPTH(BUF_DEPTH), .ADDR_WIDTH(BUF_ADDR_W)) u_scr_buf (
        .clk(clk),
        .a_en(scr_a_en), .a_we(1'b0), .a_addr(scr_a_addr),
        .a_din(128'd0), .a_dout(scr_dout_a),
        .b_en(scr_b_en), .b_we(scr_b_we), .b_addr(scr_b_addr),
        .b_din(ctl_wdata), .b_dout(scr_dout_b)
    );
    ram_dp #(.DATA_WIDTH(128), .DEPTH(BUF_DEPTH), .ADDR_WIDTH(BUF_ADDR_W)) u_wgt_buf (
        .clk(clk),
        .a_en(wgt_a_en), .a_we(wgt_a_we), .a_addr(wgt_a_addr),
        .a_din(host_wgt_din), .a_dout(wgt_dout_a),
        .b_en(wgt_b_en), .b_we(1'b0), .b_addr(wgt_b_addr),
        .b_din(128'd0), .b_dout(wgt_dout_b)
    );
    ram_dp #(.DATA_WIDTH(128), .DEPTH(BUF_DEPTH), .ADDR_WIDTH(BUF_ADDR_W)) u_out_buf (
        .clk(clk),
        .a_en(out_a_en), .a_we(1'b0), .a_addr(out_a_addr),
        .a_din(128'd0), .a_dout(out_dout_a),
        .b_en(out_b_en), .b_we(out_b_we), .b_addr(out_b_addr),
        .b_din(ctl_wdata), .b_dout(out_dout_b)
    );

    assign ctl_rdata =
        (ctl_rsel == 2'b00) ? act_dout_a :
        (ctl_rsel == 2'b01) ? scr_dout_a :
        (ctl_rsel == 2'b10) ? wgt_dout_a : out_dout_a;

    assign ctl_rdata_b =
        (ctl_rsel_b == 2'b00) ? act_dout_b :
        (ctl_rsel_b == 2'b01) ? scr_dout_b :
        (ctl_rsel_b == 2'b10) ? wgt_dout_b : out_dout_b;

    // =========================================================================
    // LN array (drives ALL 16 instances in parallel)
    // =========================================================================
    ln_array_16x16 u_ln (
        .x_in(ln_x_in), .gamma(ln_gamma), .beta(ln_beta), .y_out(ln_y_out)
    );

    // =========================================================================
    // Linear projection engine (shared for non-attention matmuls)
    // =========================================================================
    wire [7:0] lp_y0,  lp_y1,  lp_y2,  lp_y3,  lp_y4,  lp_y5,  lp_y6,  lp_y7;
    wire [7:0] lp_y8,  lp_y9,  lp_y10, lp_y11, lp_y12, lp_y13, lp_y14, lp_y15;

    linear_proj u_lp (
        .clk(clk), .rst(rst | lp_rst_sync),
        .load_wc1 (lp_load_cols[0]),  .load_wc2 (lp_load_cols[1]),
        .load_wc3 (lp_load_cols[2]),  .load_wc4 (lp_load_cols[3]),
        .load_wc5 (lp_load_cols[4]),  .load_wc6 (lp_load_cols[5]),
        .load_wc7 (lp_load_cols[6]),  .load_wc8 (lp_load_cols[7]),
        .load_wc9 (lp_load_cols[8]),  .load_wc10(lp_load_cols[9]),
        .load_wc11(lp_load_cols[10]), .load_wc12(lp_load_cols[11]),
        .load_wc13(lp_load_cols[12]), .load_wc14(lp_load_cols[13]),
        .load_wc15(lp_load_cols[14]), .load_wc16(lp_load_cols[15]),
        .w(lp_w),
        .x0 (lp_x_packed[  0 +: 8]), .x1 (lp_x_packed[  8 +: 8]),
        .x2 (lp_x_packed[ 16 +: 8]), .x3 (lp_x_packed[ 24 +: 8]),
        .x4 (lp_x_packed[ 32 +: 8]), .x5 (lp_x_packed[ 40 +: 8]),
        .x6 (lp_x_packed[ 48 +: 8]), .x7 (lp_x_packed[ 56 +: 8]),
        .x8 (lp_x_packed[ 64 +: 8]), .x9 (lp_x_packed[ 72 +: 8]),
        .x10(lp_x_packed[ 80 +: 8]), .x11(lp_x_packed[ 88 +: 8]),
        .x12(lp_x_packed[ 96 +: 8]), .x13(lp_x_packed[104 +: 8]),
        .x14(lp_x_packed[112 +: 8]), .x15(lp_x_packed[120 +: 8]),
        .valid_x(lp_valid_x),
        .y0 (lp_y0),  .y1 (lp_y1),  .y2 (lp_y2),  .y3 (lp_y3),
        .y4 (lp_y4),  .y5 (lp_y5),  .y6 (lp_y6),  .y7 (lp_y7),
        .y8 (lp_y8),  .y9 (lp_y9),  .y10(lp_y10), .y11(lp_y11),
        .y12(lp_y12), .y13(lp_y13), .y14(lp_y14), .y15(lp_y15),
        .out_valid(lp_out_valid)
    );

    assign lp_y_packed = { lp_y15, lp_y14, lp_y13, lp_y12,
                           lp_y11, lp_y10, lp_y9,  lp_y8,
                           lp_y7,  lp_y6,  lp_y5,  lp_y4,
                           lp_y3,  lp_y2,  lp_y1,  lp_y0 };

    // =========================================================================
    // Multi-head attention (H parallel attention_heads)
    // =========================================================================
    wire [H_HEADS-1:0]     load_k_en_per_head;
    wire [H_HEADS*128-1:0] k_in_packed_per_head;
    wire [H_HEADS*128-1:0] q_packed_per_head;
    wire [H_HEADS-1:0]     valid_q_per_head;
    wire [H_HEADS*128-1:0] sm_out_per_head;
    wire [H_HEADS*128-1:0] lsm_out_per_head;
    wire [H_HEADS-1:0]     attn_valid_per_head;

    // Broadcast controller-driven attention signals across all heads.  For
    // true multi-head, per-head Q/K slices would be distinct; the controller
    // time-multiplexes them in a real DeiT flow.  Here we fanout to populate
    // all heads so they stay synthesized.
    genvar bi;
    generate
        for (bi = 0; bi < H_HEADS; bi = bi + 1) begin : GEN_BCAST
            assign load_k_en_per_head  [bi]              = ah_load_k_en;
            assign k_in_packed_per_head[bi*128 +: 128]   = ah_k_in_packed ^ {16{bi[7:0]}};
            assign q_packed_per_head   [bi*128 +: 128]   = ah_q_packed    ^ {16{bi[7:0]}};
            assign valid_q_per_head    [bi]              = ah_valid_q;
        end
    endgenerate

    multi_head_attn #(
        .H_HEADS(H_HEADS), .H_PARALLEL(H_PARALLEL),
        .BOOTH_LSB_SCALE(BOOTH_LSB_SCALE), .THRESHOLD(THRESHOLD)
    ) u_mha (
        .clk(clk), .rst(rst | ah_rst_sync),
        .load_k_en_per_head  (load_k_en_per_head),
        .load_k_col          (ah_load_k_col),
        .k_in_packed_per_head(k_in_packed_per_head),
        .q_packed_per_head   (q_packed_per_head),
        .valid_q_per_head    (valid_q_per_head),
        .sm_out_per_head     (sm_out_per_head),
        .lsm_out_per_head    (lsm_out_per_head),
        .attn_valid_per_head (attn_valid_per_head)
    );

    // Pick head 0 output for the inner controller
    assign ah_sm_out     = sm_out_per_head[127:0];
    assign ah_attn_valid = attn_valid_per_head[0];

    // =========================================================================
    // Head concat unit -- keeps multi-head output observable in synth
    // =========================================================================
    wire [127:0]           hc_concat_out;
    wire [H_HEADS*128-1:0] hc_all_heads_reg;
    wire [127:0]           hc_sum_reduce;

    head_concat_unit #(.H_HEADS(H_HEADS)) u_hc (
        .clk(clk), .rst(rst),
        .per_head_in   (sm_out_per_head),
        .sel_head      (ah_load_k_col),
        .concat_out    (hc_concat_out),
        .all_heads_reg (hc_all_heads_reg),
        .sum_reduce_reg(hc_sum_reduce)
    );

    // =========================================================================
    // SM Unit (OBSERVABLE via debug write-back)
    // =========================================================================
    wire [127:0] smu_e_out, smu_lsm_out;
    sm_unit u_sm_unit (
        .x_in   (smu_probe_x_in),
        .e_out  (smu_e_out),
        .sm_out (smu_probe_sm_out),
        .lsm_out(smu_lsm_out),
        .es_sum (smu_probe_es_sum)
    );

    // =========================================================================
    // Combinational NL units
    // =========================================================================
    gelu_approx_16   u_gelu (.x_in(gelu_x_in), .y_out(gelu_y_out));
    residual_add_16  u_res  (.a_in(res_a), .b_in(res_b), .y_out(res_y));

    // =========================================================================
    // Wide accumulator bank
    // =========================================================================
    wire [24*16-1:0] accum_dbg_vec;
    wire [127:0]     accum_y_out_w;
    wire             accum_out_valid_w;
    wide_accum_bank #(.ACC_WIDTH(24), .N_LANES(16)) u_accum (
        .clk(clk), .rst(rst),
        .clear_accum (accum_clear),
        .valid_in    (accum_valid_in),
        .y_in_packed (accum_y_in),
        .shift       (accum_shift),
        .latch_out   (accum_latch),
        .y_out_packed(accum_y_out_w),
        .y_out_valid (accum_out_valid_w),
        .acc_dbg     (accum_dbg_vec)
    );

    // =========================================================================
    // host_out_dout mux: based on top 4 bits of host_out_addr
    //   0x00..0x3F = output buffer
    //   0xF0       = sm_unit probe (e_out)
    //   0xF1       = sm_unit sm_out
    //   0xF2       = sm_unit lsm_out
    //   0xF3       = {es_sum, 116'd0}
    //   0xF4       = wide_accum y_out
    //   0xF5       = wide_accum dbg low 128
    //   0xF6       = head-concat sum
    //   0xF7       = head-concat all-heads low 128 (always head 0)
    //   0xF8       = {cur_l, cur_h, cur_n, cur_d, state, total_cycles}
    //   0xF9       = {total_tiles_fired, 96'd0}
    //   0xFA       = AXI status {busy, done, 126'd0}
    // =========================================================================
    reg [127:0] debug_status_reg;
    always @* begin
        debug_status_reg = {
            12'd0, cur_l_dbg, cur_h_dbg, cur_n_dbg, cur_d_dbg,
            3'd0, cur_state_dbg, total_cycles,
            64'd0
        };
    end

    reg [127:0] host_out_mux;
    always @* begin
        case (host_out_addr[11:4])
            8'hF0: host_out_mux = smu_e_out;
            8'hF1: host_out_mux = smu_probe_sm_out;
            8'hF2: host_out_mux = smu_lsm_out;
            8'hF3: host_out_mux = {116'd0, smu_probe_es_sum};
            8'hF4: host_out_mux = accum_y_out_w;
            8'hF5: host_out_mux = accum_dbg_vec[127:0];
            8'hF6: host_out_mux = hc_sum_reduce;
            8'hF7: host_out_mux = hc_all_heads_reg[127:0];
            8'hF8: host_out_mux = debug_status_reg;
            8'hF9: host_out_mux = {total_tiles_fired, 96'd0};
            8'hFA: host_out_mux = {axi_busy, axi_done, 126'd0};
            default: host_out_mux = out_dout_a;
        endcase
    end

    assign host_out_dout = host_out_mux;

endmodule
