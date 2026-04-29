`timescale 1ns / 1ps

module multi_head_attn #(
    parameter integer H_HEADS        = 3,
    parameter integer H_PARALLEL     = 1,
    parameter         BOOTH_LSB_SCALE = 1,
    parameter         THRESHOLD       = 10
)(
    input  wire                   clk,
    input  wire                   rst,

    
    input  wire [H_HEADS-1:0]     load_k_en_per_head,
    input  wire [3:0]             load_k_col,
    input  wire [H_HEADS*128-1:0] k_in_packed_per_head,

    
    input  wire [H_HEADS*128-1:0] q_packed_per_head,
    input  wire [H_HEADS-1:0]     valid_q_per_head,

    
    output wire [H_HEADS*128-1:0] sm_out_per_head,
    output wire [H_HEADS*128-1:0] lsm_out_per_head,
    output wire [H_HEADS-1:0]     attn_valid_per_head
);

    genvar hi;
    generate
        if (H_PARALLEL == 1) begin : GEN_PAR_HEADS
            for (hi = 0; hi < H_HEADS; hi = hi + 1) begin : GEN_HEAD
                wire [127:0] exp_dbg_unused;
                wire [11:0]  es_dbg_unused;
                attention_head #(
                    .BOOTH_LSB_SCALE(BOOTH_LSB_SCALE),
                    .THRESHOLD(THRESHOLD)
                ) u_head (
                    .clk(clk), .rst(rst),
                    .load_k_en  (load_k_en_per_head[hi]),
                    .load_k_col (load_k_col),
                    .k_in_packed(k_in_packed_per_head[hi*128 +: 128]),
                    .q0 (q_packed_per_head[hi*128 + 0   +: 8]),
                    .q1 (q_packed_per_head[hi*128 + 8   +: 8]),
                    .q2 (q_packed_per_head[hi*128 + 16  +: 8]),
                    .q3 (q_packed_per_head[hi*128 + 24  +: 8]),
                    .q4 (q_packed_per_head[hi*128 + 32  +: 8]),
                    .q5 (q_packed_per_head[hi*128 + 40  +: 8]),
                    .q6 (q_packed_per_head[hi*128 + 48  +: 8]),
                    .q7 (q_packed_per_head[hi*128 + 56  +: 8]),
                    .q8 (q_packed_per_head[hi*128 + 64  +: 8]),
                    .q9 (q_packed_per_head[hi*128 + 72  +: 8]),
                    .q10(q_packed_per_head[hi*128 + 80  +: 8]),
                    .q11(q_packed_per_head[hi*128 + 88  +: 8]),
                    .q12(q_packed_per_head[hi*128 + 96  +: 8]),
                    .q13(q_packed_per_head[hi*128 + 104 +: 8]),
                    .q14(q_packed_per_head[hi*128 + 112 +: 8]),
                    .q15(q_packed_per_head[hi*128 + 120 +: 8]),
                    .valid_q   (valid_q_per_head[hi]),
                    .sm_out    (sm_out_per_head [hi*128 +: 128]),
                    .lsm_out   (lsm_out_per_head[hi*128 +: 128]),
                    .exp_dbg   (exp_dbg_unused),
                    .es_dbg    (es_dbg_unused),
                    .attn_valid(attn_valid_per_head[hi])
                );
            end
        end else begin : GEN_SER_HEADS
            
            
            wire [127:0] mux_k, mux_q;
            wire         mux_load_k, mux_valid_q;
            wire [127:0] mux_sm, mux_lsm;
            wire [127:0] exp_dbg_unused;
            wire [11:0]  es_dbg_unused;
            wire         mux_valid;

            
            assign mux_k       = k_in_packed_per_head[127:0];
            assign mux_q       = q_packed_per_head   [127:0];
            assign mux_load_k  = load_k_en_per_head  [0];
            assign mux_valid_q = valid_q_per_head    [0];

            attention_head #(
                .BOOTH_LSB_SCALE(BOOTH_LSB_SCALE),
                .THRESHOLD(THRESHOLD)
            ) u_shared_head (
                .clk(clk), .rst(rst),
                .load_k_en(mux_load_k), .load_k_col(load_k_col),
                .k_in_packed(mux_k),
                .q0 (mux_q[0   +: 8]), .q1 (mux_q[8   +: 8]),
                .q2 (mux_q[16  +: 8]), .q3 (mux_q[24  +: 8]),
                .q4 (mux_q[32  +: 8]), .q5 (mux_q[40  +: 8]),
                .q6 (mux_q[48  +: 8]), .q7 (mux_q[56  +: 8]),
                .q8 (mux_q[64  +: 8]), .q9 (mux_q[72  +: 8]),
                .q10(mux_q[80  +: 8]), .q11(mux_q[88  +: 8]),
                .q12(mux_q[96  +: 8]), .q13(mux_q[104 +: 8]),
                .q14(mux_q[112 +: 8]), .q15(mux_q[120 +: 8]),
                .valid_q(mux_valid_q),
                .sm_out(mux_sm), .lsm_out(mux_lsm),
                .exp_dbg(exp_dbg_unused), .es_dbg(es_dbg_unused),
                .attn_valid(mux_valid)
            );

            for (hi = 0; hi < H_HEADS; hi = hi + 1) begin : GEN_BCAST
                assign sm_out_per_head   [hi*128 +: 128] = mux_sm;
                assign lsm_out_per_head  [hi*128 +: 128] = mux_lsm;
                assign attn_valid_per_head[hi]           = mux_valid;
            end
        end
    endgenerate

endmodule
