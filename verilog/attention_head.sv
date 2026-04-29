`timescale 1ns / 1ps


module attention_head #(
    parameter BOOTH_LSB_SCALE = 1,   
    parameter THRESHOLD       = 10   
)(
    input  wire        clk,
    input  wire        rst,

    
    input  wire        load_k_en,    
    input  wire [3:0]  load_k_col,   
    input  wire [127:0] k_in_packed, 

    
    input  wire [7:0]  q0,  q1,  q2,  q3,
    input  wire [7:0]  q4,  q5,  q6,  q7,
    input  wire [7:0]  q8,  q9,  q10, q11,
    input  wire [7:0]  q12, q13, q14, q15,
    input  wire        valid_q,

    
    output wire [127:0] sm_out,     
    output wire [127:0] lsm_out,    
    output wire [127:0] exp_dbg,    
    output wire [11:0]  es_dbg,     
    output wire         attn_valid
);

    
    function automatic [7:0] apply_lsb_scale(input signed [7:0] k);
        if (BOOTH_LSB_SCALE) begin
            if (!k[7])   
                apply_lsb_scale = k | 8'b0011_1000;  
            else         
                apply_lsb_scale = k & 8'b1100_0111;   
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


    wire [15:0] load_kc_vec = load_k_en ? (16'h0001 << load_k_col) : 16'h0000;


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
