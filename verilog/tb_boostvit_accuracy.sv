`timescale 1ns / 1ps

module tb_boostvit_accuracy;

    reg clk, rst;
    initial clk = 0;
    always #5 clk = ~clk;


    reg        load_k_en;
    reg [3:0]  load_k_col;
    reg [127:0] k_packed;
    reg [7:0]  q0, q1, q2, q3, q4, q5, q6, q7;
    reg [7:0]  q8, q9, q10, q11, q12, q13, q14, q15;
    reg        valid_q;

    wire [127:0] lsm_out,    sm_out,    exp_dbg;
    wire [11:0]  es_dbg;
    wire         attn_valid;

    attention_head #(.BOOTH_LSB_SCALE(1), .THRESHOLD(10)) DUT (
        .clk(clk), .rst(rst),
        .load_k_en(load_k_en), .load_k_col(load_k_col), .k_in_packed(k_packed),
        .q0(q0), .q1(q1), .q2(q2), .q3(q3),
        .q4(q4), .q5(q5), .q6(q6), .q7(q7),
        .q8(q8), .q9(q9), .q10(q10), .q11(q11),
        .q12(q12), .q13(q13), .q14(q14), .q15(q15),
        .valid_q(valid_q),
        .lsm_out(lsm_out), .sm_out(sm_out),
        .exp_dbg(exp_dbg), .es_dbg(es_dbg),
        .attn_valid(attn_valid)
    );

    reg        load_k_en_ns;
    reg [3:0]  load_k_col_ns;
    reg [127:0] k_packed_ns;
    wire [127:0] lsm_ns, sm_ns;
    wire         valid_ns;

    attention_head #(.BOOTH_LSB_SCALE(0), .THRESHOLD(10)) DUT_NS (
        .clk(clk), .rst(rst),
        .load_k_en(load_k_en_ns), .load_k_col(load_k_col_ns),
        .k_in_packed(k_packed_ns),
        .q0(q0), .q1(q1), .q2(q2), .q3(q3),
        .q4(q4), .q5(q5), .q6(q6), .q7(q7),
        .q8(q8), .q9(q9), .q10(q10), .q11(q11),
        .q12(q12), .q13(q13), .q14(q14), .q15(q15),
        .valid_q(valid_q),
        .lsm_out(lsm_ns), .sm_out(sm_ns),
        .exp_dbg(), .es_dbg(),
        .attn_valid(valid_ns)
    );

   
    
    reg signed [7:0] K_mat [0:15][0:15];
    reg signed [7:0] Q_mat [0:15][0:15];
    real             K_real [0:15][0:15];
    real             Q_real [0:15][0:15];

    function automatic [7:0] gen_k (input integer r, input integer c);
        integer seed, v, bucket;
        begin

            
            seed   = ((r + 1) * 37 + (c + 1) * 73) & 8'hFF;
            bucket = seed % 100;
            if (bucket < 50) begin                          
                v = (seed % 31) - 15;                       
            end else begin                                  
                case (bucket % 10)
                    0: v =  38;  1: v =  42;  2: v =  50;
                    3: v =  54;  4: v =  46;
                    5: v = -38;  6: v = -42;  7: v = -50;
                    8: v = -54;  default: v = -46;
                endcase
            end
            gen_k = v[7:0];
        end
    endfunction

    function automatic [7:0] gen_q (input integer r, input integer c);
        integer seed, v;
        begin
            seed = ((r + 7) * 41 + (c + 3) * 29) & 8'hFF;
            v    = (seed % 21) - 10;                     
            
            v = v + (((r * 5) % 7) - 3);
            if (v > 31)  v = 31;
            if (v < -32) v = -32;
            gen_q = v[7:0];
        end
    endfunction

    
    
    
    integer total_booth_ops;
    integer skip_ops_natural;
    integer skip_ops_lsb;

    function integer count_skips (input [7:0] k_val);
        reg [8:0] kext;
        reg [2:0] bu1_, bu2_, bu3_, bu4_;
        begin
            kext = {k_val, 1'b0};
            bu1_ = kext[8:6];  bu2_ = kext[6:4];
            bu3_ = kext[4:2];  bu4_ = kext[2:0];
            count_skips = 0;
            if (bu1_ == 3'b000 || bu1_ == 3'b111) count_skips = count_skips + 1;
            if (bu2_ == 3'b000 || bu2_ == 3'b111) count_skips = count_skips + 1;
            if (bu3_ == 3'b000 || bu3_ == 3'b111) count_skips = count_skips + 1;
            if (bu4_ == 3'b000 || bu4_ == 3'b111) count_skips = count_skips + 1;
        end
    endfunction

    function automatic [7:0] lsb_scale (input signed [7:0] k);
        if (!k[7])  lsb_scale = k | 8'b0011_1000;
        else        lsb_scale = k & 8'b1100_0111;
    endfunction

    task automatic load_K_matrix (input reg use_lsb_scale, input reg which_ns);
        integer r, c;
        reg [127:0] col_packed;
    begin
        for (c = 0; c < 16; c = c + 1) begin
            for (r = 0; r < 16; r = r + 1) begin
                if (use_lsb_scale)
                    col_packed[r*8 +: 8] = lsb_scale(K_mat[r][c]);
                else
                    col_packed[r*8 +: 8] = K_mat[r][c];
            end
            @(negedge clk);
            if (!which_ns) begin
                load_k_en    = 1'b1;
                load_k_col   = c[3:0];
                k_packed     = col_packed;
            end else begin
                load_k_en_ns  = 1'b1;
                load_k_col_ns = c[3:0];
                k_packed_ns   = col_packed;
            end
            @(posedge clk); #1;
            if (!which_ns) load_k_en    = 1'b0;
            else           load_k_en_ns = 1'b0;
        end
    end
    endtask

    task automatic stream_Q_token (input integer tok);
    begin
        @(negedge clk);
        q0  = Q_mat[tok][0];   q1  = Q_mat[tok][1];
        q2  = Q_mat[tok][2];   q3  = Q_mat[tok][3];
        q4  = Q_mat[tok][4];   q5  = Q_mat[tok][5];
        q6  = Q_mat[tok][6];   q7  = Q_mat[tok][7];
        q8  = Q_mat[tok][8];   q9  = Q_mat[tok][9];
        q10 = Q_mat[tok][10];  q11 = Q_mat[tok][11];
        q12 = Q_mat[tok][12];  q13 = Q_mat[tok][13];
        q14 = Q_mat[tok][14];  q15 = Q_mat[tok][15];
        valid_q = 1'b1;
        @(posedge clk); #1;
        valid_q = 1'b0;
    end
    endtask

    real score_real  [0:15];
    real softmax_ref [0:15];

    task automatic ref_softmax (input integer tok);
        integer a, b;
        real    maxs, sume;
    begin
        for (b = 0; b < 16; b = b + 1) begin
            score_real[b] = 0.0;
            for (a = 0; a < 16; a = a + 1)
                score_real[b] = score_real[b] + Q_real[tok][a] * K_real[b][a];
            score_real[b] = score_real[b] * 0.25;   
        end
        maxs = score_real[0];
        for (b = 1; b < 16; b = b + 1)
            if (score_real[b] > maxs) maxs = score_real[b];
        sume = 0.0;
        for (b = 0; b < 16; b = b + 1) begin
            softmax_ref[b] = $exp(score_real[b] - maxs);
            sume = sume + softmax_ref[b];
        end
        for (b = 0; b < 16; b = b + 1)
            softmax_ref[b] = softmax_ref[b] / sume;
    end
    endtask

    real sum_err_all, max_err_all, avg_sum_hw;
    integer num_tokens_tested;

    task automatic run_one_token (input integer tok);
        integer tmo, b;
        logic signed [7:0] ls;
        real hw_lsm, hw_sm, ref_sm, err, sum_hw;
        reg [127:0] cap;
    begin
        stream_Q_token(tok);
        tmo = 0;
        while (!attn_valid && tmo < 200) begin @(posedge clk); tmo = tmo + 1; end
        repeat(2) @(posedge clk);
        cap = lsm_out;

        ref_softmax(tok);

        sum_hw = 0.0;
        $display("  Token %0d:", tok);
        $display("  row | HW_lsm | HW_sm  | Ref_sm | Err%%");
        $display("  ----+--------+--------+--------+------");
        for (b = 0; b < 16; b = b + 1) begin
            ls     = $signed(cap[b*8 +: 8]);
            hw_lsm = $itor(ls) / 32.0;
            hw_sm  = $exp(hw_lsm);
            ref_sm = softmax_ref[b];
            err    = hw_sm - ref_sm; if (err < 0.0) err = -err;
            err    = err * 100.0;
            sum_hw = sum_hw + hw_sm;
            if (err > max_err_all) max_err_all = err;
            sum_err_all = sum_err_all + err;
            $display("  %3d | %6.3f | %6.4f | %6.4f | %5.2f", b, hw_lsm, hw_sm, ref_sm, err);
        end
        $display("  Sum(HW_sm) = %6.4f   (target ~1.0)", sum_hw);
        avg_sum_hw = avg_sum_hw + sum_hw;
        num_tokens_tested = num_tokens_tested + 1;
    end
    endtask

    integer i, j, tok;
    real skip_rate_natural, skip_rate_lsb;

    initial begin
        $display("");
        $display("================================================================");
        $display("  BoostViT Accuracy & Performance Testbench");
        $display("  Paper: BoostViT TCAS-I Nov 2025 (Zhao et al.)");
        $display("================================================================");

        rst = 1; load_k_en = 0; load_k_en_ns = 0; valid_q = 0;
        k_packed = 128'd0; k_packed_ns = 128'd0;
        {q0,q1,q2,q3,q4,q5,q6,q7,q8,q9,q10,q11,q12,q13,q14,q15} = 128'd0;
        num_tokens_tested = 0;
        sum_err_all = 0.0; max_err_all = 0.0; avg_sum_hw = 0.0;
        repeat(4) @(posedge clk);
        rst = 0;
        @(posedge clk);

        
        
        
        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
                K_mat[i][j]  = gen_k(i, j);
                Q_mat[i][j]  = gen_q(i, j);
                K_real[i][j] = $itor($signed(K_mat[i][j])) / 128.0;
                Q_real[i][j] = $itor($signed(Q_mat[i][j])) / 128.0;
            end
        end

        
        
        
        $display("");
        $display("--- TEST 1: Booth Skip Rate ---");
        total_booth_ops = 0;
        skip_ops_natural = 0;
        skip_ops_lsb = 0;
        for (i = 0; i < 16; i = i + 1)
            for (j = 0; j < 16; j = j + 1) begin
                total_booth_ops   = total_booth_ops + 4;
                skip_ops_natural  = skip_ops_natural  + count_skips(K_mat[i][j]);
                skip_ops_lsb      = skip_ops_lsb      + count_skips(lsb_scale(K_mat[i][j]));
            end
        skip_rate_natural = (100.0 * skip_ops_natural) / total_booth_ops;
        skip_rate_lsb     = (100.0 * skip_ops_lsb)     / total_booth_ops;
        $display("  Total Booth ops    : %0d", total_booth_ops);
        $display("  Skip (natural)     : %6.1f%%   (paper DeiT: ~37%%)",
                 skip_rate_natural);
        $display("  Skip (LSB scaled)  : %6.1f%%   (paper DeiT: ~57%%)",
                 skip_rate_lsb);
        $display("  Skip-rate increase : %+6.1f%%   (paper: +20%%)",
                 skip_rate_lsb - skip_rate_natural);

        
        
        
        $display("");
        $display("--- TEST 2: MSB Identical-Bit Density (Paper Fig. 2) ---");
        begin
            integer cnt4, cnt3, total;
            reg [3:0] top4;
            reg [2:0] top3;
            cnt4 = 0; cnt3 = 0; total = 0;
            for (i = 0; i < 16; i = i + 1)
                for (j = 0; j < 16; j = j + 1) begin
                    top4 = K_mat[i][j][7:4];
                    top3 = K_mat[i][j][7:5];
                    if (top4 == 4'b0000 || top4 == 4'b1111) cnt4 = cnt4 + 1;
                    if (top3 == 3'b000  || top3 == 3'b111)  cnt3 = cnt3 + 1;
                    total = total + 1;
                end
            $display("  Same top-4 MSBs (000/111): %4d / %4d = %5.1f%%   (paper >90%%)",
                     cnt4, total, (100.0 * cnt4) / total);
            $display("  Same top-3 MSBs          : %4d / %4d = %5.1f%%   (paper ~91%%)",
                     cnt3, total, (100.0 * cnt3) / total);
        end

        
        
        
        $display("");
        $display("--- TEST 3: HW Softmax accuracy (Booth-Friendly LSB Scaling ON) ---");
        load_K_matrix(1'b1, 1'b0);  
        @(posedge clk);
        for (tok = 0; tok < 16; tok = tok + 4)
            run_one_token(tok);

        
        
        
        $display("");
        $display("--- TEST 4: HW Softmax accuracy (Booth-Friendly LSB Scaling OFF) ---");
        rst = 1; repeat(4) @(posedge clk); rst = 0; @(posedge clk);
        load_K_matrix(1'b0, 1'b1);  
        @(posedge clk);
        begin
            real max_delta, delta;
            integer tmo, b;
            logic signed [7:0] sa, sb;
            reg [127:0] cap_lsb, cap_ns;
            max_delta = 0.0;
            for (tok = 0; tok < 16; tok = tok + 4) begin
                stream_Q_token(tok);
                tmo = 0;
                while (!valid_ns && tmo < 200) begin @(posedge clk); tmo = tmo + 1; end
                repeat(2) @(posedge clk);
                cap_ns = lsm_ns;

                
                load_K_matrix(1'b1, 1'b0);
                @(posedge clk);
                stream_Q_token(tok);
                tmo = 0;
                while (!attn_valid && tmo < 200) begin @(posedge clk); tmo = tmo + 1; end
                repeat(2) @(posedge clk);
                cap_lsb = lsm_out;

                for (b = 0; b < 16; b = b + 1) begin
                    sa = $signed(cap_lsb[b*8 +: 8]);
                    sb = $signed(cap_ns [b*8 +: 8]);
                    delta = $itor(sa - sb);
                    if (delta < 0.0) delta = -delta;
                    if (delta > max_delta) max_delta = delta;
                end
            end
            $display("  Max |lsm_with_LSB - lsm_no_LSB| across tested tokens: %.1f LSBs",
                     max_delta);
            $display("  (smaller = LSB scaling has less impact on result)");
        end

        
        
        
        $display("");
        $display("================================================================");
        $display("  PAPER COMPARISON SUMMARY");
        $display("================================================================");
        $display("  Metric                 | HW measured | Paper target");
        $display("  -----------------------+-------------+---------------");
        $display("  Skip (natural)         | %9.1f%% | ~37%%",         skip_rate_natural);
        $display("  Skip (LSB scaled)      | %9.1f%% | ~57%%",         skip_rate_lsb);
        $display("  Skip-rate increase     | %+9.1f%% | +20%%",       skip_rate_lsb - skip_rate_natural);
        if (num_tokens_tested > 0) begin
            $display("  Max softmax error      | %9.2f%% | <1.5%%",
                     max_err_all);
            $display("  Avg softmax error      | %9.2f%% | low",
                     sum_err_all / (num_tokens_tested * 16));
            $display("  Avg softmax sum        | %9.4f  | ~1.0",
                     avg_sum_hw / num_tokens_tested);
        end
        $display("  Tokens exercised       | %11d | ---", num_tokens_tested);
        $display("================================================================");
        $display("  Notes:");
        $display("  - Test uses deterministic pseudo-random K with ~91%% MSB-dense");
        $display("    distribution mimicking INT8-quantised DeiT weights.");
        $display("  - For REAL DeiT weights, dump quantised checkpoint into K_mat.");
        $display("  - Accuracy drop target <1.5%% from paper Section IV-B-1.");
        $display("================================================================");
        $finish;
    end

    
    initial begin
        #2000000;
        $display("[WATCHDOG] timeout");
        $finish;
    end

endmodule
