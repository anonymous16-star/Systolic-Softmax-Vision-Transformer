`timescale 1ns / 1ps



module boostvit_top #(
    parameter BOOTH_LSB_SCALE = 1,     
    parameter THRESHOLD       = 10     
)(
    input  wire         clk,
    input  wire         rst_n,         

    
    input  wire         i_load_k_en,
    input  wire [3:0]   i_load_k_col,
    input  wire [127:0] i_k_in_packed,

    
    input  wire [7:0]   i_q0,  i_q1,  i_q2,  i_q3,
    input  wire [7:0]   i_q4,  i_q5,  i_q6,  i_q7,
    input  wire [7:0]   i_q8,  i_q9,  i_q10, i_q11,
    input  wire [7:0]   i_q12, i_q13, i_q14, i_q15,
    input  wire         i_valid_q,

    
    output reg  [127:0] o_sm_out,       
    output reg  [127:0] o_lsm_out,      
    output reg  [127:0] o_exp_out,      
    output reg  [11:0]  o_es_out,       
    output reg          o_attn_valid
);

    reg rst_sync1, rst_sync2;
    always @(posedge clk) begin
        rst_sync1 <= ~rst_n;
        rst_sync2 <= rst_sync1;
    end
    wire rst = rst_sync2;
 
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
