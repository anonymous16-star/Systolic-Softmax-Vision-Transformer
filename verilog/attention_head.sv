`timescale 1ns / 1ps
// =============================================================================
// attention_head.sv  --  Single-head attention: S = softmax(Q * K^T)
//
// PURPOSE:
//   Implements one attention head of Multi-Head Self-Attention.
//   Wraps the 16x16 BSPE systolic array with Booth-Serial Skipping and
//   exposes BOTH normal softmax (for V multiplication) and log-softmax
//   (for analysis / comparison with the BoostViT paper's lsm_out).
//
// BOOTH-FRIENDLY LSB SCALING (paper Section IV-B-1):
//   If k > 0: bits [5:3] (4th-6th LSBs) set to 1s   (k | 0x38)
//   If k < 0: bits [5:3] set to 0s                   (k & 0xC7)
//   Applied BEFORE loading K into the array.
//   Paper reports skip rate goes from 36.5% to 56.4% with minimal acc drop.
//
// dk SCALING:
//   Paper scales Q*K^T by 1/sqrt(dk) in software before feeding to hardware.
//   For dk=16 this is a >>2 right-shift that the caller applies to Q.
//
// OUTPUTS:
//   sm_out  : 16 Q1.7 unsigned softmax weights  (PRIMARY - used by MHSA)
//   lsm_out : 16 Q3.5 signed log-softmax        (DEBUG / paper-style)
//   exp_dbg : 16 Q1.7 unsigned exp values       (DEBUG)
//   es_dbg  : sum of exp                        (DEBUG)
// =============================================================================

module attention_head #(
    parameter BOOTH_LSB_SCALE = 1,   // 1: enable Booth-friendly LSB scaling
    parameter THRESHOLD       = 10   // attention score early-termination threshold
)(
    input  wire        clk,
    input  wire        rst,

    // K loading: caller loads K weights one column at a time
    input  wire        load_k_en,    // 1 = load k_col into column load_k_col
    input  wire [3:0]  load_k_col,   // which column (0..15) to load
    input  wire [127:0] k_in_packed, // 16x8b: k_in_packed[r*8+:8] = K[r, load_k_col]

    // Q streaming: one row of Q per valid_q cycle
    input  wire [7:0]  q0,  q1,  q2,  q3,
    input  wire [7:0]  q4,  q5,  q6,  q7,
    input  wire [7:0]  q8,  q9,  q10, q11,
    input  wire [7:0]  q12, q13, q14, q15,
    input  wire        valid_q,

    // Outputs
    output wire [127:0] sm_out,     // 16 Q1.7 unsigned softmax        <-- PRIMARY
    output wire [127:0] lsm_out,    // 16 Q3.5 signed log-softmax      <-- DEBUG
    output wire [127:0] exp_dbg,    // 16 Q1.7 unsigned exp values     <-- DEBUG
    output wire [11:0]  es_dbg,     // sum of exp                      <-- DEBUG
    output wire         attn_valid
);

    // =========================================================================
    // Booth-Friendly LSB Scaling  (paper Section IV-B-1)
    // =========================================================================
    function automatic [7:0] apply_lsb_scale(input signed [7:0] k);
        if (BOOTH_LSB_SCALE) begin
            if (!k[7])   // k >= 0
                apply_lsb_scale = k | 8'b0011_1000;   // set bits [5:3]
            else         // k < 0
                apply_lsb_scale = k & 8'b1100_0111;   // clear bits [5:3]
        end else begin
            apply_lsb_scale = k;
        end
    endfunction

    wire [127:0] k_scaled;
    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : GEN_KSCALE
            assign k_scaled[gi*8 +: 8] = apply_lsb_scale(k_in_packed[gi*8 +: 8]);
        end
    endgenerate

    // =========================================================================
    // load_k_col (0..15) -> load_kc1..16 one-hot strobe decoder
    // =========================================================================
    wire [15:0] load_kc_vec = load_k_en ? (16'h0001 << load_k_col) : 16'h0000;

    // =========================================================================
    // Systolic array with softmax (uses new softmax_from_exp_16)
    // =========================================================================
    systolic_16x16_softmax u_sys_sm (
        .clk       (clk),
        .rst       (rst),
        .load_kc1  (load_kc_vec[0]),  .load_kc2  (load_kc_vec[1]),
        .load_kc3  (load_kc_vec[2]),  .load_kc4  (load_kc_vec[3]),
        .load_kc5  (load_kc_vec[4]),  .load_kc6  (load_kc_vec[5]),
        .load_kc7  (load_kc_vec[6]),  .load_kc8  (load_kc_vec[7]),
        .load_kc9  (load_kc_vec[8]),  .load_kc10 (load_kc_vec[9]),
        .load_kc11 (load_kc_vec[10]), .load_kc12 (load_kc_vec[11]),
        .load_kc13 (load_kc_vec[12]), .load_kc14 (load_kc_vec[13]),
        .load_kc15 (load_kc_vec[14]), .load_kc16 (load_kc_vec[15]),
        .k         (k_scaled),
        .q0(q0), .q1(q1), .q2(q2), .q3(q3),
        .q4(q4), .q5(q5), .q6(q6), .q7(q7),
        .q8(q8), .q9(q9), .q10(q10), .q11(q11),
        .q12(q12), .q13(q13), .q14(q14), .q15(q15),
        .valid_q   (valid_q),
        .sm_out    (sm_out),
        .lsm_out   (lsm_out),
        .e_row     (exp_dbg),
        .es_sum    (es_dbg),
        .exp_valid (attn_valid)
    );

endmodule
