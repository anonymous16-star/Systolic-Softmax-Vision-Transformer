`timescale 1ns / 1ps

module ln_array_16x16 (
    input  wire [2047:0] x_in,         
    input  wire [127:0]  gamma,        
    input  wire [127:0]  beta,         
    output wire [2047:0] y_out
);

    genvar ti;
    generate
        for (ti = 0; ti < 16; ti = ti + 1) begin : GEN_LN
            layer_norm_16 u_ln (
                .x_in  (x_in [ti*128 +: 128]),
                .gamma (gamma[ti*8  +:   8]),  
                .beta  (beta [ti*8  +:   8]),
                .y_out (y_out[ti*128 +: 128])
            );
        end
    endgenerate

endmodule
