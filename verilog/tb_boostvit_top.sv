`timescale 1ns / 1ps
// =============================================================================
// tb_boostvit_top.sv  --  smoke test for synthesis wrapper boostvit_top.sv
// Verifies the registered-I/O wrapper produces valid softmax output.
// =============================================================================

module tb_boostvit_top;

    reg clk, rst_n;
    initial clk = 0;
    always #1 clk = ~clk;                // 500 MHz

    reg         load_k_en;
    reg  [3:0]  load_k_col;
    reg  [127:0] k_in_packed;
    reg  [7:0]  q0, q1, q2, q3, q4, q5, q6, q7;
    reg  [7:0]  q8, q9, q10, q11, q12, q13, q14, q15;
    reg         valid_q;

    wire [127:0] sm_out, lsm_out, exp_out;
    wire [11:0]  es_out;
    wire         attn_valid;

    boostvit_top #(.BOOTH_LSB_SCALE(1), .THRESHOLD(10)) DUT (
        .clk(clk), .rst_n(rst_n),
        .i_load_k_en(load_k_en), .i_load_k_col(load_k_col),
        .i_k_in_packed(k_in_packed),
        .i_q0(q0), .i_q1(q1), .i_q2(q2), .i_q3(q3),
        .i_q4(q4), .i_q5(q5), .i_q6(q6), .i_q7(q7),
        .i_q8(q8), .i_q9(q9), .i_q10(q10), .i_q11(q11),
        .i_q12(q12), .i_q13(q13), .i_q14(q14), .i_q15(q15),
        .i_valid_q(valid_q),
        .o_sm_out(sm_out), .o_lsm_out(lsm_out), .o_exp_out(exp_out),
        .o_es_out(es_out), .o_attn_valid(attn_valid)
    );

    integer col, r, tmo;
    reg [127:0] col_packed;

    initial begin
        $display("");
        $display("=== tb_boostvit_top: synthesis wrapper smoke test ===");
        rst_n = 1'b0;
        load_k_en = 0; load_k_col = 0; k_in_packed = 0; valid_q = 0;
        {q0, q1, q2, q3, q4, q5, q6, q7}      = 64'd0;
        {q8, q9, q10, q11, q12, q13, q14, q15} = 64'd0;
        repeat(10) @(posedge clk);
        rst_n = 1'b1;
        repeat(4) @(posedge clk);

        // Load 16 K columns (small values for demo)
        for (col = 0; col < 16; col = col + 1) begin
            for (r = 0; r < 16; r = r + 1)
                col_packed[r*8 +: 8] = 8'(((r*5 + col*3) & 5'h1F) - 16);
            @(negedge clk);
            load_k_en   = 1'b1;
            load_k_col  = col[3:0];
            k_in_packed = col_packed;
            @(posedge clk); #0.1;
            load_k_en = 1'b0;
        end

        // Stream 16 Q rows
        for (col = 0; col < 16; col = col + 1) begin
            @(negedge clk);
            q0  = 8'(((col*3 + 0*5) & 5'h1F) - 16);  q1  = 8'(((col*3 + 1*5) & 5'h1F) - 16);
            q2  = 8'(((col*3 + 2*5) & 5'h1F) - 16);  q3  = 8'(((col*3 + 3*5) & 5'h1F) - 16);
            q4  = 8'(((col*3 + 4*5) & 5'h1F) - 16);  q5  = 8'(((col*3 + 5*5) & 5'h1F) - 16);
            q6  = 8'(((col*3 + 6*5) & 5'h1F) - 16);  q7  = 8'(((col*3 + 7*5) & 5'h1F) - 16);
            q8  = 8'(((col*3 + 8*5) & 5'h1F) - 16);  q9  = 8'(((col*3 + 9*5) & 5'h1F) - 16);
            q10 = 8'(((col*3 +10*5) & 5'h1F) - 16);  q11 = 8'(((col*3 +11*5) & 5'h1F) - 16);
            q12 = 8'(((col*3 +12*5) & 5'h1F) - 16);  q13 = 8'(((col*3 +13*5) & 5'h1F) - 16);
            q14 = 8'(((col*3 +14*5) & 5'h1F) - 16);  q15 = 8'(((col*3 +15*5) & 5'h1F) - 16);
            valid_q = 1'b1;
            @(posedge clk); #0.1;
            valid_q = 1'b0;
        end

        tmo = 0;
        while (!attn_valid && tmo < 100) begin @(posedge clk); tmo = tmo + 1; end
        repeat(3) @(posedge clk);

        if (attn_valid || tmo < 100) begin
            $display("  [PASS] attn_valid asserted after %0d wait cycles", tmo);
            $display("  sm_out (last row)   = %h", sm_out);
            $display("  lsm_out(last row)   = %h", lsm_out);
            $display("  exp_out(last row)   = %h", exp_out);
            $display("  es_out (sum exp)    = %0d", es_out);
            begin
                integer b, sum_sm;
                sum_sm = 0;
                for (b = 0; b < 16; b = b + 1)
                    sum_sm = sum_sm + sm_out[b*8 +: 8];
                $display("  sum(sm_out)         = %0d  (target 128 = 1.0 in Q1.7)", sum_sm);
                if (sum_sm >= 120 && sum_sm <= 135)
                    $display("  [PASS] softmax sum within tolerance");
                else
                    $display("  [WARN] softmax sum outside expected range");
            end
        end else begin
            $display("  [FAIL] attn_valid never asserted");
        end
        $display("=======================================================");
        $finish;
    end

    initial begin
        #10000;
        $display("[WATCHDOG] tb timeout");
        $finish;
    end

endmodule
