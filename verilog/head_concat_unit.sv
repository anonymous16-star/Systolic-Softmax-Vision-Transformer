`timescale 1ns / 1ps


module head_concat_unit #(
    parameter integer H_HEADS = 3
)(
    input  wire                   clk,
    input  wire                   rst,

    input  wire [H_HEADS*128-1:0] per_head_in,       
    input  wire [3:0]             sel_head,          
    output reg  [127:0]           concat_out,        

    
    output reg  [H_HEADS*128-1:0] all_heads_reg,

    
    output reg  [127:0]           sum_reduce_reg
);
    integer hi, bi;
    reg signed [11:0] sum_byte;
    reg signed [7:0]  sum_sat;
    always @(posedge clk) begin
        if (rst) begin
            concat_out     <= 128'd0;
            all_heads_reg  <= {(H_HEADS*128){1'b0}};
            sum_reduce_reg <= 128'd0;
        end else begin
            concat_out    <= per_head_in[sel_head*128 +: 128];
            all_heads_reg <= per_head_in;
            for (bi = 0; bi < 16; bi = bi + 1) begin
                sum_byte = 0;
                for (hi = 0; hi < H_HEADS; hi = hi + 1) begin
                    sum_byte = sum_byte
                            + $signed(per_head_in[hi*128 + bi*8 +: 8]);
                end
                if      (sum_byte >  12'sd127) sum_sat = 8'sd127;
                else if (sum_byte < -12'sd128) sum_sat = -8'sd128;
                else                            sum_sat = sum_byte[7:0];
                sum_reduce_reg[bi*8 +: 8] <= sum_sat;
            end
        end
    end

endmodule
