`timescale 1ns / 1ps


module boothmul(
input [2:0]in1,
input signed [7:0]in2,
output reg signed [8:0]out1
    );
    
    always@(*)begin
   
        out1 = 9'b000000000;
        case(in1)  
        3'b001,3'b010: begin
            out1 = in2;
        end
        3'b011: begin
             out1 = in2 << 1;
        end
        3'b100: begin
            out1 = -(in2 << 1);
        end
        3'b101,3'b110: begin
             out1 = -in2;
        end

        endcase      
    end
    
endmodule
