`timescale 1ns / 1ps
// =============================================================================
// logcalc_v2  --  Natural-log approximation, 10-bit input (Q3.5, scale=32)
// =============================================================================
//
// INPUT  : x [9:0]   unsigned integer [1..255]  (8-bit value zero-extended)
// OUTPUT : log_x [7:0]  unsigned Q3.5 = round(ln(x)*32),  range [0..177]
//
// ALGORITHM:
//   1. k  = floor(log2(x))            priority encoder
//   2. m  = normalise x to [128,255]  by shifting
//   3. r  = m - 128                   fractional part [0,127]
//   4. log_m = base[r>>4] + delta     piecewise-linear LUT
//   5. k_ln2 = k * ln2 * 32           shift-add approximation
//   6. log_x = log_m + k_ln2
//
// BUG FIXED: d_sh2/d_sh3/d_sh4 used 4-bit intermediates that overflow for frac>=8
//   FIX: 5-bit intermediates prevent overflow.
// BUG FIXED: bases for seg3/seg4/seg7 not minimax.
//   FIX: {0,4,7,10,13,16,18,20}
// =============================================================================
module logcalc_v2 (
    input  wire [9:0]  x,       // unsigned [1..255], 8-bit zero-extended to 10
    output wire [7:0]  log_x    // Q3.5 = round(ln(x)*32)
);

    // --- Step 1: k = floor(log2(x)) ---
    wire [3:0] k =
        x[9] ? 4'd9 : x[8] ? 4'd8 : x[7] ? 4'd7 : x[6] ? 4'd6 :
        x[5] ? 4'd5 : x[4] ? 4'd4 : x[3] ? 4'd3 : x[2] ? 4'd2 :
        x[1] ? 4'd1 : 4'd0;

    // --- Step 2: normalise to m in [128,255] ---
    wire [16:0] x17  = {7'b0, x};
    wire [3:0]  sh_l = (k <= 4'd7) ? (4'd7 - k) : 4'd0;
    wire [3:0]  sh_r = (k >= 4'd8) ? (k - 4'd7) : 4'd0;
    wire [16:0] x_shifted = (k >= 4'd8) ? (x17 >> sh_r) : (x17 << sh_l);
    wire [7:0]  m    = x_shifted[7:0];

    // --- Step 3: r = m - 128 in [0,127] ---
    wire [6:0] r     = m[6:0];
    wire [2:0] index = r[6:4];
    wire [3:0] frac  = r[3:0];

    // --- 5-bit rounded-shift helpers (BUG-OVERFLOW FIX) ---
    wire [4:0] d_sh2 = ({1'b0, frac} + 5'd2) >> 2;   // round(frac/4)
    wire [4:0] d_sh3 = ({1'b0, frac} + 5'd4) >> 3;   // round(frac/8)
    wire [4:0] d_sh4 = ({1'b0, frac} + 5'd8) >> 4;   // round(frac/16)

    // --- Minimax bases (BUG-BASES FIX) ---
    wire [4:0] base_w =
        (index == 3'd0) ? 5'd0  :
        (index == 3'd1) ? 5'd4  :
        (index == 3'd2) ? 5'd7  :
        (index == 3'd3) ? 5'd10 :
        (index == 3'd4) ? 5'd13 :
        (index == 3'd5) ? 5'd16 :
        (index == 3'd6) ? 5'd18 : 5'd20;

    wire [4:0] delta_w =
        (index <= 3'd2) ? d_sh2 :
        (index <= 3'd4) ? (d_sh3 + d_sh4) :
                           d_sh3;

    wire [7:0] log_m = {3'b0, base_w} + {3'b0, delta_w};

    // --- Step 5: k_ln2 = k*ln2*32 ~ k*22.1836 ---
    wire [8:0] k9    = {5'b0, k};
    wire [8:0] k_ln2 = (k9 << 4) + (k9 << 2) + (k9 << 1) + (k9 >> 2)
                     - (k9 >> 4) - (k9 >> 8);

    // --- Step 6: combine, saturate ---
    wire [8:0] log_full = {1'b0, log_m} + k_ln2;
    assign log_x = log_full[8] ? 8'd255 : log_full[7:0];

endmodule


// =============================================================================
// logcalc_wide_v2  --  Natural-log approximation, 20-bit input (Q3.5, scale=32)
// =============================================================================
//
// INPUT  : x [19:0]   unsigned integer [1 .. 2^20-1]
// OUTPUT : log_x [15:0]  unsigned Q3.5 = round(ln(x)*32)
//
// Used for computing ln(sum of exps) in softmax.
//   For N=16: sum range [752..2048] -> 12-bit input, padded to 20 bits.
//
// SAME BUGS FIXED as logcalc_v2.
// =============================================================================
module logcalc_wide_v2 (
    input  wire [19:0] x,       // unsigned [1 .. 2^20-1]
    output wire [15:0] log_x    // Q3.5 = round(ln(x)*32)
);

    // --- Step 1: k = floor(log2(x)), 5-bit ---
    wire [4:0] k =
        x[19] ? 5'd19 : x[18] ? 5'd18 : x[17] ? 5'd17 : x[16] ? 5'd16 :
        x[15] ? 5'd15 : x[14] ? 5'd14 : x[13] ? 5'd13 : x[12] ? 5'd12 :
        x[11] ? 5'd11 : x[10] ? 5'd10 : x[9]  ? 5'd9  : x[8]  ? 5'd8  :
        x[7]  ? 5'd7  : x[6]  ? 5'd6  : x[5]  ? 5'd5  : x[4]  ? 5'd4  :
        x[3]  ? 5'd3  : x[2]  ? 5'd2  : x[1]  ? 5'd1  : 5'd0;

    // --- Step 2: normalise to m in [128,255] ---
    wire [26:0] x27  = {7'b0, x};
    wire [4:0]  sh_l = (k <= 5'd7) ? (5'd7 - k) : 5'd0;
    wire [4:0]  sh_r = (k >= 5'd8) ? (k - 5'd7) : 5'd0;
    wire [26:0] x_shifted = (k >= 5'd8) ? (x27 >> sh_r) : (x27 << sh_l);
    wire [7:0]  m    = x_shifted[7:0];

    // --- Step 3: r = m - 128 ---
    wire [6:0] r     = m[6:0];
    wire [2:0] index = r[6:4];
    wire [3:0] frac  = r[3:0];

    // --- 5-bit rounded-shift helpers (BUG-OVERFLOW FIX) ---
    wire [4:0] d_sh2 = ({1'b0, frac} + 5'd2) >> 2;
    wire [4:0] d_sh3 = ({1'b0, frac} + 5'd4) >> 3;
    wire [4:0] d_sh4 = ({1'b0, frac} + 5'd8) >> 4;

    // --- Minimax bases (BUG-BASES FIX) ---
    wire [4:0] base_w =
        (index == 3'd0) ? 5'd0  :
        (index == 3'd1) ? 5'd4  :
        (index == 3'd2) ? 5'd7  :
        (index == 3'd3) ? 5'd10 :
        (index == 3'd4) ? 5'd13 :
        (index == 3'd5) ? 5'd16 :
        (index == 3'd6) ? 5'd18 : 5'd20;

    wire [4:0] delta_w =
        (index <= 3'd2) ? d_sh2 :
        (index <= 3'd4) ? (d_sh3 + d_sh4) :
                           d_sh3;

    wire [7:0] log_m = {3'b0, base_w} + {3'b0, delta_w};

    // --- Step 5: k_ln2 = k*ln2*32 (16-bit, covers k=0..19) ---
    wire [15:0] k16   = {11'b0, k};
    wire [15:0] k_ln2 = (k16 << 4) + (k16 << 2) + (k16 << 1) + (k16 >> 2)
                      - (k16 >> 4) - (k16 >> 8);

    // --- Step 6: combine ---
    assign log_x = {8'b0, log_m} + k_ln2;

endmodule
