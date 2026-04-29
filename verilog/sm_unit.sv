`timescale 1ns / 1ps
// =============================================================================
// sm_unit.sv  --  Paper's "SM. Unit" (Fig. 6, Section V-B-2)
//
//   Quote: "The SM. Unit performs exponential, accumulation, and reciprocal
//           operations, which serve as the fundamental computations for both
//           SoftMax and LayerNorm."
//
// This is a wrapper that bundles the three fundamental primitives
// (expcalc_v2, accumulator, logcalc_wide_v2 for reciprocal-via-log) into
// a single block so Vivado's synthesis hierarchy reports it as one unit.
//
//   Mode 0 (SOFTMAX): e[i] = exp(x[i] - x_max), s = Sum(e), y = e/s
//   Mode 1 (LN_VAR) : ignored here (LN reuses layer_norm_16 per-token);
//                     present for completeness of paper's block diagram.
//
// Uses your LUT-based expcalc_v2 / logcalc_wide_v2 -- NOT Taylor.
//
// This module is COMBINATIONAL in the data path; the "accumulation" is
// a fully-unrolled 16-input adder tree.
// =============================================================================

module sm_unit (
    input  wire [127:0] x_in,      // 16 x signed INT8 logits
    output wire [127:0] e_out,     // per-element exp, Q1.7 unsigned
    output wire [127:0] sm_out,    // softmax, Q1.7 unsigned (sums to ~128)
    output wire [127:0] lsm_out,   // log-softmax, Q3.5 signed
    output wire [11:0]  es_sum     // sum of e, 12-bit unsigned
);

    // ---- Stage 1: subtract max (prevents exp-overflow, same result
    //       due to softmax invariance).  We compute max via 16-way tree.
    wire signed [7:0] xi [0:15];
    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : GEN_UNPACK
            assign xi[gi] = x_in[gi*8 +: 8];
        end
    endgenerate

    // 16-way max reduction
    function signed [7:0] smax;
        input signed [7:0] a, b;
        smax = (a > b) ? a : b;
    endfunction

    wire signed [7:0] m01  = smax(xi[0],  xi[1]);
    wire signed [7:0] m23  = smax(xi[2],  xi[3]);
    wire signed [7:0] m45  = smax(xi[4],  xi[5]);
    wire signed [7:0] m67  = smax(xi[6],  xi[7]);
    wire signed [7:0] m89  = smax(xi[8],  xi[9]);
    wire signed [7:0] mab  = smax(xi[10], xi[11]);
    wire signed [7:0] mcd  = smax(xi[12], xi[13]);
    wire signed [7:0] mef  = smax(xi[14], xi[15]);
    wire signed [7:0] m0_3 = smax(m01, m23);
    wire signed [7:0] m4_7 = smax(m45, m67);
    wire signed [7:0] m8_b = smax(m89, mab);
    wire signed [7:0] mc_f = smax(mcd, mef);
    wire signed [7:0] mhi  = smax(m0_3, m4_7);
    wire signed [7:0] mlo  = smax(m8_b, mc_f);
    wire signed [7:0] x_max = smax(mhi, mlo);

    // Subtract max (saturated to <= 0, fits in signed 8-bit since
    // all differences are <= 0)
    wire [127:0] x_shifted;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : GEN_SUB
            wire signed [8:0] d9 = {xi[gi][7], xi[gi]} - {x_max[7], x_max};
            assign x_shifted[gi*8 +: 8] = (d9 < -9'sd128) ? 8'sh80 : d9[7:0];
        end
    endgenerate

    // ---- Stage 2: 16 parallel expcalc_v2 (your LUT-based exp)
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : GEN_EXP
            expcalc_v2 u_exp (
                .psum     (x_shifted[gi*8 +: 8]),
                .psum_exp (e_out[gi*8 +: 8])
            );
        end
    endgenerate

    // ---- Stage 3: softmax normalization via your softmax_from_exp_16
    //  (which does accumulation + reciprocal-via-log internally)
    softmax_from_exp_16 u_sm (
        .e_in   (e_out),
        .sm_out (sm_out),
        .lsm_out(lsm_out),
        .es_sum (es_sum)
    );

endmodule
