`timescale 1ns / 1ps



module boostvit_full_top #(
    parameter BOOTH_LSB_SCALE = 1,
    parameter THRESHOLD       = 10
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         i_load_k_en,
    input  wire [3:0]   i_load_k_col,
    input  wire [127:0] i_k_in_packed,
    input  wire [7:0]   i_q0, i_q1, i_q2, i_q3, i_q4, i_q5, i_q6, i_q7,
    input  wire [7:0]   i_q8, i_q9, i_q10, i_q11, i_q12, i_q13, i_q14, i_q15,
    input  wire         i_valid_q,
    input  wire [2047:0] i_ln_x_in,
    input  wire [127:0]  i_ln_gamma, i_ln_beta,
    input  wire [127:0]  i_gelu_in,
    output reg  [127:0] o_sm_out,
    output reg  [127:0] o_lsm_out,
    output reg  [127:0] o_exp_out,
    output reg  [11:0]  o_es_out,
    output reg          o_attn_valid,
    output reg  [2047:0] o_ln_out,
    output reg  [127:0]  o_gelu_out
);

    reg rst_s1, rst_s2;
    always @(posedge clk) begin rst_s1 <= ~rst_n; rst_s2 <= rst_s1; end
    wire rst = rst_s2;

    reg         load_k_en_r;
    reg [3:0]   load_k_col_r;
    reg [127:0] k_packed_r;
    reg [7:0]   q_r [0:15];
    reg         valid_q_r;
    reg [2047:0] ln_x_r;
    reg [127:0]  ln_g_r, ln_b_r;
    reg [127:0]  gelu_r;
    integer ii;

    always @(posedge clk) begin
        if (rst) begin
            load_k_en_r <= 0; load_k_col_r <= 0; k_packed_r <= 0;
            for (ii=0; ii<16; ii=ii+1) q_r[ii] <= 0;
            valid_q_r <= 0;
            ln_x_r <= 0; ln_g_r <= 0; ln_b_r <= 0; gelu_r <= 0;
        end else begin
            load_k_en_r  <= i_load_k_en;
            load_k_col_r <= i_load_k_col;
            k_packed_r   <= i_k_in_packed;
            q_r[0] <= i_q0;  q_r[1] <= i_q1;  q_r[2] <= i_q2;  q_r[3] <= i_q3;
            q_r[4] <= i_q4;  q_r[5] <= i_q5;  q_r[6] <= i_q6;  q_r[7] <= i_q7;
            q_r[8] <= i_q8;  q_r[9] <= i_q9;  q_r[10]<= i_q10; q_r[11]<= i_q11;
            q_r[12]<= i_q12; q_r[13]<= i_q13; q_r[14]<= i_q14; q_r[15]<= i_q15;
            valid_q_r <= i_valid_q;
            ln_x_r    <= i_ln_x_in;
            ln_g_r    <= i_ln_gamma;
            ln_b_r    <= i_ln_beta;
            gelu_r    <= i_gelu_in;
        end
    end

    wire [127:0] sm_w, lsm_w, exp_w;
    wire [11:0]  es_w;
    wire         valid_w;

    attention_head #(.BOOTH_LSB_SCALE(BOOTH_LSB_SCALE), .THRESHOLD(THRESHOLD))
    u_attn (
        .clk(clk), .rst(rst),
        .load_k_en(load_k_en_r), .load_k_col(load_k_col_r), .k_in_packed(k_packed_r),
        .q0(q_r[0]),  .q1(q_r[1]),  .q2(q_r[2]),  .q3(q_r[3]),
        .q4(q_r[4]),  .q5(q_r[5]),  .q6(q_r[6]),  .q7(q_r[7]),
        .q8(q_r[8]),  .q9(q_r[9]),  .q10(q_r[10]), .q11(q_r[11]),
        .q12(q_r[12]), .q13(q_r[13]), .q14(q_r[14]), .q15(q_r[15]),
        .valid_q(valid_q_r),
        .sm_out(sm_w), .lsm_out(lsm_w), .exp_dbg(exp_w), .es_dbg(es_w),
        .attn_valid(valid_w)
    );

    wire [2047:0] ln_w;
    ln_array_16x16 u_ln (.x_in(ln_x_r), .gamma(ln_g_r), .beta(ln_b_r), .y_out(ln_w));

    wire [127:0] gelu_w;
    gelu_approx_16 u_gelu (.x_in(gelu_r), .y_out(gelu_w));

    always @(posedge clk) begin
        if (rst) begin
            o_sm_out <= 0; o_lsm_out <= 0; o_exp_out <= 0;
            o_es_out <= 0; o_attn_valid <= 0;
            o_ln_out <= 0; o_gelu_out <= 0;
        end else begin
            o_sm_out     <= sm_w;
            o_lsm_out    <= lsm_w;
            o_exp_out    <= exp_w;
            o_es_out     <= es_w;
            o_attn_valid <= valid_w;
            o_ln_out     <= ln_w;
            o_gelu_out   <= gelu_w;
        end
    end

endmodule
