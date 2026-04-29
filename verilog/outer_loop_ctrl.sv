`timescale 1ns / 1ps

module outer_loop_ctrl #(
    parameter N_TILES_W  = 5,    
    parameter D_TILES_W  = 5,    
    parameter H_HEADS_W  = 4,    
    parameter L_LAYERS_W = 4     
)(
    input  wire                    clk,
    input  wire                    rst,

    input  wire                    start,
    input  wire [N_TILES_W-1:0]    cfg_n_tiles,     
    input  wire [D_TILES_W-1:0]    cfg_d_tiles,     
    input  wire [H_HEADS_W-1:0]    cfg_h_heads,     
    input  wire [L_LAYERS_W-1:0]   cfg_l_layers,    

    
    output reg                     inner_start,
    input  wire                    inner_done,

    
    output reg                     pf_start,
    input  wire                    pf_done,
    output reg  [1:0]              pf_bank,         

    
    output reg  [1:0]              active_bank,

    
    output reg  [N_TILES_W-1:0]    cur_n,
    output reg  [D_TILES_W-1:0]    cur_d,
    output reg  [H_HEADS_W-1:0]    cur_h,
    output reg  [L_LAYERS_W-1:0]   cur_l,

    
    output reg  [31:0]             total_tiles_fired,
    output reg                     all_done
);

    localparam S_IDLE   = 3'd0;
    localparam S_PF     = 3'd1;    
    localparam S_FIRE   = 3'd2;   
    localparam S_WAIT   = 3'd3;    
    localparam S_ADV    = 3'd4;    
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
          
                    if (pf_done) begin
                        state       <= S_FIRE;
                    end
                end

                S_FIRE: begin
                    inner_start <= 1'b1;
                    
                    
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
