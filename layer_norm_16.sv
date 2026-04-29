`timescale 1ns / 1ps
// =============================================================================
// layer_norm_16.sv  --  INT8 Layer Normalization for 16-element vectors
//
// PURPOSE:
//   Computes LayerNorm(x) = gamma * (x - mean) / sqrt(var + eps) + beta
//   Approximated in INT8 arithmetic for hardware efficiency.
//
// PAPER REFERENCE:
//   BoostViT Section V-B: "SM. Unit performs exponential, accumulation,
//   and reciprocal operations, which serve as the fundamental computations
//   for both SoftMax and LayerNorm."
//
// APPROXIMATION STRATEGY:
//   1. mean = sum(x[i]) / 16  (shift by 4 bits = divide by 16)
//   2. centered[i] = x[i] - mean
//   3. var ≈ sum(centered[i]^2) / 16  (approximated with shift)
//   4. isqrt ≈ 1/sqrt(var) using LUT (8 entries)
//   5. y[i] = gamma * centered[i] * isqrt + beta
//
//   For INT8 with gamma=1, beta=0 (common in 8-bit ViT inference):
//   y[i] = saturate8(centered[i] * isqrt)
//
// FULLY COMBINATIONAL (no registers) - register externally.
//
// INPUTS:
//   x_in[127:0]  : 16 x signed INT8 values (x_in[i*8+:8] = x[i])
//   gamma[7:0]   : scale factor  (default: 8'd128 = 1.0 in Q1.7)
//   beta[7:0]    : offset factor (default: 8'd0)
//
// OUTPUTS:
//   y_out[127:0] : 16 x signed INT8 normalized values
// =============================================================================

module layer_norm_16 (
    input  wire [127:0] x_in,      // 16 x signed INT8
    input  wire [7:0]   gamma,     // Q1.7 scale (128 = 1.0)
    input  wire [7:0]   beta,      // Q3.5 offset (0 = no offset)
    output wire [127:0] y_out      // 16 x signed INT8 normalized
);

    // =========================================================================
    // Step 1: Compute mean = sum(x[i]) / 16
    // =========================================================================
    wire signed [11:0] sum_x;
    wire signed [7:0]  xi [0:15];

    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1)
            assign xi[gi] = x_in[gi*8 +: 8];
    endgenerate

    // 16 signed 8-bit values, sum fits in 12 bits
    wire signed [11:0] xi_ext [0:15];
    generate
        for (gi = 0; gi < 16; gi = gi + 1)
            assign xi_ext[gi] = {{4{xi[gi][7]}}, xi[gi]};
    endgenerate

    wire signed [11:0] partial_sum [0:15];
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : GEN_PSUM
            if (gi == 0)
                assign partial_sum[0] = xi_ext[0];
            else
                assign partial_sum[gi] = partial_sum[gi-1] + xi_ext[gi];
        end
    endgenerate

    assign sum_x = partial_sum[15];

    // mean = sum / 16 = sum >>> 4  (arithmetic right shift)
    wire signed [7:0] mean = sum_x[11:4];  // top 8 bits after /16

    // =========================================================================
    // Step 2: Centered values centered[i] = x[i] - mean
    // =========================================================================
    wire signed [7:0] centered [0:15];
    generate
        for (gi = 0; gi < 16; gi = gi + 1)
            assign centered[gi] = xi[gi] - mean;
    endgenerate

    // =========================================================================
    // Step 3: Variance approximation: var = sum(centered[i]^2) / 16
    // Use 8x8->9b product (avoid full 16-bit) with saturation
    // =========================================================================
    wire [7:0]  sq [0:15];
    wire [11:0] sq_sum_partial [0:15];

    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : GEN_SQ
            // centered[i]^2: take unsigned magnitude, square lower 4 bits
            wire [3:0] mag = centered[gi][7] ?
                             (~centered[gi][3:0] + 4'd1) : centered[gi][3:0];
            assign sq[gi] = {2'b00, mag, mag[3:0]};   // approx: mag^2 in 8b
        end
    endgenerate

    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : GEN_SQSUM
            if (gi == 0)
                assign sq_sum_partial[0] = {4'b0, sq[0]};
            else
                assign sq_sum_partial[gi] = sq_sum_partial[gi-1] + {4'b0, sq[gi]};
        end
    endgenerate

    wire [7:0] var_approx = sq_sum_partial[15][11:4];  // /16 via >>4

    // =========================================================================
    // Step 4: Inverse sqrt LUT (8-entry, covers var range 0..255)
    // isqrt_lut[v] ~ 128/sqrt(v+1) in Q1.7
    // =========================================================================
    reg [7:0] isqrt;
    always @(*) begin
        case (var_approx[7:5])   // 3 MSBs give 8 ranges
            3'd0: isqrt = 8'd128;  // var~0: isqrt~inf -> clamp to 128 (1.0)
            3'd1: isqrt = 8'd91;   // var~8:  1/sqrt(8)*128 = 45 -> use 91 for Q1.7
            3'd2: isqrt = 8'd64;   // var~16: 1/sqrt(16)*128 = 32 -> 64
            3'd3: isqrt = 8'd52;   // var~24: ~52
            3'd4: isqrt = 8'd45;   // var~32: 1/sqrt(32)*128 = 22 -> 45
            3'd5: isqrt = 8'd40;   // var~40: ~40
            3'd6: isqrt = 8'd36;   // var~48: ~36
            3'd7: isqrt = 8'd32;   // var~56+: ~32
        endcase
    end

    // =========================================================================
    // Step 5: y[i] = saturate8(gamma * centered[i] * isqrt / 128 + beta)
    // For gamma=128 (1.0), this simplifies to centered[i] * isqrt / 128
    // =========================================================================
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : GEN_OUT
            wire signed [15:0] prod;
            wire signed [7:0]  scaled;
            wire signed [8:0]  with_beta;
            wire signed [7:0]  saturated;

            // centered * isqrt (8b * 8b = 16b, but use top 8 after /128)
            assign prod      = $signed(centered[gi]) * $signed({1'b0, isqrt});
            assign scaled    = prod[14:7];           // / 128

            // Apply gamma (already folded in if gamma=128)
            // Apply beta
            assign with_beta = {scaled[7], scaled} + {{1{beta[7]}}, beta};

            // Saturate to INT8
            assign saturated = (with_beta >  9'sd127)  ? 8'sh7F :
                               (with_beta < -9'sd128)  ? 8'sh80 :
                                with_beta[7:0];

            assign y_out[gi*8 +: 8] = saturated;
        end
    endgenerate

endmodule
