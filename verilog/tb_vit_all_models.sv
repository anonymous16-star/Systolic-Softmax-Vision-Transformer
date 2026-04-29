`timescale 1ns / 1ps



module tb_vit_all_models;

    reg clk, rst;
    initial clk = 0;
    always #5 clk = ~clk;                  

    reg  [2047:0] x_in;
    reg  [2047:0] wq_flat, wk_flat, wv_flat, wo_flat, wmlp1_flat, wmlp2_flat;
    reg  [127:0]  gamma1, beta1, gamma2, beta2;
    reg           start;

    wire [2047:0] x_out_toy,    x_out_tiny,    x_out_small,    x_out_base;
    wire          done_toy,     done_tiny,     done_small,     done_base;
    wire [31:0]   cyc_toy,      cyc_tiny,      cyc_small,      cyc_base;
    wire [47:0]   xcyc_toy,     xcyc_tiny,     xcyc_small,     xcyc_base;

    vit_top #(.MODEL_CFG(0), .BOOTH_LSB_SCALE(1), .THRESHOLD(10)) DUT_TOY (
        .clk(clk), .rst(rst),
        .x_in(x_in),
        .wq_flat(wq_flat), .wk_flat(wk_flat), .wv_flat(wv_flat),
        .wo_flat(wo_flat), .wmlp1_flat(wmlp1_flat), .wmlp2_flat(wmlp2_flat),
        .gamma1(gamma1), .beta1(beta1), .gamma2(gamma2), .beta2(beta2),
        .start(start),
        .x_out(x_out_toy), .done(done_toy),
        .tile_cycles(cyc_toy), .extrapolated_cycles(xcyc_toy)
    );
    vit_top #(.MODEL_CFG(1), .BOOTH_LSB_SCALE(1), .THRESHOLD(10)) DUT_TINY (
        .clk(clk), .rst(rst),
        .x_in(x_in), .wq_flat(wq_flat), .wk_flat(wk_flat), .wv_flat(wv_flat),
        .wo_flat(wo_flat), .wmlp1_flat(wmlp1_flat), .wmlp2_flat(wmlp2_flat),
        .gamma1(gamma1), .beta1(beta1), .gamma2(gamma2), .beta2(beta2),
        .start(start),
        .x_out(x_out_tiny), .done(done_tiny),
        .tile_cycles(cyc_tiny), .extrapolated_cycles(xcyc_tiny)
    );
    vit_top #(.MODEL_CFG(2), .BOOTH_LSB_SCALE(1), .THRESHOLD(10)) DUT_SMALL (
        .clk(clk), .rst(rst),
        .x_in(x_in), .wq_flat(wq_flat), .wk_flat(wk_flat), .wv_flat(wv_flat),
        .wo_flat(wo_flat), .wmlp1_flat(wmlp1_flat), .wmlp2_flat(wmlp2_flat),
        .gamma1(gamma1), .beta1(beta1), .gamma2(gamma2), .beta2(beta2),
        .start(start),
        .x_out(x_out_small), .done(done_small),
        .tile_cycles(cyc_small), .extrapolated_cycles(xcyc_small)
    );
    vit_top #(.MODEL_CFG(3), .BOOTH_LSB_SCALE(1), .THRESHOLD(10)) DUT_BASE (
        .clk(clk), .rst(rst),
        .x_in(x_in), .wq_flat(wq_flat), .wk_flat(wk_flat), .wv_flat(wv_flat),
        .wo_flat(wo_flat), .wmlp1_flat(wmlp1_flat), .wmlp2_flat(wmlp2_flat),
        .gamma1(gamma1), .beta1(beta1), .gamma2(gamma2), .beta2(beta2),
        .start(start),
        .x_out(x_out_base), .done(done_base),
        .tile_cycles(cyc_base), .extrapolated_cycles(xcyc_base)
    );

    integer i, j, timeout;
    integer out_x_toy, out_x_tiny, out_x_small, out_x_base;

    initial begin
        $display("");
        $display("================================================================");
        $display("  ViT Accuracy & Latency Comparison -- ALL DeiT Configurations  ");
        $display("  Paper: BoostViT (TCAS-I Nov 2025)                              ");
        $display("================================================================");

        rst = 1; start = 0;
        x_in = 0; wq_flat = 0; wk_flat = 0; wv_flat = 0;
        wo_flat = 0; wmlp1_flat = 0; wmlp2_flat = 0;
        gamma1 = 0; beta1 = 0; gamma2 = 0; beta2 = 0;
        repeat(4) @(posedge clk);
        rst = 0;
        @(posedge clk);

        
        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
                
                x_in[i*128 + j*8 +: 8] =
                    8'( ((((i*5) + 1) * ((j*3) + 1)) % 41) - 20 );
            end
        end

        for (i = 0; i < 256; i = i + 1) begin
            wq_flat   [i*8 +: 8] = 8'( ((i*7)  % 9)  - 4 );    
            wk_flat   [i*8 +: 8] = 8'( ((i*11) % 9)  - 4 );
            wv_flat   [i*8 +: 8] = 8'( ((i*13) % 11) - 5 );    
            wo_flat   [i*8 +: 8] = 8'( ((i*17) % 7)  - 3 );
            wmlp1_flat[i*8 +: 8] = 8'( ((i*19) % 9)  - 4 );
            wmlp2_flat[i*8 +: 8] = 8'( ((i*23) % 7)  - 3 );
        end

        for (i = 0; i < 16; i = i + 1) begin
            gamma1[i*8 +: 8] = 8'd128;  beta1[i*8 +: 8] = 8'd0;
            gamma2[i*8 +: 8] = 8'd128;  beta2[i*8 +: 8] = 8'd0;
        end

        $display("");
        $display("  Launching all 4 configurations in parallel...");
        @(negedge clk); start = 1'b1;
        @(posedge clk); #1; start = 1'b0;

        timeout = 0;
        while ((!done_toy || !done_tiny || !done_small || !done_base)
               && timeout < 10000) begin
            @(posedge clk); timeout = timeout + 1;
        end
        repeat(2) @(posedge clk);

        out_x_toy = 0;  out_x_tiny = 0;  out_x_small = 0;  out_x_base = 0;
        for (i = 0; i < 256; i = i + 1) begin
            if (x_out_toy  [i*8 +: 8] === 8'bxxxxxxxx) out_x_toy   = out_x_toy   + 1;
            if (x_out_tiny [i*8 +: 8] === 8'bxxxxxxxx) out_x_tiny  = out_x_tiny  + 1;
            if (x_out_small[i*8 +: 8] === 8'bxxxxxxxx) out_x_small = out_x_small + 1;
            if (x_out_base [i*8 +: 8] === 8'bxxxxxxxx) out_x_base  = out_x_base  + 1;
        end

        $display("");
        $display("================================================================");
        $display("                   RESULTS  (1-tile * model-tiles)              ");
        $display("================================================================");
        $display("  Model      | 1-tile cyc | Model tiles | Extrapolated cycles");
        $display("  -----------+------------+-------------+--------------------");
        $display("  TOY        | %10d |  %10d | %12d",
                 cyc_toy,   1,                                cyc_toy);
        $display("  DeiT-Tiny  | %10d |  %10d | %12d",
                 cyc_tiny,  (cyc_tiny  > 0) ? xcyc_tiny  / cyc_tiny  : 0,  xcyc_tiny);
        $display("  DeiT-Small | %10d |  %10d | %12d",
                 cyc_small, (cyc_small > 0) ? xcyc_small / cyc_small : 0, xcyc_small);
        $display("  DeiT-Base  | %10d |  %10d | %12d",
                 cyc_base,  (cyc_base  > 0) ? xcyc_base  / cyc_base  : 0,  xcyc_base);
        $display("");

        $display("--- Output Integrity ---");
        if (out_x_toy   == 0) $display("  [PASS] TOY        outputs clean");
        else                  $display("  [FAIL] TOY        has %0d X outputs", out_x_toy);
        if (out_x_tiny  == 0) $display("  [PASS] DeiT-Tiny  outputs clean");
        else                  $display("  [FAIL] DeiT-Tiny  has %0d X outputs", out_x_tiny);
        if (out_x_small == 0) $display("  [PASS] DeiT-Small outputs clean");
        else                  $display("  [FAIL] DeiT-Small has %0d X outputs", out_x_small);
        if (out_x_base  == 0) $display("  [PASS] DeiT-Base  outputs clean");
        else                  $display("  [FAIL] DeiT-Base  has %0d X outputs", out_x_base);

        $display("");
        $display("--- Sample outputs: token 0 bytes 0..15 (hex) ---");
        $display("  x_in (token 0) : %02h %02h %02h %02h %02h %02h %02h %02h",
                 x_in[7:0],  x_in[15:8], x_in[23:16], x_in[31:24],
                 x_in[39:32],x_in[47:40],x_in[55:48], x_in[63:56]);
        $display("  x_out(tok 0)   : %02h %02h %02h %02h %02h %02h %02h %02h",
                 x_out_tiny[7:0],  x_out_tiny[15:8], x_out_tiny[23:16], x_out_tiny[31:24],
                 x_out_tiny[39:32],x_out_tiny[47:40],x_out_tiny[55:48], x_out_tiny[63:56]);

        $display("");
        $display("--- Output diversity check (token 0 vs token 8) ---");
        $display("  x_out[0*128+:64]: %016h", x_out_tiny[63:0]);
        $display("  x_out[8*128+:64]: %016h", x_out_tiny[8*128 +: 64]);

        $display("");
        $display("--- Paper Table II speedup extrapolation ---");
        $display("  To compute BoostViT/baseline ratios, divide 'Extrapolated'");
        $display("  cycles columns against the baseline numbers from the paper:");
        $display("    CPU (Xeon)     : ~50.3x");
        $display("    EdgeGPU (Jetson): ~21.9x");
        $display("    GPU (Xp)       : ~17.37x");
        $display("    ViTCoD         :  ~7.47x");
        $display("    ViT-slice      :  ~1.49x");
        $display("");
        $display("================================================================");
        $finish;
    end

    initial begin
        #100000;
        $display("  [WATCHDOG] exceeded 100us, terminating");
        $finish;
    end

endmodule
