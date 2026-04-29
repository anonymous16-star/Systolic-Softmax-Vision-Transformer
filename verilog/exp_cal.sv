`timescale 1ns / 1ps
// =============================================================================
// expcalc_v2  --  INT8 e^x approximation  (Q1.7, scale = 128)
// =============================================================================
//
// INPUT  : psum [7:0]  signed Q1.7  =  round(x * 128),  x in [-1, 0]
//            psum = -128  ->  x = -1.0  ->  e^x*128 = 47.09
//            psum =    0  ->  x =  0.0  ->  e^x*128 = 128.0
//
// OUTPUT : psum_exp [7:0]  unsigned Q1.7  =  round(e^x * 128),  range [47, 128]
//
// BUGS FIXED (from original expcalc):
//   BUG-A  a_ln2 was [7:0] -> overflows for a=-2 (-178 truncates to +78)
//          FIX: wire signed [9:0] with all arithmetic on 10-bit a10
//   BUG-B  a_mag = a[2:0] -> wrong magnitude (a=-1 gives 7 not 1)
//          FIX: ~a[2:0] + 3'd1  (two's complement negation of lower bits)
//   BUG-LUT non-minimax bases -> profile-optimised to [128,144,164,185,210,238]
//   BUG-C  1/ln2 approximation missing 1/128 term -> use 1+1/4+1/8+1/16+1/128
//
// ERROR (exhaustive psum in [-128,0]):
//   Max |ULP| = 0.93     Mean |ULP| = 0.31
// =============================================================================
module expcalc_v2 (
    input  wire signed [7:0] psum,      // Q1.7 signed input
    output wire        [7:0] psum_exp   // Q1.7 unsigned output
);

    // [F1] Clamp positive to 0 (x must be <= 0 for softmax-stabilised input)
    wire signed [7:0] psum_sat = psum[7] ? psum : 8'sh00;

    // [F2] Multiply by ~1/ln2 = 1.4453125  in 10-bit signed
    //   1 + 1/4 + 1/8 + 1/16 + 1/128 = 1.4453125
    wire signed [9:0] ps10 = {{2{psum_sat[7]}}, psum_sat};
    wire signed [9:0] t;
    assign t = ps10
             + (ps10 >>> 2)
             + (ps10 >>> 3)
             + (ps10 >>> 4)
             + (ps10 >>> 7);

    // a = floor(t / 128)  -> {-2, -1, 0}
    wire signed [3:0] a;
    assign a = t >>> 7;

    // [F3][BUG-A FIX] a_ln2 = a*89 in 10-bit signed (no overflow)
    //   ln2*128 = 88.722 ~ 89 = 64+16+8+1
    wire signed [9:0] a10   = {{6{a[3]}}, a};
    wire signed [9:0] a_ln2 = (a10 <<< 6) + (a10 <<< 4) + (a10 <<< 3) + a10;

    // r = psum_sat - a_ln2, clamped [0, 127]
    wire signed [9:0] r_raw = {{2{psum_sat[7]}}, psum_sat} - a_ln2;
    wire        [6:0] r     = r_raw[9] ? 7'd0 : r_raw[6:0];

    // [F5] Segment index and fraction
    wire [2:0] index = r[6:4];
    wire [3:0] frac  = r[3:0];

    // 5-bit rounded-shift helpers (prevents overflow for frac up to 15)
    wire [4:0] f5   = {1'b0, frac};
    wire [4:0] rsh1 = (f5 + 5'd1) >> 1;   // round(frac/2)
    wire [4:0] rsh2 = (f5 + 5'd2) >> 2;   // round(frac/4)
    wire [4:0] rsh3 = (f5 + 5'd4) >> 3;   // round(frac/8)

    // [F4][BUG-LUT FIX] Profile-optimised bases, 9-bit delta
    reg [7:0] lut_base;
    reg [8:0] lut_delta;
    always @(*) begin
        case (index)
            3'd0: begin lut_base = 8'd128; lut_delta = {4'b0, frac};                                          end
            3'd1: begin lut_base = 8'd144; lut_delta = {4'b0, frac} + {4'b0, rsh2[3:0]};                     end
            3'd2: begin lut_base = 8'd164; lut_delta = {4'b0, frac} + {4'b0, rsh2[3:0]} + {4'b0, rsh3[3:0]}; end
            3'd3: begin lut_base = 8'd185; lut_delta = {4'b0, frac} + {4'b0, rsh1[3:0]} + {4'b0, rsh3[3:0]}; end
            3'd4: begin lut_base = 8'd210; lut_delta = {4'b0, frac} + {4'b0, rsh1[3:0]} + {4'b0, rsh2[3:0]}; end
            3'd5: begin lut_base = 8'd238; lut_delta = {4'b0, frac} + {4'b0, rsh1[3:0]} + {4'b0, rsh1[3:0]}; end
            3'd6: begin lut_base = 8'd250; lut_delta = {4'b0, frac} - {4'b0, rsh3[3:0]};                     end
            3'd7: begin lut_base = 8'd255; lut_delta = 9'd0;                                                   end
            default: begin lut_base = 8'd128; lut_delta = 9'd0; end
        endcase
    end

    // [F6] Clamp mantissa at 255 before shifting
    wire [8:0] mant_raw = {1'b0, lut_base} + lut_delta;
    wire [7:0] mant     = mant_raw[8] ? 8'd255 : mant_raw[7:0];

    // [F7][BUG-B FIX] Shift by |a|: two's complement magnitude of lower 3 bits
    //   a=-1: 4'b1111, a[2:0]=3'b111, ~111+1=001 -> shift 1  correct
    //   a=-2: 4'b1110, a[2:0]=3'b110, ~110+1=010 -> shift 2  correct
    //   a= 0: a[3]=0  -> no shift
    wire [2:0] a_mag   = ~a[2:0] + 3'd1;
    wire [8:0] shifted = a[3] ? ({1'b0, mant} >> a_mag) : {1'b0, mant};

    assign psum_exp = shifted[7:0];

endmodule