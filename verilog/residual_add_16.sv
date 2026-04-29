`timescale 1ns / 1ps

module residual_add_16 (
    input  wire [127:0] a_in,           
    input  wire [127:0] b_in,           
    output wire [127:0] y_out
);

    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : GEN_ADD
            wire signed [7:0] a = a_in[gi*8 +: 8];
            wire signed [7:0] b = b_in[gi*8 +: 8];
            wire signed [8:0] sum9 = {a[7], a} + {b[7], b};
            
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
