`timescale 1ns / 1ps
// =============================================================================
// boostvit_top.sv  --  SYNTHESIS WRAPPER for Vivado
// =============================================================================
//
// PURPOSE:
//   Clean registered I/O wrapper around the core BoostViT attention pipeline,
//   designed so you can synthesise against a realistic FPGA (or ASIC) target
//   and get meaningful LUT / FF / DSP / BRAM / power numbers that map back to
//   the paper's Table II and Fig. 9/10/11.
//
// WHY A WRAPPER?
//   Vivado reports area/timing/power on the TOP module's boundary.  A good
//   synthesis top:
//     - Registers ALL inputs (so setup/hold constraints are straightforward)
//     - Registers ALL outputs (so the tool can optimise inside without
//       hurting downstream timing)
//     - Has a single clock domain and synchronous reset
//     - Uses NO $exp / $rtoi / $finish / $display (all simulation-only)
//     - Parameterises key knobs so you can sweep THRESHOLD and LSB_SCALE
//       during synthesis characterisation
//
// TARGET DUT INSIDE:
//   attention_head -- the single 16x16 BSPE array + per-row expcalc_v2 +
//   softmax_from_exp_16.  This is the core of the paper's contribution
//   (Booth-Serial Skipping + LSB Scaling + LUT exp/log softmax).
//
// PORT COUNT is kept small and aligned to 8-bit (paper's INT8 datapath):
//   - 1 x 128-bit packed K column input (one column loaded per cycle when
//     load_k_en=1)
//   - 16 x 8-bit Q inputs (one row streamed per cycle when valid_q=1)
//   - 128-bit softmax output + 128-bit log-softmax output (+ debug ports)
//
// HOW TO SYNTHESISE IN VIVADO:
//   1. Create a project targeting e.g. XC7Z020 or XCZU7EV (Zynq).
//   2. Add ALL .sv / .v files from this directory as DESIGN sources.
//   3. Set `boostvit_top` as the top module.
//   4. Leave testbench .sv files as simulation-only (remove from design set).
//   5. Add timing constraints: create_clock -period 2.0 [get_ports clk]  (500 MHz)
//   6. Run synthesis -> Open Synthesized Design -> Reports:
//       Utilization (LUT / FF / DSP / BRAM)
//       Timing Summary (WNS / TNS)
//       Power (total on-chip, dynamic, static)
//   7. Compare these numbers to BoostViT paper Table III / Fig. 10.
// =============================================================================

module boostvit_top #(
    parameter BOOTH_LSB_SCALE = 1,     // 1 = paper's LSB scaling enabled
    parameter THRESHOLD       = 10     // attention-score early-termination
)(
    input  wire         clk,
    input  wire         rst_n,         // active-low for ZC702/ZCU104-style boards

    // ---- K loading ----
    input  wire         i_load_k_en,
    input  wire [3:0]   i_load_k_col,
    input  wire [127:0] i_k_in_packed,

    // ---- Q streaming ----
    input  wire [7:0]   i_q0,  i_q1,  i_q2,  i_q3,
    input  wire [7:0]   i_q4,  i_q5,  i_q6,  i_q7,
    input  wire [7:0]   i_q8,  i_q9,  i_q10, i_q11,
    input  wire [7:0]   i_q12, i_q13, i_q14, i_q15,
    input  wire         i_valid_q,

    // ---- Outputs (registered) ----
    output reg  [127:0] o_sm_out,       // Q1.7 unsigned softmax (primary)
    output reg  [127:0] o_lsm_out,      // Q3.5 signed log-softmax (debug)
    output reg  [127:0] o_exp_out,      // Q1.7 unsigned exp values (debug)
    output reg  [11:0]  o_es_out,       // sum of exp (debug)
    output reg          o_attn_valid
);

    // -------------------------------------------------------------------------
    // Active-high sync reset derived from active-low external reset
    // -------------------------------------------------------------------------
    reg rst_sync1, rst_sync2;
    always @(posedge clk) begin
        rst_sync1 <= ~rst_n;
        rst_sync2 <= rst_sync1;
    end
    wire rst = rst_sync2;

    // -------------------------------------------------------------------------
    // Registered inputs (first I/O stage)
    // -------------------------------------------------------------------------
    reg         load_k_en_r;
    reg [3:0]   load_k_col_r;
    reg [127:0] k_packed_r;
    reg [7:0]   q0_r,  q1_r,  q2_r,  q3_r;
    reg [7:0]   q4_r,  q5_r,  q6_r,  q7_r;
    reg [7:0]   q8_r,  q9_r,  q10_r, q11_r;
    reg [7:0]   q12_r, q13_r, q14_r, q15_r;
    reg         valid_q_r;

    always @(posedge clk) begin
        if (rst) begin
            load_k_en_r  <= 1'b0;
            load_k_col_r <= 4'd0;
            k_packed_r   <= 128'd0;
            { q0_r,  q1_r,  q2_r,  q3_r }  <= 32'd0;
            { q4_r,  q5_r,  q6_r,  q7_r }  <= 32'd0;
            { q8_r,  q9_r,  q10_r, q11_r } <= 32'd0;
            { q12_r, q13_r, q14_r, q15_r } <= 32'd0;
            valid_q_r    <= 1'b0;
        end else begin
            load_k_en_r  <= i_load_k_en;
            load_k_col_r <= i_load_k_col;
            k_packed_r   <= i_k_in_packed;
            q0_r  <= i_q0;  q1_r  <= i_q1;  q2_r  <= i_q2;  q3_r  <= i_q3;
            q4_r  <= i_q4;  q5_r  <= i_q5;  q6_r  <= i_q6;  q7_r  <= i_q7;
            q8_r  <= i_q8;  q9_r  <= i_q9;  q10_r <= i_q10; q11_r <= i_q11;
            q12_r <= i_q12; q13_r <= i_q13; q14_r <= i_q14; q15_r <= i_q15;
            valid_q_r    <= i_valid_q;
        end
    end

    // -------------------------------------------------------------------------
    // Core DUT: attention_head (systolic 16x16 BSPE + softmax)
    // -------------------------------------------------------------------------
    wire [127:0] sm_w;
    wire [127:0] lsm_w;
    wire [127:0] exp_w;
    wire [11:0]  es_w;
    wire         valid_w;

    attention_head #(
        .BOOTH_LSB_SCALE (BOOTH_LSB_SCALE),
        .THRESHOLD       (THRESHOLD)
    ) u_attn (
        .clk          (clk),
        .rst          (rst),
        .load_k_en    (load_k_en_r),
        .load_k_col   (load_k_col_r),
        .k_in_packed  (k_packed_r),
        .q0 (q0_r),  .q1 (q1_r),  .q2 (q2_r),  .q3 (q3_r),
        .q4 (q4_r),  .q5 (q5_r),  .q6 (q6_r),  .q7 (q7_r),
        .q8 (q8_r),  .q9 (q9_r),  .q10(q10_r), .q11(q11_r),
        .q12(q12_r), .q13(q13_r), .q14(q14_r), .q15(q15_r),
        .valid_q      (valid_q_r),
        .sm_out       (sm_w),
        .lsm_out      (lsm_w),
        .exp_dbg      (exp_w),
        .es_dbg       (es_w),
        .attn_valid   (valid_w)
    );

    // -------------------------------------------------------------------------
    // Registered outputs (second I/O stage)
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            o_sm_out     <= 128'd0;
            o_lsm_out    <= 128'd0;
            o_exp_out    <= 128'd0;
            o_es_out     <= 12'd0;
            o_attn_valid <= 1'b0;
        end else begin
            o_sm_out     <= sm_w;
            o_lsm_out    <= lsm_w;
            o_exp_out    <= exp_w;
            o_es_out     <= es_w;
            o_attn_valid <= valid_w;
        end
    end

endmodule
