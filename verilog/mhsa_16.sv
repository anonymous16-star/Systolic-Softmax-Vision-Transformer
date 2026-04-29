`timescale 1ns / 1ps


module mhsa_16 #(
    parameter BOOTH_LSB_SCALE = 1,
    parameter THRESHOLD       = 10
)(
    input  wire         clk,
    input  wire         rst,

    input  wire [2047:0] q_flat,    
    input  wire [2047:0] k_flat,    

    input  wire          start,      

    
    output reg  [127:0]  attn_out,   
    output reg  [127:0]  lsm_out,    
    output reg  [127:0]  exp_out,    
    output reg  [11:0]   es_out,     
    output reg           attn_valid
);

    
    
    
    localparam S_IDLE      = 3'd0;
    localparam S_LOAD_K    = 3'd1;
    localparam S_STREAM_Q  = 3'd2;
    localparam S_WAIT_DONE = 3'd3;
    localparam S_DONE      = 3'd4;

    reg [2:0]  state;
    reg [4:0]  col_cnt;
    reg [5:0]  wait_cnt;

    reg [127:0] k_col_packed;
    integer ri;
    always @(*) begin
        k_col_packed = 128'd0;
        for (ri = 0; ri < 16; ri = ri + 1)
            k_col_packed[ri*8 +: 8] = k_flat[ri*128 + col_cnt*8 +: 8];
    end

    
    reg [7:0] q_vec [0:15];
    always @(*) begin
        for (ri = 0; ri < 16; ri = ri + 1)
            q_vec[ri] = q_flat[col_cnt*128 + ri*8 +: 8];
    end

    reg        load_k_en_r;
    reg [3:0]  load_k_col_r;
    reg        valid_q_r;

    wire [127:0] sm_w;
    wire [127:0] lsm_w;
    wire [127:0] exp_w;
    wire [11:0]  es_w;
    wire         attn_valid_w;

    attention_head #(
        .BOOTH_LSB_SCALE (BOOTH_LSB_SCALE),
        .THRESHOLD       (THRESHOLD)
    ) u_attn (
        .clk            (clk),
        .rst            (rst),
        .load_k_en      (load_k_en_r),
        .load_k_col     (load_k_col_r),
        .k_in_packed    (k_col_packed),
        .q0  (q_vec[0]),  .q1  (q_vec[1]),  .q2  (q_vec[2]),  .q3  (q_vec[3]),
        .q4  (q_vec[4]),  .q5  (q_vec[5]),  .q6  (q_vec[6]),  .q7  (q_vec[7]),
        .q8  (q_vec[8]),  .q9  (q_vec[9]),  .q10 (q_vec[10]), .q11 (q_vec[11]),
        .q12 (q_vec[12]), .q13 (q_vec[13]), .q14 (q_vec[14]), .q15 (q_vec[15]),
        .valid_q        (valid_q_r),
        .sm_out         (sm_w),
        .lsm_out        (lsm_w),
        .exp_dbg        (exp_w),
        .es_dbg         (es_w),
        .attn_valid     (attn_valid_w)
    );
    always @(posedge clk) begin
        if (rst) begin
            state        <= S_IDLE;
            col_cnt      <= 5'd0;
            wait_cnt     <= 6'd0;
            load_k_en_r  <= 1'b0;
            load_k_col_r <= 4'd0;
            valid_q_r    <= 1'b0;
            attn_valid   <= 1'b0;
            attn_out     <= 128'd0;
            lsm_out      <= 128'd0;
            exp_out      <= 128'd0;
            es_out       <= 12'd0;
        end else begin
            load_k_en_r <= 1'b0;
            valid_q_r   <= 1'b0;
            attn_valid  <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        state   <= S_LOAD_K;
                        col_cnt <= 5'd0;
                    end
                end

                S_LOAD_K: begin
                    load_k_en_r  <= 1'b1;
                    load_k_col_r <= col_cnt[3:0];
                    if (col_cnt == 5'd15) begin
                        state   <= S_STREAM_Q;
                        col_cnt <= 5'd0;
                    end else begin
                        col_cnt <= col_cnt + 5'd1;
                    end
                end

                S_STREAM_Q: begin
                    valid_q_r <= 1'b1;
                    if (col_cnt == 5'd15) begin
                        state    <= S_WAIT_DONE;
                        wait_cnt <= 6'd0;
                        col_cnt  <= 5'd0;
                    end else begin
                        col_cnt <= col_cnt + 5'd1;
                    end
                end

                S_WAIT_DONE: begin
                    wait_cnt <= wait_cnt + 6'd1;
                    if (attn_valid_w) begin
                        attn_out   <= sm_w;
                        lsm_out    <= lsm_w;
                        exp_out    <= exp_w;
                        es_out     <= es_w;
                        attn_valid <= 1'b1;
                        state      <= S_DONE;
                    end else if (wait_cnt >= 6'd63) begin
                        state <= S_DONE;                  
                    end
                end

                S_DONE: begin
                    attn_valid <= 1'b0;
                    state      <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
