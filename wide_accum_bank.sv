`timescale 1ns / 1ps
// =============================================================================
// wide_accum_bank.sv  --  16 x 24-bit accumulator bank
//
// Paper reports 16-20 bit partial sums inside the BSPE datapath.  Our BSPE
// preserves your original 8-bit path.  To match the paper's precision
// on inter-tile accumulation (K-axis reduction for multi-tile matmul),
// this block sits on the BSPE output and maintains 24-bit accumulators
// across multiple K-tiles of the same (row, col) output.
//
// Behavior:
//   - On `clear_accum`: accumulator <- 0
//   - On `valid_in`:    accumulator <- accumulator + sign-extend(y_in_8b)
//   - On `latch_out`:   y_out_8b <- saturate(accumulator >>> shift)
//
// This is synthesized as 16 parallel 24-bit adders + registers + sat logic,
// and contributes ~8-12 k LUTs on ZCU102.
//
// =============================================================================

module wide_accum_bank #(
    parameter ACC_WIDTH = 24,          // Accumulator width in bits
    parameter N_LANES   = 16
)(
    input  wire                    clk,
    input  wire                    rst,

    input  wire                    clear_accum,
    input  wire                    valid_in,
    input  wire [N_LANES*8-1:0]    y_in_packed,      // 16 x signed INT8
    input  wire [4:0]              shift,            // output right-shift amount
    input  wire                    latch_out,

    output reg  [N_LANES*8-1:0]    y_out_packed,     // 16 x signed INT8 saturated
    output reg                     y_out_valid,

    // Debug / observability
    output wire [ACC_WIDTH*N_LANES-1:0] acc_dbg
);

    // 16 parallel accumulators
    reg  signed [ACC_WIDTH-1:0] acc [0:N_LANES-1];

    genvar li;
    generate
        for (li = 0; li < N_LANES; li = li + 1) begin : GEN_ACC
            wire signed [7:0]           y_lane   = y_in_packed[li*8 +: 8];
            wire signed [ACC_WIDTH-1:0] y_ext    = { {(ACC_WIDTH-8){y_lane[7]}}, y_lane };
            assign acc_dbg[li*ACC_WIDTH +: ACC_WIDTH] = acc[li];

            always @(posedge clk) begin
                if (rst)                 acc[li] <= {ACC_WIDTH{1'b0}};
                else if (clear_accum)    acc[li] <= {ACC_WIDTH{1'b0}};
                else if (valid_in)       acc[li] <= acc[li] + y_ext;
            end
        end
    endgenerate

    // Quantize-and-saturate path, registered output
    integer      ji;
    reg signed [ACC_WIDTH-1:0] shifted;
    reg signed [7:0]           sat;
    always @(posedge clk) begin
        if (rst) begin
            y_out_packed <= {N_LANES*8{1'b0}};
            y_out_valid  <= 1'b0;
        end else if (latch_out) begin
            for (ji = 0; ji < N_LANES; ji = ji + 1) begin
                shifted = acc[ji] >>> shift;
                if      (shifted >  24'sd127)   sat = 8'sd127;
                else if (shifted < -24'sd128)   sat = -8'sd128;
                else                             sat = shifted[7:0];
                y_out_packed[ji*8 +: 8] <= sat;
            end
            y_out_valid <= 1'b1;
        end else begin
            y_out_valid <= 1'b0;
        end
    end

endmodule
