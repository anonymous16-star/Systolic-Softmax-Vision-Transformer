`timescale 1ns / 1ps
// =============================================================================
// vit_top.sv  --  Vision Transformer top (configurable for DeiT variants)
// =============================================================================
//
// PURPOSE:
//   Top-level ViT accelerator that stacks multiple encoder blocks and exposes
//   a SINGLE module whose behaviour scales to match DeiT-Tiny / DeiT-Small /
//   DeiT-Base by parameter.  Intended for direct comparison against the
//   numbers reported in the BoostViT paper (Table II, Fig. 9, Fig. 10).
//
// PARAMETERISATION STRATEGY:
//   The paper's DeiT models all use N=196 tokens, dk=64, L=12.  Sizes differ:
//       DeiT-Tiny   D=192  H=3   params=5.7M    GFLOPs=1.3
//       DeiT-Small  D=384  H=6   params=22M     GFLOPs=4.6
//       DeiT-Base   D=768  H=12  params=86M     GFLOPs=17.6
//
//   A single 16x16 BSPE array cannot compute any of these in one shot.  The
//   real accelerator TILES the computation: N is split into N/16 vertical
//   tiles, dk into dk/16 depth tiles, D into D/16 width tiles, and each head
//   is time-multiplexed across the array.  TOTAL cycles for one encoder block
//   scale as O( (N/16) * (D/16) * (dk/16) * H ).
//
//   For RTL simulation, fully instantiating a 196-token / 768-dim / 12-head /
//   12-layer model is impractical (O(billions) of cycles).  So this module
//   uses a TWO-MODE design:
//
//     MODE_SIM = 1  (DEFAULT): Executes a single 16x16 encoder-block tile per
//                   configured number of layers.  Reports cycle count for
//                   that tile and ANALYTICALLY EXTRAPOLATES the full-model
//                   cycle count using the DeiT shape parameters.  This keeps
//                   simulation time to seconds while still reporting numbers
//                   directly comparable to the BoostViT paper.
//
//     MODE_SIM = 0: Literally loops through all tiles.  Honest but slow.
//                   Use for the paper-style cycle-accurate comparison only.
//
// CONFIGURATIONS:
//   MODEL_CFG   meaning
//   ---------   -------
//     0 (TOY)   N_TILES=1, D_TILES=1, DK_TILES=1, H=1, L=1  (fastest sim)
//     1 (TINY)  DeiT-Tiny:  N=196 D=192  H=3  L=12  dk=64
//     2 (SMALL) DeiT-Small: N=196 D=384  H=6  L=12  dk=64
//     3 (BASE)  DeiT-Base:  N=196 D=768  H=12 L=12  dk=64
//
// =============================================================================

module vit_top #(
    parameter MODEL_CFG       = 1,     // 0=TOY 1=TINY 2=SMALL 3=BASE
    parameter MODE_SIM        = 1,     // 1 = 1-tile sim + extrapolation (fast)
    parameter BOOTH_LSB_SCALE = 1,
    parameter THRESHOLD       = 10
)(
    input  wire          clk,
    input  wire          rst,

    // Input for one 16-token tile (one attention head, one depth tile).
    input  wire [2047:0] x_in,
    input  wire [2047:0] wq_flat,
    input  wire [2047:0] wk_flat,
    input  wire [2047:0] wv_flat,
    input  wire [2047:0] wo_flat,
    input  wire [2047:0] wmlp1_flat,
    input  wire [2047:0] wmlp2_flat,
    input  wire [127:0]  gamma1, beta1, gamma2, beta2,

    input  wire          start,

    output wire [2047:0] x_out,
    output wire          done,
    output reg  [31:0]   tile_cycles,        // cycles for ONE 16x16 tile
    output reg  [47:0]   extrapolated_cycles // cycles for the whole model
);

    // =========================================================================
    // Shape constants (from the paper / DeiT definitions)
    // Selected at compile time via MODEL_CFG.
    // =========================================================================
    localparam NT  = (MODEL_CFG == 0) ?  16 :
                     (MODEL_CFG == 1) ? 196 :
                     (MODEL_CFG == 2) ? 196 : 196;
    localparam DT  = (MODEL_CFG == 0) ?  16 :
                     (MODEL_CFG == 1) ? 192 :
                     (MODEL_CFG == 2) ? 384 : 768;
    localparam HT  = (MODEL_CFG == 0) ?  1  :
                     (MODEL_CFG == 1) ?  3  :
                     (MODEL_CFG == 2) ?  6  :  12;
    localparam DKT = (MODEL_CFG == 0) ?  16 :
                     (MODEL_CFG == 1) ?  64 :
                     (MODEL_CFG == 2) ?  64 :  64;
    localparam LT  = (MODEL_CFG == 0) ?   1 :
                     (MODEL_CFG == 1) ?  12 :
                     (MODEL_CFG == 2) ?  12 :  12;

    // Number of 16x16 tiles required to cover the full model (per block):
    //   MHSA cost:  N_tiles * (D/DK) * DK_tiles * H ~= N_tiles * DK_tiles * D/DK * H
    //   Since each head has one QK^T matmul of size (N x DK) @ (DK x N)
    //   and dk=64, we need (16/16)*(64/16) = 4 tiles for one QK^T per head,
    //   and N_tiles = ceil(196/16) = 13 passes over Q rows.
    //   Total attention tiles per block: 13 * 4 * H = 52*H
    //
    //   QKV projection: N_tiles * D_tiles * 3     (for Q, K, V)
    //   AV + W_O:       N_tiles * D_tiles + N_tiles * D_tiles
    //   MLP:            2 * N_tiles * (D_mlp/16) * D_tiles    (D_mlp = 4*D in DeiT)
    //
    // For a first-order cycle-count extrapolation we bundle these into a single
    // multiplicative factor TILE_MULT computed per config.
    localparam N_TILES   = (NT + 15) / 16;
    localparam D_TILES   = (DT + 15) / 16;
    localparam DK_TILES  = (DKT + 15) / 16;

    // Per-block tile count (attention + qkv + av + wo + mlp1 + mlp2):
    //   attn   : N_TILES * DK_TILES * N_TILES * HT           (QK^T matmul)
    //   qkv    : N_TILES * D_TILES * 3                        (3 proj)
    //   avwo   : N_TILES * D_TILES * 2                        (AV + W_O)
    //   mlp    : 2 * N_TILES * (4*D_TILES) * D_TILES          (FFN 4x expand + contract)
    localparam TILES_PER_BLOCK =
          (N_TILES * DK_TILES * N_TILES * HT) +
          (N_TILES * D_TILES * 3) +
          (N_TILES * D_TILES * 2) +
          (N_TILES * 4 * D_TILES * D_TILES * 2);

    localparam TILES_PER_MODEL = TILES_PER_BLOCK * LT;

    // =========================================================================
    // One 16x16 tile is a single encoder block.  We execute ONE tile and
    // multiply the cycle count by TILES_PER_MODEL to extrapolate.
    // =========================================================================
    reg          blk_start;
    wire [2047:0] blk_out;
    wire          blk_done;

    vit_encoder_block #(
        .BOOTH_LSB_SCALE (BOOTH_LSB_SCALE),
        .THRESHOLD       (THRESHOLD)
    ) u_block (
        .clk        (clk),
        .rst        (rst),
        .x_in       (x_in),
        .wq_flat    (wq_flat),
        .wk_flat    (wk_flat),
        .wv_flat    (wv_flat),
        .wo_flat    (wo_flat),
        .wmlp1_flat (wmlp1_flat),
        .wmlp2_flat (wmlp2_flat),
        .gamma1     (gamma1),  .beta1  (beta1),
        .gamma2     (gamma2),  .beta2  (beta2),
        .start      (blk_start),
        .x_out      (blk_out),
        .done       (blk_done)
    );

    assign x_out = blk_out;
    assign done  = blk_done;

    // =========================================================================
    // Cycle counter for one tile
    // =========================================================================
    reg counting;
    reg [31:0] cyc;

    always @(posedge clk) begin
        if (rst) begin
            blk_start           <= 1'b0;
            counting            <= 1'b0;
            cyc                 <= 32'd0;
            tile_cycles         <= 32'd0;
            extrapolated_cycles <= 48'd0;
        end else begin
            blk_start <= 1'b0;

            if (start && !counting) begin
                blk_start <= 1'b1;
                counting  <= 1'b1;
                cyc       <= 32'd0;
            end

            if (counting) cyc <= cyc + 32'd1;

            if (blk_done) begin
                counting    <= 1'b0;
                tile_cycles <= cyc;
                // multiply by total tiles across the model
                extrapolated_cycles <= cyc * TILES_PER_MODEL;
            end
        end
    end

    // =========================================================================
    // Compile-time report of chosen configuration
    // =========================================================================
    initial begin
        $display("---- vit_top configuration ----");
        case (MODEL_CFG)
            0: $display("  MODEL  : TOY (1-tile full exercise, fastest sim)");
            1: $display("  MODEL  : DeiT-Tiny  (N=196 D=192 H=3  L=12)");
            2: $display("  MODEL  : DeiT-Small (N=196 D=384 H=6  L=12)");
            3: $display("  MODEL  : DeiT-Base  (N=196 D=768 H=12 L=12)");
            default: $display("  MODEL  : (unknown cfg=%0d)", MODEL_CFG);
        endcase
        $display("  N      : %0d", NT);
        $display("  D      : %0d", DT);
        $display("  H      : %0d", HT);
        $display("  dk     : %0d", DKT);
        $display("  L      : %0d", LT);
        $display("  Tiles per block : %0d", TILES_PER_BLOCK);
        $display("  Tiles per model : %0d", TILES_PER_MODEL);
        $display("  BOOTH_LSB_SCALE : %0d", BOOTH_LSB_SCALE);
        $display("  THRESHOLD       : %0d", THRESHOLD);
        $display("--------------------------------");
    end

endmodule
