`timescale 1ns / 1ps

module vit_top #(
    parameter MODEL_CFG       = 1,     
    parameter MODE_SIM        = 1,     
    parameter BOOTH_LSB_SCALE = 1,
    parameter THRESHOLD       = 10
)(
    input  wire          clk,
    input  wire          rst,

    
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
    output reg  [31:0]   tile_cycles,        
    output reg  [47:0]   extrapolated_cycles 
);

    
    
    
    
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

    
    localparam N_TILES   = (NT + 15) / 16;
    localparam D_TILES   = (DT + 15) / 16;
    localparam DK_TILES  = (DKT + 15) / 16;

    localparam TILES_PER_BLOCK =
          (N_TILES * DK_TILES * N_TILES * HT) +
          (N_TILES * D_TILES * 3) +
          (N_TILES * D_TILES * 2) +
          (N_TILES * 4 * D_TILES * D_TILES * 2);

    localparam TILES_PER_MODEL = TILES_PER_BLOCK * LT;

    
    
    
    
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
                extrapolated_cycles <= cyc * TILES_PER_MODEL;
            end
        end
    end

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
