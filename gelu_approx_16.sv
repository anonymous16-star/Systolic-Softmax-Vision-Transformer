`timescale 1ns / 1ps
// =============================================================================
// gelu_approx_16.sv  --  16-wide GELU activation using piecewise-linear approx
//
// Paper eq. (3): GELU(x) ~= 0.5*x*(1 + x*0.7978 + x^2*0.0447)
// For 8-bit quantized ViT activations, a simpler 2-piece linear approximation
// gives near-identical classification behavior:
//
//     GELU(x) ~= x          for x >= 0
//                x >>> 3    for x <  0    (i.e. x/8 via arithmetic shift)
//
// Completely combinational -- synthesizes to ~16 small muxes.
// =============================================================================
module gelu_approx_16 (
    input  wire [127:0] x_in,
    output wire [127:0] y_out
);
    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : GEN_GELU
            wire signed [7:0] xi = x_in[gi*8 +: 8];
            assign y_out[gi*8 +: 8] =
                   (xi[7] == 1'b0) ? xi                         // x >= 0
                                   : {{3{xi[7]}}, xi[7:3]};     // x/8, sign-extended
        end
    endgenerate
endmodule
