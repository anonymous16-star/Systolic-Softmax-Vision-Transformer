`timescale 1ns / 1ps
// =============================================================================
// ln_array_16x16.sv  --  16 parallel instances of layer_norm_16
//
// Paper reuses exp/reciprocal between SoftMax and LayerNorm.  For FPGA,
// it's cleaner to keep LN as an explicit array so the tools report a
// separate line item.  Each layer_norm_16 operates on one 16-element
// token vector; this block normalizes 16 tokens simultaneously.
// =============================================================================
module ln_array_16x16 (
    input  wire [2047:0] x_in,         // 16 tokens x 16 dims x 8b
    input  wire [127:0]  gamma,        // 16 x Q1.7 (one per dim)
    input  wire [127:0]  beta,         // 16 x Q3.5
    output wire [2047:0] y_out
);

    genvar ti;
    generate
        for (ti = 0; ti < 16; ti = ti + 1) begin : GEN_LN
            layer_norm_16 u_ln (
                .x_in  (x_in [ti*128 +: 128]),
                .gamma (gamma[ti*8  +:   8]),  // one gamma per token (simple)
                .beta  (beta [ti*8  +:   8]),
                .y_out (y_out[ti*128 +: 128])
            );
        end
    endgenerate

endmodule
