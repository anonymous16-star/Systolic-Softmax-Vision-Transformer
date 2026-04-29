`timescale 1ns / 1ps

module expcalc_v2 (
    input  wire signed [7:0] psum,     
    output wire        [7:0] psum_exp   
);

    wire signed [7:0] psum_sat = psum[7] ? psum : 8'sh00;

    wire signed [9:0] ps10 = {{2{psum_sat[7]}}, psum_sat};
    wire signed [9:0] t;
    assign t = ps10
             + (ps10 >>> 2)
             + (ps10 >>> 3)
             + (ps10 >>> 4)
             + (ps10 >>> 7);

    wire signed [3:0] a;
    assign a = t >>> 7;

    
    wire signed [9:0] a10   = {{6{a[3]}}, a};
    wire signed [9:0] a_ln2 = (a10 <<< 6) + (a10 <<< 4) + (a10 <<< 3) + a10;

    wire signed [9:0] r_raw = {{2{psum_sat[7]}}, psum_sat} - a_ln2;
    wire        [6:0] r     = r_raw[9] ? 7'd0 : r_raw[6:0];

    wire [2:0] index = r[6:4];
    wire [3:0] frac  = r[3:0];

    wire [4:0] f5   = {1'b0, frac};
    wire [4:0] rsh1 = (f5 + 5'd1) >> 1;   
    wire [4:0] rsh2 = (f5 + 5'd2) >> 2; 
    wire [4:0] rsh3 = (f5 + 5'd4) >> 3;   

    reg [7:0] lut_base;
    reg [8:0] lut_delta;
    always @(*) begin
        case (index)
            3'd0: begin lut_base = 8'd128; lut_delta = {4'b0, frac};                                          end
            3'd1: begin lut_base = 8'd144; lut_delta = {4'b0, frac} + {4'b0, rsh2[3:0]};                     end
            3'd2: begin lut_base = 8'd164; lut_delta = {4'b0, frac} + {4'b0, rsh2[3:0]} + {4'b0, rsh3[3:0]}; end
            3'd3: begin lut_base = 8'd185; lut_delta = {4'b0, frac} + {4'b0, rsh1[3:0]} + {4'b0, rsh3[3:0]}; end
            3'd4: begin lut_base = 8'd210; lut_delta = {4'b0, frac} + {4'b0, rsh1[3:0]} + {4'b0, rsh2[3:0]}; end
            3'd5: begin lut_base = 8'd238; lut_delta = {4'b0, frac} + {4'b0, rsh1[3:0]} + {4'b0, rsh1[3:0]}; end
            3'd6: begin lut_base = 8'd250; lut_delta = {4'b0, frac} - {4'b0, rsh3[3:0]};                     end
            3'd7: begin lut_base = 8'd255; lut_delta = 9'd0;                                                   end
            default: begin lut_base = 8'd128; lut_delta = 9'd0; end
        endcase
    end

    wire [8:0] mant_raw = {1'b0, lut_base} + lut_delta;
    wire [7:0] mant     = mant_raw[8] ? 8'd255 : mant_raw[7:0];

   
    wire [2:0] a_mag   = ~a[2:0] + 3'd1;
    wire [8:0] shifted = a[3] ? ({1'b0, mant} >> a_mag) : {1'b0, mant};

    assign psum_exp = shifted[7:0];

endmodule