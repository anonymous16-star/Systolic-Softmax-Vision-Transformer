`timescale 1ns / 1ps

module gelu_approx_16 (
    input  wire [127:0] x_in,
    output wire [127:0] y_out
);
    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : GEN_GELU
            wire signed [7:0] xi = x_in[gi*8 +: 8];
            assign y_out[gi*8 +: 8] =
                   (xi[7] == 1'b0) ? xi                        
                                   : {{3{xi[7]}}, xi[7:3]};     
        end
    endgenerate
endmodule
