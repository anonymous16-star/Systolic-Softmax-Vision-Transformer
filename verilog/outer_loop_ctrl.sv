`timescale 1ns / 1ps
// =============================================================================
// outer_loop_ctrl.sv  --  Multi-tile outer-loop controller for full-DeiT
//
// Wraps the inner `boostvit_controller` (single-tile) with multi-tile
// iteration: for (N_tile, D_tile, Head) triple, triggers the inner
// controller, waits for its `done`, advances tile pointers, and repeats.
//
// Also manages a double-buffered weight staging:  while the inner is
// computing tile (n, d, h), a parallel AXI-burst loader is staging weights
// for (n, d+1, h) into the back-half of the weight buffer.
//
// Parameters:
//   N_TILES  = ceil(N / 16)       (13 for DeiT-Tiny N=196)
//   D_TILES  = ceil(D / 16)       (12 for DeiT-Tiny D=192)
//   H_HEADS  = H                  (3 for DeiT-Tiny)
//   L_LAYERS = L                  (12 for DeiT)
//
// The max total iterations = L * N_TILES * D_TILES * H_HEADS.  The outer
// loop terminates when all iterations complete.
// =============================================================================

module outer_loop_ctrl #(
    parameter N_TILES_W  = 5,    // bit width for N tile counter (up to 32)
    parameter D_TILES_W  = 5,    // up to 32
    parameter H_HEADS_W  = 4,    // up to 16
    parameter L_LAYERS_W = 4     // up to 16
)(
    input  wire                    clk,
    input  wire                    rst,

    input  wire                    start,
    input  wire [N_TILES_W-1:0]    cfg_n_tiles,     // # token tiles - 1
    input  wire [D_TILES_W-1:0]    cfg_d_tiles,     // # dim tiles   - 1
    input  wire [H_HEADS_W-1:0]    cfg_h_heads,     // # heads       - 1
    input  wire [L_LAYERS_W-1:0]   cfg_l_layers,    // # layers      - 1

    // ---- Inner controller handshake ----
    output reg                     inner_start,
    input  wire                    inner_done,

    // ---- Weight prefetch handshake (to axi_burst_if) ----
    output reg                     pf_start,
    input  wire                    pf_done,
    output reg  [1:0]              pf_bank,         // double-buffer bank select

    // ---- Active bank select for inner ----
    output reg  [1:0]              active_bank,

    // ---- Current tile indices (for debug / trace) ----
    output reg  [N_TILES_W-1:0]    cur_n,
    output reg  [D_TILES_W-1:0]    cur_d,
    output reg  [H_HEADS_W-1:0]    cur_h,
    output reg  [L_LAYERS_W-1:0]   cur_l,

    // ---- Progress counters ----
    output reg  [31:0]             total_tiles_fired,
    output reg                     all_done
);

    localparam S_IDLE   = 3'd0;
    localparam S_PF     = 3'd1;    // prefetch weights for (0,0)
    localparam S_FIRE   = 3'd2;    // fire inner controller
    localparam S_WAIT   = 3'd3;    // wait for inner done
    localparam S_ADV    = 3'd4;    // advance tile pointers + overlap prefetch next
    localparam S_FIN    = 3'd5;

    reg [2:0] state;
    reg       last_tile;

    always @(posedge clk) begin
        if (rst) begin
            state              <= S_IDLE;
            inner_start        <= 1'b0;
            pf_start           <= 1'b0;
            pf_bank            <= 2'd0;
            active_bank        <= 2'd0;
            cur_n              <= 0;
            cur_d              <= 0;
            cur_h              <= 0;
            cur_l              <= 0;
            total_tiles_fired  <= 32'd0;
            all_done           <= 1'b0;
            last_tile          <= 1'b0;
        end else begin
            inner_start <= 1'b0;
            pf_start    <= 1'b0;

            case (state)
                S_IDLE: begin
                    // Keep all_done high once asserted, until start re-pulses
                    if (start) begin
                        all_done <= 1'b0;
                        cur_n <= 0; cur_d <= 0; cur_h <= 0; cur_l <= 0;
                        total_tiles_fired <= 0;
                        pf_start <= 1'b1;
                        pf_bank  <= 2'd0;
                        active_bank <= 2'd0;
                        state    <= S_PF;
                    end
                end

                S_PF: begin
                    // Wait for first prefetch to complete before firing
                    if (pf_done) begin
                        state       <= S_FIRE;
                    end
                end

                S_FIRE: begin
                    inner_start <= 1'b1;
                    // Simultaneously kick off prefetch of next tile into the
                    // OTHER bank (double-buffer)
                    pf_start <= 1'b1;
                    pf_bank  <= ~pf_bank;
                    total_tiles_fired <= total_tiles_fired + 1;
                    state    <= S_WAIT;
                end

                S_WAIT: begin
                    if (inner_done) begin
                        active_bank <= ~active_bank;
                        state       <= S_ADV;
                    end
                end

                S_ADV: begin
                    // Advance the innermost pointer (D), then N, then H, then L
                    if (cur_d < cfg_d_tiles) begin
                        cur_d <= cur_d + 1;
                        state <= S_FIRE;
                    end else begin
                        cur_d <= 0;
                        if (cur_n < cfg_n_tiles) begin
                            cur_n <= cur_n + 1;
                            state <= S_FIRE;
                        end else begin
                            cur_n <= 0;
                            if (cur_h < cfg_h_heads) begin
                                cur_h <= cur_h + 1;
                                state <= S_FIRE;
                            end else begin
                                cur_h <= 0;
                                if (cur_l < cfg_l_layers) begin
                                    cur_l <= cur_l + 1;
                                    state <= S_FIRE;
                                end else begin
                                    state <= S_FIN;
                                end
                            end
                        end
                    end
                end

                S_FIN: begin
                    all_done <= 1'b1;
                    state    <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
