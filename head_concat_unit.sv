`timescale 1ns / 1ps
// =============================================================================
// head_concat_unit.sv  --  Concatenate H head outputs into H*16 element vector
//
// Paper Eq. 1: OAttn = Concat(H_1..H_H) * W_O
//
// For DeiT-Tiny H=3: concatenation gives 3*16 = 48-lane vector that then
// gets processed by W_O (linear projection) in 3 dim-tiles.
//
// This module provides a tile selector: given cur_d_sub in [0..H_HEADS-1],
// it picks the matching head's 16-lane output.  Controller iterates through
// cur_d_sub to feed W_O linear_proj with successive head outputs.
//
// Also provides a registered fanout of all H heads for simultaneous view
// in synthesis reports (keeps the multi-head paths alive).
// =============================================================================

module head_concat_unit #(
    parameter integer H_HEADS = 3
)(
    input  wire                   clk,
    input  wire                   rst,

    input  wire [H_HEADS*128-1:0] per_head_in,       // flattened
    input  wire [3:0]             sel_head,          // which head to emit
    output reg  [127:0]           concat_out,        // selected head's 128b vec

    // Also expose registered version of all heads for observability
    output reg  [H_HEADS*128-1:0] all_heads_reg,

    // Combined sum-reduce (for debug: stays alive in synth)
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
            // Mux out selected head
            concat_out    <= per_head_in[sel_head*128 +: 128];
            all_heads_reg <= per_head_in;
            // Sum-reduce across heads per byte lane
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
