`timescale 1ns / 1ps


module sm_unit (
    input  wire [127:0] x_in,      
    output wire [127:0] e_out,     
    output wire [127:0] sm_out,    
    output wire [127:0] lsm_out,   
    output wire [11:0]  es_sum     
);

    wire signed [7:0] xi [0:15];
    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : GEN_UNPACK
            assign xi[gi] = x_in[gi*8 +: 8];
        end
    endgenerate

    
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

    
    
    wire [127:0] x_shifted;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : GEN_SUB
            wire signed [8:0] d9 = {xi[gi][7], xi[gi]} - {x_max[7], x_max};
            assign x_shifted[gi*8 +: 8] = (d9 < -9'sd128) ? 8'sh80 : d9[7:0];
        end
    endgenerate

    
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : GEN_EXP
            expcalc_v2 u_exp (
                .psum     (x_shifted[gi*8 +: 8]),
                .psum_exp (e_out[gi*8 +: 8])
            );
        end
    endgenerate
 
    softmax_from_exp_16 u_sm (
        .e_in   (e_out),
        .sm_out (sm_out),
        .lsm_out(lsm_out),
        .es_sum (es_sum)
    );

endmodule
