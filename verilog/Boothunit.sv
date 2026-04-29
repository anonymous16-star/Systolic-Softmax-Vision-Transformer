`timescale 1ns / 1ps
// =============================================================================
// boothunit  --  single Radix-4 Booth pipeline stage
//
// CORNER-CASE FIX [C2] (vs original):
//   - Changed `always @(posedge clk or posedge rst)` (ASYNC reset) to
//     `always @(posedge clk)` with synchronous `if (rst)` pattern.
//     Every other module in this design uses sync reset, so the async
//     reset here created mixed-reset synthesis warnings and could cause
//     timing issues at the reset-domain boundary.  Sync reset is also
//     preferred for Vivado/ASIC flows.
//   - LOGIC UNCHANGED: same skip detection, same stage pipelining, same
//     dout/booth_out_8b/done outputs.
// =============================================================================

module boothunit (
    input               clk,
    input               rst,
    input               start,

    input  signed [7:0] q,
    input        [2:0]  boothcode,
    input  signed [7:0] pin,
    input        [2:0]  shift,
    output signed [7:0] booth_out_8b,
    output signed [7:0] dout,
    output              done
);

    wire signed [8:0] boothmulOut;
    wire              skip;

    reg  signed [7:0] q_reg1;
    reg  signed [7:0] q_reg;
    reg  signed [7:0] stage1;
    reg  signed [7:0] stage2;
    reg               stage1_valid;
    reg               stage2_valid;

    initial begin
        q_reg1       = 8'sd0; q_reg        = 8'sd0;
        stage1       = 8'sd0; stage2       = 8'sd0;
        stage1_valid = 1'b0;  stage2_valid = 1'b0;
    end

    boothmul BM (
        .in1 (boothcode),
        .in2 (q_reg1),
        .out1(boothmulOut)
    );

    assign skip = (boothcode == 3'b000 || boothcode == 3'b111);

    // [FIX C2] Synchronous reset, consistent with rest of design
    always @(posedge clk) begin
        if (rst) begin
            stage1       <= 8'sd0;
            stage2       <= 8'sd0;
            stage1_valid <= 1'b0;
            stage2_valid <= 1'b0;
            q_reg        <= 8'sd0;
            q_reg1       <= 8'sd0;
        end else begin
            stage1_valid <= start && !skip;
            stage2_valid <= stage1_valid;

            if (start && !skip) begin
                stage1 <= pin <<< shift;
                q_reg1 <= q;
            end

            if (stage1_valid) begin
                stage2 <= stage1 + boothmulOut;   // truncation preserved
                q_reg  <= q_reg1;
            end
        end
    end

    assign dout         = skip ? q            : q_reg;
    assign booth_out_8b = skip ? (pin <<< shift) : stage2;
    assign done         = skip ? start        : stage2_valid;

endmodule
