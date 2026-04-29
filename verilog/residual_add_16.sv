`timescale 1ns / 1ps
// =============================================================================
// residual_add_16.sv  --  Signed-saturating INT8 + INT8 for 16 elements
//
// Paper Fig. 3: residual paths add encoder-block input X to the MHSA output
// (before LN2) and add the LN2/MLP output to create Y''.  Uses saturation
// to stay in signed INT8 range.
// =============================================================================
module residual_add_16 (
    input  wire [127:0] a_in,           // 16 x INT8  (primary branch)
    input  wire [127:0] b_in,           // 16 x INT8  (residual branch)
    output wire [127:0] y_out
);

    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : GEN_ADD
            wire signed [7:0] a = a_in[gi*8 +: 8];
            wire signed [7:0] b = b_in[gi*8 +: 8];
            wire signed [8:0] sum9 = {a[7], a} + {b[7], b};
            // Saturate to [-128, 127]
            reg signed [7:0] sat;
            always @* begin
                if (sum9 > 9'sd127)       sat = 8'sd127;
                else if (sum9 < -9'sd128) sat = -8'sd128;
                else                      sat = sum9[7:0];
            end
            assign y_out[gi*8 +: 8] = sat;
        end
    endgenerate
endmodule
