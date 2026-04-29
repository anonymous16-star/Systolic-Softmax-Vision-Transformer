`timescale 1ns / 1ps


module boothencoder (
    input  [8:0] kext,          
    output [2:0] bu1,           
    output [2:0] bu2,           
    output [2:0] bu3,           
    output [2:0] bu4            
);

    assign bu1 = kext[8:6];
    assign bu2 = kext[6:4];
    assign bu3 = kext[4:2];
    assign bu4 = kext[2:0];

endmodule