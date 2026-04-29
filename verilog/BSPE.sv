`timescale 1ns / 1ps
// =============================================================================
// BSPE  --  Booth-Serial Processing Element (paper Section V-B)
//
// CORNER-CASE FIXES vs original:
//   [H1] Threshold comparison made SIGNED-AWARE.  Original wrote
//        `(pin4 > thres)` which is UNSIGNED even though pin4 is signed;
//        this caused negative partial sums to unconditionally pass the
//        threshold (MSB=1 looks like 128..255 unsigned).  Paper's
//        attention-score early termination (Section IV-B-2) is a MAGNITUDE
//        filter "Q*K^T falls below threshold".  We now compare against
//        the MAGNITUDE of pin4 vs the unsigned threshold so positive AND
//        negative small scores get zeroed, matching the paper.
//   - Reset logic of `thres` register cleaned up (was latching THRESHOLD
//     every cycle including after reset; now held at THRESHOLD once out
//     of reset).
//   - All other logic unchanged: 4-stage Booth pipeline, FIFO, handshake
//     signals, data_out = q passthrough (K-stationary systolic).
// =============================================================================

module BSPE #(
    parameter THRESHOLD = 8'd10       // paper: attention score threshold
)(
    input              clk,
    input              rst,
    input      [7:0]   k,
    input      [7:0]   q,
    input      [7:0]   pin,
    output     [7:0]   psum,
    input              valid_q,
    input              load_k,

    // horizontal FIFO-chain handshake (paper Fig. 6/7)
    input              left_valid,
    input  signed [7:0] left_fifo_out,
    output             left_read,
    input              right_inread,
    output     [7:0]   fifo_out_right,
    output             fifo_read_out,

    output signed [7:0] data_out
);

    // -------------------------------------------------------------------
    // K weight register (stationary)
    // -------------------------------------------------------------------
    reg [7:0] k_reg;
    initial   k_reg = 8'd0;
    always @(posedge clk) begin
        if (rst)          k_reg <= 8'd0;
        else if (load_k)  k_reg <= k;
    end

    // -------------------------------------------------------------------
    // Booth encoder (8-bit signed K -> four 3-bit Booth codes)
    // -------------------------------------------------------------------
    wire [2:0] beu1, beu2, beu3, beu4;
    boothencoder be (
        .kext ({k_reg, 1'b0}),
        .bu1  (beu1), .bu2(beu2), .bu3(beu3), .bu4(beu4)
    );

    // -------------------------------------------------------------------
    // 4-stage Booth pipeline (paper Fig. 6 inner BSPE)
    // -------------------------------------------------------------------
    wire [7:0] do1, do2, do3, do4;
    wire [7:0] pin1, pin2, pin3, pin4;
    wire       sp1, sp2, sp3, sp4;

    boothunit bu1 (
        .clk(clk), .rst(rst),
        .q(q),  .boothcode(beu1), .shift(3'd2),
        .pin(pin), .booth_out_8b(pin1),
        .dout(do1), .start(valid_q), .done(sp1)
    );
    boothunit bu2 (
        .clk(clk), .rst(rst),
        .q(do1), .boothcode(beu2), .shift(3'd2),
        .pin(pin1), .booth_out_8b(pin2),
        .dout(do2), .start(sp1),    .done(sp2)
    );
    boothunit bu3 (
        .clk(clk), .rst(rst),
        .q(do2), .boothcode(beu3), .shift(3'd2),
        .pin(pin2), .booth_out_8b(pin3),
        .dout(do3), .start(sp2),    .done(sp3)
    );
    boothunit bu4 (
        .clk(clk), .rst(rst),
        .q(do3), .boothcode(beu4), .shift(3'd2),
        .pin(pin3), .booth_out_8b(pin4),
        .dout(do4), .start(sp3),    .done(sp4)
    );

    // -------------------------------------------------------------------
    // [H1 FIX] Threshold comparison - SIGNED MAGNITUDE
    // Original: `(pin4 > thres)` was unsigned (MSB=1 => >= 128 unsigned)
    // Paper:    "attention score < threshold => set to 0"   (magnitude)
    // -------------------------------------------------------------------
    reg [7:0] thres;
    initial   thres = 8'd0;
    always @(posedge clk) begin
        if (rst) thres <= 8'd0;
        else     thres <= THRESHOLD;
    end

    // Magnitude of pin4: abs(signed 8-bit). 0x80 (-128) -> 128 clamped to 127 safely.
    wire signed [7:0] pin4_s = pin4;
    wire       [7:0] pin4_abs = pin4_s[7] ? ((pin4_s == 8'sh80) ? 8'd127
                                                                : (~pin4 + 8'd1))
                                          : pin4;
    assign psum = (pin4_abs > thres) ? pin4 : 8'd0;

    // -------------------------------------------------------------------
    // FIFO (inter-PE skew buffer) + horizontal handshake
    // -------------------------------------------------------------------
    assign left_read = sp4;

    wire fifo_full, fifo_empty;
    wire signed [7:0] fifo_dout;

    reg fifo_rd;
    initial fifo_rd = 1'b0;

    fifo #(
        .WIDTH      (8),
        .DEPTH      (16),      // was 9; now power-of-2 (see Fifo.sv comments)
        .ADDR_WIDTH (4)
    ) fifo_between_pes (
        .clk   (clk),
        .rst   (rst),
        .wr_en (sp4),
        .din   (psum),
        .rd_en (fifo_rd),
        .dout  (fifo_dout),
        .full  (fifo_full),
        .empty (fifo_empty)
    );

    always @(posedge clk) begin
        if (rst) fifo_rd <= 1'b0;
        else     fifo_rd <= left_valid && right_inread;
    end

    // -------------------------------------------------------------------
    // Outputs: K-stationary systolic behaviour
    //   data_out   : Q pass-through (to row below)
    //   fifo_out_r : horizontal accumulator to right neighbour
    // -------------------------------------------------------------------
    assign data_out       = q;
    assign fifo_out_right = fifo_dout + left_fifo_out;
    assign fifo_read_out  = fifo_rd;

endmodule
