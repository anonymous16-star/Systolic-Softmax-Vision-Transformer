`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 29.01.2026 19:27:21
// Design Name: 
// Module Name: boothmul
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module boothmul(
input [2:0]in1,
input signed [7:0]in2,
output reg signed [8:0]out1
    );
    
    always@(*)begin
   
        out1 = 9'b000000000;
        case(in1)
      //  3'b000,3'b111: begin
       // end
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
