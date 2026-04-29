`timescale 1ns / 1ps


module tb_boostvit_accelerator;
    localparam integer H_HEADS = 3;

    reg clk, rst_n, start;
    initial clk = 0;
    always #1 clk = ~clk;

    reg          host_act_we;
    reg  [11:0]  host_act_addr;
    reg  [127:0] host_act_din;
    reg          host_wgt_we;
    reg  [11:0]  host_wgt_addr;
    reg  [127:0] host_wgt_din;
    reg  [11:0]  host_out_addr;

    reg  [4:0]   cfg_n_tiles;
    reg  [4:0]   cfg_d_tiles;
    reg  [3:0]   cfg_h_heads;
    reg  [3:0]   cfg_l_layers;

    wire [127:0] host_out_dout;
    wire         done;
    wire [15:0]  total_cycles;
    wire [4:0]   state_dbg;
    wire         all_done;
    wire [31:0]  total_tiles_fired;

    
    wire         mem_req, mem_we;
    wire [31:0]  mem_addr;
    wire [127:0] mem_wdata;
    reg          mem_ack;
    reg  [127:0] mem_rdata;

    always @(posedge clk) begin
        if (!rst_n) begin
            mem_ack   <= 0;
            mem_rdata <= 0;
        end else begin
            mem_ack   <= mem_req;  
            mem_rdata <= {mem_addr, mem_addr, mem_addr, mem_addr};
        end
    end

    boostvit_accelerator #(
        .H_HEADS(H_HEADS), .H_PARALLEL(1),
        .BUF_DEPTH(4096), .BUF_ADDR_W(12)
    ) DUT (
        .clk(clk), .rst_n(rst_n), .start(start),
        .host_act_we(host_act_we), .host_act_addr(host_act_addr),
        .host_act_din(host_act_din),
        .host_wgt_we(host_wgt_we), .host_wgt_addr(host_wgt_addr),
        .host_wgt_din(host_wgt_din),
        .host_out_addr(host_out_addr), .host_out_dout(host_out_dout),
        .cfg_n_tiles(cfg_n_tiles), .cfg_d_tiles(cfg_d_tiles),
        .cfg_h_heads(cfg_h_heads), .cfg_l_layers(cfg_l_layers),
        .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
        .mem_wdata(mem_wdata), .mem_ack(mem_ack), .mem_rdata(mem_rdata),
        .done(done), .total_cycles(total_cycles),
        .cur_state_dbg(state_dbg), .all_done(all_done),
        .total_tiles_fired(total_tiles_fired)
    );

    function automatic [255:0] state_name;
        input [4:0] s;
        case (s)
            5'd0 :  state_name = "S_IDLE";
            5'd1 :  state_name = "S_LN1_LOAD";
            5'd2 :  state_name = "S_LN1_STORE";
            5'd3 :  state_name = "S_WQ_LOAD";
            5'd4 :  state_name = "S_WQ_STREAM";
            5'd5 :  state_name = "S_WQ_CAPTURE";
            5'd6 :  state_name = "S_WK_LOAD";
            5'd7 :  state_name = "S_WK_STREAM";
            5'd8 :  state_name = "S_WK_CAPTURE";
            5'd9 :  state_name = "S_WV_LOAD";
            5'd10:  state_name = "S_WV_STREAM";
            5'd11:  state_name = "S_WV_CAPTURE";
            5'd12:  state_name = "S_QK_K_LOAD";
            5'd13:  state_name = "S_QK_STREAM";
            5'd14:  state_name = "S_AV_V_LOAD";
            5'd15:  state_name = "S_AV_STREAM";
            5'd16:  state_name = "S_AV_CAPTURE";
            5'd17:  state_name = "S_WO_LOAD";
            5'd18:  state_name = "S_WO_STREAM";
            5'd19:  state_name = "S_WO_CAPTURE";
            5'd20:  state_name = "S_RES1";
            5'd21:  state_name = "S_LN2_LOAD";
            5'd22:  state_name = "S_LN2_STORE";
            5'd23:  state_name = "S_MLP1_LOAD";
            5'd24:  state_name = "S_MLP1_STREAM";
            5'd25:  state_name = "S_MLP1_CAP";
            5'd26:  state_name = "S_GELU";
            5'd27:  state_name = "S_MLP2_LOAD";
            5'd28:  state_name = "S_MLP2_STREAM";
            5'd29:  state_name = "S_MLP2_CAP";
            5'd30:  state_name = "S_RES2";
            5'd31:  state_name = "S_DONE";
            default:state_name = "S_??";
        endcase
    endfunction

    task extrap_config;
        input integer N, D, H, dk;
        input integer toy_total;
        input [47:0]  name;
        integer ntile, dtile, dktile, mlptile;
        integer cyc_block, cyc_model;
        begin
            ntile   = (N  + 15) / 16;
            dtile   = (D  + 15) / 16;
            dktile  = (dk + 15) / 16;
            mlptile = (4*D + 15) / 16;

            cyc_block = 2*ntile                                    
                      + 3 * ntile * dtile * 44                     
                      + H * ntile * ntile * dktile * 44            
                      + H * ntile * ntile * dktile * 44            
                      + ntile * dtile * 44                          
                      + ntile * mlptile * 44                        
                      + ntile * dtile * 44                          
                      + 2*ntile;                                    
            cyc_model = cyc_block * 12;
            if (N == 16 && D == 16) cyc_block = toy_total;

            $display("     DeiT-%s  N=%3d D=%3d H=%2d:  %10d cyc/block  %10d cyc/model   %6.2f ms @500MHz",
                     name, N, D, H, cyc_block, cyc_model, real'(cyc_model)*2.0/1e6);
        end
    endtask

    reg [4:0]  prev_state;
    reg [15:0] state_enter_cyc;
    reg [15:0] cyc;
    reg [15:0] phase_cyc [0:31];
    reg [15:0] lp_valid_cnt_per_state [0:31];
    integer    pi;
    reg        trace_en;

    initial begin
        trace_en = 1;
        for (pi = 0; pi < 32; pi = pi + 1) begin
            phase_cyc[pi] = 0;
            lp_valid_cnt_per_state[pi] = 0;
        end
    end

    always @(posedge clk) begin
        if (rst_n && DUT.lp_out_valid)
            lp_valid_cnt_per_state[state_dbg] <= lp_valid_cnt_per_state[state_dbg] + 1;
        if (rst_n && DUT.lp_out_valid && state_dbg == 5'd19 && trace_en)
            $display("  [cyc %4d] lp_out_valid=1 lp_y_packed=%h",
                     cyc, DUT.lp_y_packed);
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            cyc <= 0;
            prev_state <= 5'd0;
            state_enter_cyc <= 0;
        end else begin
            cyc <= cyc + 1;
            if (state_dbg != prev_state) begin
                phase_cyc[prev_state] <= phase_cyc[prev_state] + (cyc - state_enter_cyc);
                if (trace_en)
                    $display("  [cyc %5d] %s -> %s  (dwell=%0d)",
                             cyc, state_name(prev_state), state_name(state_dbg),
                             cyc - state_enter_cyc);
                prev_state      <= state_dbg;
                state_enter_cyc <= cyc;
            end
        end
    end

    integer r, c, done_cnt;
    reg [127:0] row_data;

    initial begin
        $display("");
        $display("======================================================================");
        $display(" tb_boostvit_accelerator v2  --  Full BoostViT end-to-end");
        $display(" H_HEADS=%0d  H_PARALLEL=1  BUF_DEPTH=4096", H_HEADS);
        $display("======================================================================");

        rst_n = 0; start = 0;
        host_act_we = 0; host_act_addr = 0; host_act_din = 0;
        host_wgt_we = 0; host_wgt_addr = 0; host_wgt_din = 0;
        host_out_addr = 0;
        cfg_n_tiles = 5'd0; cfg_d_tiles = 5'd0;     
        cfg_h_heads = 4'd0; cfg_l_layers = 4'd0;    
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);

        $display("");
        $display("[LOAD] Loading 16x16 input activations...");
        for (r = 0; r < 16; r = r + 1) begin
            for (c = 0; c < 16; c = c + 1)
                row_data[c*8 +: 8] = 8'(((r*5 + c*3) & 5'h1F) - 16);
            @(negedge clk);
            host_act_we   = 1'b1;
            host_act_addr = r;
            host_act_din  = row_data;
            @(posedge clk); #0.1;
            host_act_we   = 1'b0;
        end

        $display("[LOAD] Loading 16x16 weight tile...");
        for (c = 0; c < 16; c = c + 1) begin
            for (r = 0; r < 16; r = r + 1)
                row_data[r*8 +: 8] = 8'((r + c) & 4'hF);
            @(negedge clk);
            host_wgt_we   = 1'b1;
            host_wgt_addr = c;
            host_wgt_din  = row_data;
            @(posedge clk); #0.1;
            host_wgt_we   = 1'b0;
        end
        repeat(3) @(posedge clk);

        $display("");
        $display("[RUN] Pulsing start -- outer-loop iterates 1x1 tile, 1 layer");
        $display("-----+---------------------------------------------------");
        @(negedge clk);
        start = 1;
        @(posedge clk); #0.1;
        start = 0;

        done_cnt = 0;
        fork
            begin
                while (!all_done) @(posedge clk);
            end
            begin
                repeat(5000) @(posedge clk);
                $display("  [WATCHDOG] 5000 cycles, forcing finish");
            end
        join_any
        disable fork;

        trace_en = 0;
        repeat(10) @(posedge clk);

        $display("");
        $display("----------------------------------------------------------------------");
        $display(" PER-PHASE CYCLE BREAKDOWN (single-tile inner loop)                    ");
        $display("----------------------------------------------------------------------");
        for (pi = 1; pi < 32; pi = pi + 1)
            if (phase_cyc[pi] > 0)
                $display("   %-16s  %5d cycles  (lp_out_valid=%0d)", state_name(pi),
                         phase_cyc[pi], lp_valid_cnt_per_state[pi]);
        $display("----------------------------------------------------------------------");
        $display("   Inner per-block cycles  : %0d", total_cycles);
        $display("   Tiles fired by outer    : %0d", total_tiles_fired);
        $display("   all_done                : %0d", all_done);
        $display("----------------------------------------------------------------------");

        $display("");
        $display("----------------------------------------------------------------------");
        $display(" CYCLE EXTRAPOLATION TO FULL DEIT (12 layers @ 500 MHz)                ");
        $display(" H_PARALLEL=1: H heads compute in parallel -> H-way attention speedup ");
        $display("----------------------------------------------------------------------");
        extrap_config(16,  16,  1,  16, total_cycles, "TOY  ");
        extrap_config(196, 192, 3,  64, 0,             "Tiny ");
        extrap_config(196, 384, 6,  64, 0,             "Small");
        extrap_config(196, 768, 12, 64, 0,             "Base ");

        $display("");
        $display("----------------------------------------------------------------------");
        $display(" OBSERVABILITY CHECKS  (reads of debug address range)                 ");
        $display("----------------------------------------------------------------------");
        @(negedge clk); host_out_addr = 12'hF00; @(posedge clk); @(posedge clk);
        $display("   SM Unit e_out      = %h", host_out_dout);
        @(negedge clk); host_out_addr = 12'hF10; @(posedge clk); @(posedge clk);
        $display("   SM Unit sm_out     = %h", host_out_dout);
        @(negedge clk); host_out_addr = 12'hF30; @(posedge clk); @(posedge clk);
        $display("   SM Unit es_sum     = %h", host_out_dout[11:0]);
        @(negedge clk); host_out_addr = 12'hF40; @(posedge clk); @(posedge clk);
        $display("   Wide accum y_out   = %h", host_out_dout);
        @(negedge clk); host_out_addr = 12'hF60; @(posedge clk); @(posedge clk);
        $display("   Head-concat sum    = %h", host_out_dout);
        @(negedge clk); host_out_addr = 12'hF70; @(posedge clk); @(posedge clk);
        $display("   Head-concat head0  = %h", host_out_dout);
        @(negedge clk); host_out_addr = 12'hF80; @(posedge clk); @(posedge clk);
        $display("   Debug status       = %h", host_out_dout);
        @(negedge clk); host_out_addr = 12'hFA0; @(posedge clk); @(posedge clk);
        $display("   AXI status         = %h (busy=%b done=%b)",
                 host_out_dout, host_out_dout[127], host_out_dout[126]);

        $display("");
        $display("----------------------------------------------------------------------");
        $display(" DIRECT MEMORY INSPECTION  (hierarchical dump)                        ");
        $display("----------------------------------------------------------------------");
        $display("   ACT_BUF[0..3]:");
        for (r = 0; r < 4; r = r + 1)
            $display("     act[%0d] = %h", r, DUT.u_act_buf.mem[r]);
        $display("   SCRATCH_BUF[160..163] (WO output):");
        for (r = 160; r < 164; r = r + 1)
            $display("     scr[%0d] = %h", r, DUT.u_scr_buf.mem[r]);
        $display("   SCRATCH_BUF[128..131] (MLP2 output):");
        for (r = 128; r < 132; r = r + 1)
            $display("     scr[%0d] = %h", r, DUT.u_scr_buf.mem[r]);
        $display("   OUT_BUF[16..19] (residual_1):");
        for (r = 16; r < 20; r = r + 1)
            $display("     out[%0d] = %h", r, DUT.u_out_buf.mem[r]);
        $display("   OUT_BUF[48..51] (residual_2 final):");
        for (r = 48; r < 52; r = r + 1)
            $display("     out[%0d] = %h", r, DUT.u_out_buf.mem[r]);

        $display("");
        $display("----------------------------------------------------------------------");
        $display(" INTERMEDIATE BUFFER CHECKS  (via host read port)                    ");
        $display("----------------------------------------------------------------------");
        for (r = 16; r < 20; r = r + 1) begin
            @(negedge clk); host_out_addr = r; @(posedge clk); @(posedge clk);
            $display("   OUT_BUF[%2d] (residual_1)  = %h", r, host_out_dout);
        end
        $display("");
        $display("----------------------------------------------------------------------");
        $display(" FINAL OUTPUT BUFFER CONTENTS  (residual-path writes at OUT[48+])    ");
        $display("----------------------------------------------------------------------");
        for (r = 48; r < 56; r = r + 1) begin
            @(negedge clk);
            host_out_addr = r;
            @(posedge clk); @(posedge clk);
            $display("   OUT[%2d] = %h", r - 48, host_out_dout);
        end

        $display("");
        $display("----------------------------------------------------------------------");
        $display(" CORRECTNESS SUMMARY                                                  ");
        $display("----------------------------------------------------------------------");
        if (all_done) $display("   [PASS] Outer loop reached all_done");
        else          $display("   [FAIL] Outer loop did NOT finish");
        if (total_cycles > 400 && total_cycles < 1500)
            $display("   [PASS] Inner per-block cycles %0d in expected range", total_cycles);
        else
            $display("   [WARN] Inner per-block cycles %0d unusual", total_cycles);
        if (total_tiles_fired >= 1)
            $display("   [PASS] Outer loop fired %0d tiles", total_tiles_fired);
        else
            $display("   [FAIL] No tiles fired");

        $display("======================================================================");
        $finish;
    end

    initial begin
        #80000;
        $display("[TIMEOUT]");
        $finish;
    end

endmodule
