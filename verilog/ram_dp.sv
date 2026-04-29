`timescale 1ns / 1ps
// =============================================================================
// ram_dp.sv  --  Parameterized dual-port synchronous RAM
//
// Used for the paper's on-chip buffers (Multiplier Buffer, Multiplicand
// Buffer, Output Buffer, Weight/Activation Buffer).  Vivado infers BRAM.
//
// Port A: read/write, single-cycle read latency.
// Port B: read/write, independent.  Simultaneous same-address R/W is
// undefined (standard BRAM semantics).
// =============================================================================
module ram_dp #(
    parameter DATA_WIDTH = 128,
    parameter DEPTH      = 256,
    parameter ADDR_WIDTH = 8
)(
    input  wire                   clk,
    // Port A
    input  wire                   a_en,
    input  wire                   a_we,
    input  wire [ADDR_WIDTH-1:0]  a_addr,
    input  wire [DATA_WIDTH-1:0]  a_din,
    output reg  [DATA_WIDTH-1:0]  a_dout,
    // Port B
    input  wire                   b_en,
    input  wire                   b_we,
    input  wire [ADDR_WIDTH-1:0]  b_addr,
    input  wire [DATA_WIDTH-1:0]  b_din,
    output reg  [DATA_WIDTH-1:0]  b_dout
);

    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always @(posedge clk) begin
        if (a_en) begin
            if (a_we) mem[a_addr] <= a_din;
            a_dout <= mem[a_addr];
        end
    end
    always @(posedge clk) begin
        if (b_en) begin
            if (b_we) mem[b_addr] <= b_din;
            b_dout <= mem[b_addr];
        end
    end

endmodule
