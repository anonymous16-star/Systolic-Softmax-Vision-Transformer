`timescale 1ns / 1ps
// =============================================================================
// boostvit_controller.sv  --  Master FSM (v2: real residual, full LN, obs)
// =============================================================================

module boostvit_controller (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    output reg         done,
    output reg [7:0]   phase_cycles_0,
    output reg [15:0]  total_cycles,
    output reg [4:0]   cur_state_dbg,

    // Buffer port A (primary read)
    output reg         buf_ren,
    output reg [1:0]   buf_sel,
    output reg [7:0]   buf_raddr,
    input  wire [127:0] buf_rdata,

    // Buffer port B (secondary read)
    output reg         buf_ren_b,
    output reg [1:0]   buf_sel_b,
    output reg [7:0]   buf_raddr_b,
    input  wire [127:0] buf_rdata_b,

    // Controller write
    output reg         buf_wen,
    output reg [1:0]   buf_wsel,
    output reg [7:0]   buf_waddr,
    output reg [127:0] buf_wdata,

    // LN array
    output reg  [2047:0] ln_x_in,
    output reg  [127:0]  ln_gamma,
    output reg  [127:0]  ln_beta,
    input  wire [2047:0] ln_y_out,

    // Linear projection engine
    output reg         lp_rst_sync,
    output reg [15:0]  lp_load_cols,
    output reg [127:0] lp_w,
    output reg [127:0] lp_x_packed,
    output reg         lp_valid_x,
    input  wire [127:0] lp_y_packed,
    input  wire        lp_out_valid,

    // Attention engine
    output reg         ah_rst_sync,
    output reg         ah_load_k_en,
    output reg [3:0]   ah_load_k_col,
    output reg [127:0] ah_k_in_packed,
    output reg [127:0] ah_q_packed,
    output reg         ah_valid_q,
    input  wire [127:0] ah_sm_out,
    input  wire        ah_attn_valid,

    // GELU + residual
    output reg  [127:0] gelu_x_in,
    input  wire [127:0] gelu_y_out,
    output reg  [127:0] res_a,
    output reg  [127:0] res_b,
    input  wire [127:0] res_y,

    // SM Unit observability
    output reg  [127:0] smu_probe_x_in,
    input  wire [127:0] smu_probe_sm_out,
    input  wire [11:0]  smu_probe_es_sum,

    // Wide accum bank
    output reg         accum_clear,
    output reg         accum_valid_in,
    output reg  [127:0] accum_y_in,
    output reg  [4:0]  accum_shift,
    output reg         accum_latch
);

    localparam S_IDLE        = 5'd0;
    localparam S_LN1_LOAD    = 5'd1;
    localparam S_LN1_STORE   = 5'd2;
    localparam S_WQ_LOAD     = 5'd3;
    localparam S_WQ_STREAM   = 5'd4;
    localparam S_WQ_CAPTURE  = 5'd5;
    localparam S_WK_LOAD     = 5'd6;
    localparam S_WK_STREAM   = 5'd7;
    localparam S_WK_CAPTURE  = 5'd8;
    localparam S_WV_LOAD     = 5'd9;
    localparam S_WV_STREAM   = 5'd10;
    localparam S_WV_CAPTURE  = 5'd11;
    localparam S_QK_K_LOAD   = 5'd12;
    localparam S_QK_STREAM   = 5'd13;
    localparam S_AV_V_LOAD   = 5'd14;
    localparam S_AV_STREAM   = 5'd15;
    localparam S_AV_CAPTURE  = 5'd16;
    localparam S_WO_LOAD     = 5'd17;
    localparam S_WO_STREAM   = 5'd18;
    localparam S_WO_CAPTURE  = 5'd19;
    localparam S_RES1        = 5'd20;
    localparam S_LN2_LOAD    = 5'd21;
    localparam S_LN2_STORE   = 5'd22;
    localparam S_MLP1_LOAD   = 5'd23;
    localparam S_MLP1_STREAM = 5'd24;
    localparam S_MLP1_CAP    = 5'd25;
    localparam S_GELU        = 5'd26;
    localparam S_MLP2_LOAD   = 5'd27;
    localparam S_MLP2_STREAM = 5'd28;
    localparam S_MLP2_CAP    = 5'd29;
    localparam S_RES2        = 5'd30;
    localparam S_DONE        = 5'd31;

    localparam BUF_ACT     = 2'b00;
    localparam BUF_SCRATCH = 2'b01;
    localparam BUF_WEIGHT  = 2'b10;
    localparam BUF_OUT     = 2'b11;

    localparam integer NT = 16;
    localparam integer DT = 16;
    localparam integer LP_DRAIN = 12;

    reg [4:0]   state;
    reg [5:0]   cnt;
    reg [15:0]  total_c;
    reg [7:0]   ph0_c;

    reg [2047:0] ln_batch_reg;
    reg [2047:0] ln_y_latched;

    // Counts lp_out_valid pulses within a CAPTURE state; used as the
    // real write index (LP_DRAIN gating was wrong because out_valid
    // actually fires during CAPTURE cnt = 0..12, not 12..27).
    reg [4:0] lp_wr_cnt;
    reg [4:0] prev_state;
    always @(posedge clk) begin
        if (rst) begin
            lp_wr_cnt  <= 0;
            prev_state <= S_IDLE;
        end else begin
            prev_state <= state;
            if (state != prev_state) lp_wr_cnt <= 0;
            else if (lp_out_valid &&
                     (state == S_WQ_CAPTURE || state == S_WK_CAPTURE ||
                      state == S_WV_CAPTURE || state == S_AV_CAPTURE ||
                      state == S_WO_CAPTURE || state == S_MLP1_CAP  ||
                      state == S_MLP2_CAP))
                lp_wr_cnt <= lp_wr_cnt + 1;
        end
    end

    integer li;
    always @(posedge clk) begin
        if (rst) begin
            state          <= S_IDLE;
            cnt            <= 6'd0;
            total_c        <= 16'd0;
            ph0_c          <= 8'd0;
            done           <= 1'b0;
            total_cycles   <= 16'd0;
            phase_cycles_0 <= 8'd0;
            ln_batch_reg   <= 2048'd0;
            ln_y_latched   <= 2048'd0;
            cur_state_dbg  <= 5'd0;
        end else begin
            cur_state_dbg <= state;
            case (state)
                S_IDLE: begin
                    done         <= 1'b0;
                    cnt          <= 6'd0;
                    total_c      <= 16'd0;
                    ph0_c        <= 8'd0;
                    if (start) state <= S_LN1_LOAD;
                end

                S_LN1_LOAD: begin
                    total_c <= total_c + 1;
                    ph0_c   <= ph0_c + 1;
                    if (cnt >= 1 && cnt <= NT)
                        ln_batch_reg[(cnt-1)*128 +: 128] <= buf_rdata;
                    if (cnt == NT) begin
                        ln_y_latched   <= ln_y_out;
                        phase_cycles_0 <= ph0_c + 1;
                        cnt            <= 0;
                        state          <= S_LN1_STORE;
                    end else cnt <= cnt + 1;
                end

                S_LN1_STORE: begin
                    total_c <= total_c + 1;
                    if (cnt == NT-1) begin cnt <= 0; state <= S_WQ_LOAD; end
                    else              cnt <= cnt + 1;
                end

                S_WQ_LOAD: begin
                    total_c <= total_c + 1;
                    if (cnt == DT) begin cnt <= 0; state <= S_WQ_STREAM; end
                    else           cnt <= cnt + 1;
                end
                S_WQ_STREAM: begin
                    total_c <= total_c + 1;
                    if (cnt == NT) begin cnt <= 0; state <= S_WQ_CAPTURE; end
                    else             cnt <= cnt + 1;
                end
                S_WQ_CAPTURE: begin
                    total_c <= total_c + 1;
                    if (cnt == LP_DRAIN + NT) begin cnt <= 0; state <= S_WK_LOAD; end
                    else                         cnt <= cnt + 1;
                end
                S_WK_LOAD: begin
                    total_c <= total_c + 1;
                    if (cnt == DT) begin cnt <= 0; state <= S_WK_STREAM; end
                    else           cnt <= cnt + 1;
                end
                S_WK_STREAM: begin
                    total_c <= total_c + 1;
                    if (cnt == NT) begin cnt <= 0; state <= S_WK_CAPTURE; end
                    else             cnt <= cnt + 1;
                end
                S_WK_CAPTURE: begin
                    total_c <= total_c + 1;
                    if (cnt == LP_DRAIN + NT) begin cnt <= 0; state <= S_WV_LOAD; end
                    else                         cnt <= cnt + 1;
                end
                S_WV_LOAD: begin
                    total_c <= total_c + 1;
                    if (cnt == DT) begin cnt <= 0; state <= S_WV_STREAM; end
                    else           cnt <= cnt + 1;
                end
                S_WV_STREAM: begin
                    total_c <= total_c + 1;
                    if (cnt == NT) begin cnt <= 0; state <= S_WV_CAPTURE; end
                    else             cnt <= cnt + 1;
                end
                S_WV_CAPTURE: begin
                    total_c <= total_c + 1;
                    if (cnt == LP_DRAIN + NT) begin cnt <= 0; state <= S_QK_K_LOAD; end
                    else                         cnt <= cnt + 1;
                end
                S_QK_K_LOAD: begin
                    total_c <= total_c + 1;
                    if (cnt == NT) begin cnt <= 0; state <= S_QK_STREAM; end
                    else           cnt <= cnt + 1;
                end
                S_QK_STREAM: begin
                    total_c <= total_c + 1;
                    if (cnt == NT + 10) begin cnt <= 0; state <= S_AV_V_LOAD; end
                    else                     cnt <= cnt + 1;
                end
                S_AV_V_LOAD: begin
                    total_c <= total_c + 1;
                    if (cnt == DT) begin cnt <= 0; state <= S_AV_STREAM; end
                    else             cnt <= cnt + 1;
                end
                S_AV_STREAM: begin
                    total_c <= total_c + 1;
                    if (cnt == NT) begin cnt <= 0; state <= S_AV_CAPTURE; end
                    else             cnt <= cnt + 1;
                end
                S_AV_CAPTURE: begin
                    total_c <= total_c + 1;
                    if (cnt == LP_DRAIN + NT) begin cnt <= 0; state <= S_WO_LOAD; end
                    else                         cnt <= cnt + 1;
                end
                S_WO_LOAD: begin
                    total_c <= total_c + 1;
                    if (cnt == DT) begin cnt <= 0; state <= S_WO_STREAM; end
                    else             cnt <= cnt + 1;
                end
                S_WO_STREAM: begin
                    total_c <= total_c + 1;
                    if (cnt == NT) begin cnt <= 0; state <= S_WO_CAPTURE; end
                    else             cnt <= cnt + 1;
                end
                S_WO_CAPTURE: begin
                    total_c <= total_c + 1;
                    if (cnt == LP_DRAIN + NT) begin cnt <= 0; state <= S_RES1; end
                    else                         cnt <= cnt + 1;
                end

                S_RES1: begin
                    total_c <= total_c + 1;
                    if (cnt == NT) begin cnt <= 0; state <= S_LN2_LOAD; end
                    else            cnt <= cnt + 1;
                end

                S_LN2_LOAD: begin
                    total_c <= total_c + 1;
                    if (cnt >= 1 && cnt <= NT)
                        ln_batch_reg[(cnt-1)*128 +: 128] <= buf_rdata;
                    if (cnt == NT) begin
                        ln_y_latched <= ln_y_out;
                        cnt          <= 0;
                        state        <= S_LN2_STORE;
                    end else cnt <= cnt + 1;
                end

                S_LN2_STORE: begin
                    total_c <= total_c + 1;
                    if (cnt == NT-1) begin cnt <= 0; state <= S_MLP1_LOAD; end
                    else              cnt <= cnt + 1;
                end

                S_MLP1_LOAD: begin
                    total_c <= total_c + 1;
                    if (cnt == DT) begin cnt <= 0; state <= S_MLP1_STREAM; end
                    else             cnt <= cnt + 1;
                end
                S_MLP1_STREAM: begin
                    total_c <= total_c + 1;
                    if (cnt == NT) begin cnt <= 0; state <= S_MLP1_CAP; end
                    else             cnt <= cnt + 1;
                end
                S_MLP1_CAP: begin
                    total_c <= total_c + 1;
                    if (cnt == LP_DRAIN + NT) begin cnt <= 0; state <= S_GELU; end
                    else                         cnt <= cnt + 1;
                end
                S_GELU: begin
                    total_c <= total_c + 1;
                    if (cnt == NT-1) begin cnt <= 0; state <= S_MLP2_LOAD; end
                    else             cnt <= cnt + 1;
                end
                S_MLP2_LOAD: begin
                    total_c <= total_c + 1;
                    if (cnt == DT) begin cnt <= 0; state <= S_MLP2_STREAM; end
                    else             cnt <= cnt + 1;
                end
                S_MLP2_STREAM: begin
                    total_c <= total_c + 1;
                    if (cnt == NT) begin cnt <= 0; state <= S_MLP2_CAP; end
                    else             cnt <= cnt + 1;
                end
                S_MLP2_CAP: begin
                    total_c <= total_c + 1;
                    if (cnt == LP_DRAIN + NT) begin cnt <= 0; state <= S_RES2; end
                    else                         cnt <= cnt + 1;
                end
                S_RES2: begin
                    total_c <= total_c + 1;
                    if (cnt == NT) begin cnt <= 0; state <= S_DONE; end
                    else            cnt <= cnt + 1;
                end
                S_DONE: begin
                    done         <= 1'b1;
                    total_cycles <= total_c;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    // ---- Combinational outputs ----
    integer gi;
    always @* begin
        buf_ren      = 1'b0; buf_sel      = BUF_ACT;     buf_raddr    = cnt;
        buf_ren_b    = 1'b0; buf_sel_b    = BUF_OUT;     buf_raddr_b  = cnt;
        buf_wen      = 1'b0; buf_wsel     = BUF_SCRATCH; buf_waddr    = cnt;
        buf_wdata    = 128'd0;

        ln_x_in      = ln_batch_reg;
        ln_gamma     = 128'd0;
        ln_beta      = 128'd0;
        for (gi = 0; gi < 16; gi = gi + 1) ln_gamma[gi*8 +: 8] = 8'd128;

        lp_rst_sync  = 1'b0;
        lp_load_cols = 16'd0;
        lp_w         = 128'd0;
        lp_x_packed  = 128'd0;
        lp_valid_x   = 1'b0;

        ah_rst_sync    = 1'b0;
        ah_load_k_en   = 1'b0;
        ah_load_k_col  = 4'd0;
        ah_k_in_packed = 128'd0;
        ah_q_packed    = 128'd0;
        ah_valid_q     = 1'b0;

        gelu_x_in    = 128'd0;
        res_a        = 128'd0;
        res_b        = 128'd0;
        // Non-zero default so post-sim observability reads at sm_unit
        // addresses return determinate values.  Overridden below in LN/QK states.
        smu_probe_x_in = 128'h10203040504030201000F0E0D0C0B0A0;

        accum_clear    = 1'b0;
        accum_valid_in = 1'b0;
        accum_y_in     = 128'd0;
        accum_shift    = 5'd0;
        accum_latch    = 1'b0;

        case (state)
            S_LN1_LOAD: begin
                buf_ren = 1'b1; buf_sel = BUF_ACT; buf_raddr = cnt;
            end
            S_LN1_STORE: begin
                buf_wen   = 1'b1; buf_wsel = BUF_SCRATCH; buf_waddr = cnt;
                buf_wdata = ln_y_latched[cnt*128 +: 128];
                smu_probe_x_in = ln_y_latched[cnt*128 +: 128];
            end

            S_WQ_LOAD, S_WK_LOAD, S_WV_LOAD, S_AV_V_LOAD, S_WO_LOAD,
            S_MLP1_LOAD, S_MLP2_LOAD: begin
                // Issue read at cnt=0..DT-1, data arrives 1 cycle later
                buf_ren   = 1'b1; buf_sel = BUF_WEIGHT; buf_raddr = cnt;
                lp_w      = buf_rdata;
                // Latch col = cnt-1 once data is valid (cnt >= 1)
                if (cnt >= 1 && cnt <= DT)
                    lp_load_cols[(cnt - 1) & 4'hF] = 1'b1;
                accum_clear = 1'b1;
            end

            S_QK_K_LOAD: begin
                buf_ren = 1'b1; buf_sel = BUF_SCRATCH; buf_raddr = 8'd16 + cnt;
                if (cnt >= 1 && cnt <= NT) begin
                    ah_load_k_en   = 1'b1;
                    ah_load_k_col  = (cnt - 1) & 4'hF;
                    ah_k_in_packed = buf_rdata;
                end
            end

            S_WQ_STREAM, S_WK_STREAM, S_WV_STREAM: begin
                buf_ren = 1'b1; buf_sel = BUF_SCRATCH; buf_raddr = cnt;
                lp_x_packed = buf_rdata;
                lp_valid_x  = (cnt >= 1 && cnt <= NT);
            end

            S_QK_STREAM: begin
                buf_ren = 1'b1; buf_sel = BUF_SCRATCH; buf_raddr = cnt;
                ah_q_packed = buf_rdata; ah_valid_q = (cnt < NT);
                if (ah_attn_valid) begin
                    buf_wen   = 1'b1; buf_wsel = BUF_SCRATCH;
                    buf_waddr = 8'd32 + cnt; buf_wdata = ah_sm_out;
                    smu_probe_x_in = ah_sm_out;
                end
            end

            S_AV_STREAM: begin
                buf_ren = 1'b1; buf_sel = BUF_SCRATCH; buf_raddr = 8'd32 + cnt;
                lp_x_packed = buf_rdata;
                lp_valid_x  = (cnt >= 1 && cnt <= NT);
            end

            S_WO_STREAM, S_MLP1_STREAM, S_MLP2_STREAM: begin
                buf_ren = 1'b1; buf_sel = BUF_SCRATCH; buf_raddr = cnt;
                lp_x_packed = buf_rdata;
                lp_valid_x  = (cnt >= 1 && cnt <= NT);
            end

            S_WQ_CAPTURE: begin
                if (lp_out_valid && lp_wr_cnt < NT) begin
                    buf_wen   = 1'b1; buf_wsel = BUF_SCRATCH; buf_waddr = lp_wr_cnt;
                    buf_wdata = lp_y_packed;
                    accum_valid_in = 1'b1; accum_y_in = lp_y_packed;
                end
            end
            S_WK_CAPTURE: begin
                if (lp_out_valid && lp_wr_cnt < NT) begin
                    buf_wen = 1'b1; buf_wsel = BUF_SCRATCH;
                    buf_waddr = 8'd16 + lp_wr_cnt; buf_wdata = lp_y_packed;
                    accum_valid_in = 1'b1; accum_y_in = lp_y_packed;
                end
            end
            S_WV_CAPTURE: begin
                if (lp_out_valid && lp_wr_cnt < NT) begin
                    buf_wen = 1'b1; buf_wsel = BUF_SCRATCH;
                    buf_waddr = 8'd48 + lp_wr_cnt; buf_wdata = lp_y_packed;
                    accum_valid_in = 1'b1; accum_y_in = lp_y_packed;
                end
            end
            S_AV_CAPTURE: begin
                if (lp_out_valid && lp_wr_cnt < NT) begin
                    buf_wen = 1'b1; buf_wsel = BUF_SCRATCH;
                    buf_waddr = 8'd64 + lp_wr_cnt; buf_wdata = lp_y_packed;
                    accum_valid_in = 1'b1; accum_y_in = lp_y_packed;
                end
            end
            S_WO_CAPTURE: begin
                if (lp_out_valid && lp_wr_cnt < NT) begin
                    buf_wen = 1'b1; buf_wsel = BUF_SCRATCH;
                    buf_waddr = 8'd160 + lp_wr_cnt;      // scratch[160..175]
                    buf_wdata = lp_y_packed;
                    accum_valid_in = 1'b1; accum_y_in = lp_y_packed;
                    accum_latch    = 1'b1;
                end
            end

            S_RES1: begin
                buf_ren   = 1'b1; buf_sel   = BUF_ACT;     buf_raddr   = cnt;
                buf_ren_b = 1'b1; buf_sel_b = BUF_SCRATCH; buf_raddr_b = 8'd160 + cnt;
                res_a     = buf_rdata;
                res_b     = buf_rdata_b;
                if (cnt >= 1 && cnt <= NT) begin
                    buf_wen   = 1'b1; buf_wsel = BUF_OUT;
                    buf_waddr = 8'd16 + cnt - 1; buf_wdata = res_y;
                end
            end

            S_LN2_LOAD: begin
                buf_ren = 1'b1; buf_sel = BUF_OUT; buf_raddr = 8'd16 + cnt;
            end
            S_LN2_STORE: begin
                buf_wen = 1'b1; buf_wsel = BUF_SCRATCH;
                buf_waddr = 8'd112 + cnt; buf_wdata = ln_y_latched[cnt*128 +: 128];
                smu_probe_x_in = ln_y_latched[cnt*128 +: 128];
            end

            S_MLP1_CAP: begin
                if (lp_out_valid && lp_wr_cnt < NT) begin
                    buf_wen = 1'b1; buf_wsel = BUF_SCRATCH;
                    buf_waddr = 8'd80 + lp_wr_cnt; buf_wdata = lp_y_packed;
                    accum_valid_in = 1'b1; accum_y_in = lp_y_packed;
                end
            end

            S_GELU: begin
                buf_ren = 1'b1; buf_sel = BUF_SCRATCH; buf_raddr = 8'd80 + cnt;
                gelu_x_in = buf_rdata;
                buf_wen   = 1'b1; buf_wsel  = BUF_SCRATCH;
                buf_waddr = 8'd96 + cnt; buf_wdata = gelu_y_out;
            end

            S_MLP2_CAP: begin
                if (lp_out_valid && lp_wr_cnt < NT) begin
                    buf_wen = 1'b1; buf_wsel = BUF_SCRATCH;
                    buf_waddr = 8'd128 + lp_wr_cnt;      // scratch[128..143]
                    buf_wdata = lp_y_packed;
                    accum_valid_in = 1'b1; accum_y_in = lp_y_packed;
                    accum_latch    = 1'b1;
                end
            end

            S_RES2: begin
                buf_ren   = 1'b1; buf_sel   = BUF_OUT;     buf_raddr   = 8'd16 + cnt;
                buf_ren_b = 1'b1; buf_sel_b = BUF_SCRATCH; buf_raddr_b = 8'd128 + cnt;
                res_a     = buf_rdata;
                res_b     = buf_rdata_b;
                if (cnt >= 1 && cnt <= NT) begin
                    buf_wen   = 1'b1; buf_wsel = BUF_OUT;
                    buf_waddr = 8'd48 + cnt - 1; buf_wdata = res_y;
                end
            end

            default: ;
        endcase
    end

endmodule
