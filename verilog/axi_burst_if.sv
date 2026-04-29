`timescale 1ns / 1ps


module axi_burst_if #(
    parameter FIFO_DEPTH = 16,
    parameter DATA_WIDTH = 128,
    parameter ADDR_WIDTH = 32,
    parameter BURST_LEN_W = 8
)(
    input  wire                   clk,
    input  wire                   rst,

    input  wire                   start_rd,
    input  wire                   start_wr,
    input  wire [ADDR_WIDTH-1:0]  base_addr,
    input  wire [BURST_LEN_W-1:0] burst_len,        
    output reg                    busy,
    output reg                    done,

    
    input  wire                   rd_fifo_pop,
    output wire [DATA_WIDTH-1:0]  rd_fifo_data,
    output wire                   rd_fifo_empty,
    output wire                   rd_fifo_full,

    
    input  wire                   wr_fifo_push,
    input  wire [DATA_WIDTH-1:0]  wr_fifo_data,
    output wire                   wr_fifo_full,
    output wire                   wr_fifo_empty,

    
    output reg                    mem_req,
    output reg                    mem_we,
    output reg  [ADDR_WIDTH-1:0]  mem_addr,
    output reg  [DATA_WIDTH-1:0]  mem_wdata,
    input  wire                   mem_ack,
    input  wire [DATA_WIDTH-1:0]  mem_rdata
);

    reg [DATA_WIDTH-1:0] rd_mem [0:FIFO_DEPTH-1];
    reg [$clog2(FIFO_DEPTH):0]  rd_wr_ptr, rd_rd_ptr;
    wire [$clog2(FIFO_DEPTH):0] rd_cnt = rd_wr_ptr - rd_rd_ptr;
    assign rd_fifo_empty = (rd_cnt == 0);
    assign rd_fifo_full  = (rd_cnt == FIFO_DEPTH);
    assign rd_fifo_data  = rd_mem[rd_rd_ptr[$clog2(FIFO_DEPTH)-1:0]];
 
    reg [DATA_WIDTH-1:0] wr_mem [0:FIFO_DEPTH-1];
    reg [$clog2(FIFO_DEPTH):0]  wr_wr_ptr, wr_rd_ptr;
    wire [$clog2(FIFO_DEPTH):0] wr_cnt = wr_wr_ptr - wr_rd_ptr;
    assign wr_fifo_full  = (wr_cnt == FIFO_DEPTH);
    assign wr_fifo_empty = (wr_cnt == 0);
    wire [DATA_WIDTH-1:0] wr_fifo_head = wr_mem[wr_rd_ptr[$clog2(FIFO_DEPTH)-1:0]];


    localparam S_IDLE = 2'd0;
    localparam S_RD   = 2'd1;
    localparam S_WR   = 2'd2;
    localparam S_FIN  = 2'd3;

    reg [1:0] state;
    reg [BURST_LEN_W-1:0] beat_cnt;
    reg [ADDR_WIDTH-1:0]  cur_addr;

    always @(posedge clk) begin
        if (rst) begin
            state     <= S_IDLE;
            busy      <= 1'b0;
            done      <= 1'b0;
            beat_cnt  <= 0;
            cur_addr  <= 0;
            rd_wr_ptr <= 0;
            rd_rd_ptr <= 0;
            wr_wr_ptr <= 0;
            wr_rd_ptr <= 0;
            mem_req   <= 0;
            mem_we    <= 0;
            mem_addr  <= 0;
            mem_wdata <= 0;
        end else begin
            
            if (rd_fifo_pop && !rd_fifo_empty) rd_rd_ptr <= rd_rd_ptr + 1;
            
            if (wr_fifo_push && !wr_fifo_full) begin
                wr_mem[wr_wr_ptr[$clog2(FIFO_DEPTH)-1:0]] <= wr_fifo_data;
                wr_wr_ptr <= wr_wr_ptr + 1;
            end

            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    busy     <= 1'b0;
                    mem_req  <= 1'b0;
                    if (start_rd) begin
                        state    <= S_RD;
                        busy     <= 1'b1;
                        beat_cnt <= burst_len;
                        cur_addr <= base_addr;
                        mem_req  <= 1'b1;
                        mem_we   <= 1'b0;
                        mem_addr <= base_addr;
                    end else if (start_wr) begin
                        state    <= S_WR;
                        busy     <= 1'b1;
                        beat_cnt <= burst_len;
                        cur_addr <= base_addr;
                    end
                end

                S_RD: begin
                    if (mem_ack && !rd_fifo_full) begin
                        rd_mem[rd_wr_ptr[$clog2(FIFO_DEPTH)-1:0]] <= mem_rdata;
                        rd_wr_ptr <= rd_wr_ptr + 1;
                        if (beat_cnt == 0) begin
                            state   <= S_FIN;
                            mem_req <= 1'b0;
                        end else begin
                            beat_cnt <= beat_cnt - 1;
                            cur_addr <= cur_addr + 16;   
                            mem_addr <= cur_addr + 16;
                            mem_req  <= 1'b1;
                        end
                    end
                end

                S_WR: begin
                    if (!wr_fifo_empty && !mem_req) begin
                        mem_req   <= 1'b1;
                        mem_we    <= 1'b1;
                        mem_addr  <= cur_addr;
                        mem_wdata <= wr_fifo_head;
                    end else if (mem_req && mem_ack) begin
                        wr_rd_ptr <= wr_rd_ptr + 1;
                        mem_req   <= 1'b0;
                        if (beat_cnt == 0) begin
                            state <= S_FIN;
                        end else begin
                            beat_cnt <= beat_cnt - 1;
                            cur_addr <= cur_addr + 16;
                        end
                    end
                end

                S_FIN: begin
                    done    <= 1'b1;
                    busy    <= 1'b0;
                    mem_req <= 1'b0;
                    state   <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
