`timescale 1ns / 1ps
// =============================================================================
// fifo - Synchronous First-Word-Fall-Through (FWFT) FIFO
//
// CORNER-CASE FIX [C1] (vs original):
//   - DEPTH changed from 9 -> 16 (power of 2).  Original had a subtle
//     pointer wrap-around bug: wr_ptr/rd_ptr lower ADDR_WIDTH=4 bits wrap
//     at 16 while mem[] only had 9 entries; mem[9..15] was undefined if
//     the ptr ever reached those indices.  With DEPTH=16 the mask exactly
//     matches the array size, eliminating the bug.
//   - Paper (BoostViT Section V-B) uses FIFO depth == max timing skew;
//     depth=16 is a safe over-provision that behaves identically for the
//     skew range 0..9 but avoids the latent overflow bug.
// =============================================================================

module fifo #(
    parameter WIDTH      = 8,
    parameter DEPTH      = 16,      // FIXED: was 9 (non-pow2). Now 16.
    parameter ADDR_WIDTH = 4
)(
    input                  clk,
    input                  rst,

    input                  wr_en,
    input  [WIDTH-1:0]     din,

    input                  rd_en,
    output [WIDTH-1:0]     dout,

    output                 full,
    output                 empty
);

    reg [WIDTH-1:0]      mem [0:DEPTH-1];
    reg [ADDR_WIDTH:0]   wr_ptr;
    reg [ADDR_WIDTH:0]   rd_ptr;

    initial begin : init_blk
        integer i0;
        wr_ptr = 0; rd_ptr = 0;
        for (i0 = 0; i0 < DEPTH; i0 = i0 + 1) mem[i0] = {WIDTH{1'b0}};
    end

    integer k;

    always @(posedge clk) begin
        if (rst) begin
            wr_ptr <= {(ADDR_WIDTH+1){1'b0}};
            for (k = 0; k < DEPTH; k = k + 1)
                mem[k] <= {WIDTH{1'b0}};
        end
        else if (wr_en && !full) begin
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= din;
            wr_ptr <= wr_ptr + 1'b1;
        end
    end

    always @(posedge clk) begin
        if (rst)
            rd_ptr <= {(ADDR_WIDTH+1){1'b0}};
        else if (rd_en && !empty)
            rd_ptr <= rd_ptr + 1'b1;
    end

    assign empty = (wr_ptr == rd_ptr);
    assign full  = (wr_ptr[ADDR_WIDTH]     != rd_ptr[ADDR_WIDTH]) &&
                   (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);

    // FWFT bypass
    assign dout = (empty  && wr_en)              ? din :
                  (rd_en  && wr_en && !empty)    ? din :
                  mem[rd_ptr[ADDR_WIDTH-1:0]];

endmodule
