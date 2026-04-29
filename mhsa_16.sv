`timescale 1ns / 1ps
// =============================================================================
// mhsa_16.sv  --  Multi-Head Self-Attention core (1 head, 16 tokens, dk=16)
//
// PURPOSE:
//   Implements one attention head of MHSA using the 16x16 BSPE systolic array.
//   For a ROW i of Q, it computes:
//       logit[i][j]   = Q[i] . K[j]                        (Booth-skipping array)
//       e[i][j]       = exp(logit[i][j])                   (per-row expcalc)
//       sm[i][j]      = e[i][j] / sum_j(e[i][j])           (softmax_from_exp_16)
//
//   The attention output for row i is:
//       attn_out[i][d] = sum_j( sm[i][j] * V[j][d] )
//
//   In this module we only produce sm[i][*] (attention WEIGHTS) for one Q row
//   at a time.  Multiplication by V is a SEPARATE linear projection done by
//   the encoder block (re-using the same BSPE array via linear_proj).
//
// STATE MACHINE:
//   S_IDLE -> S_LOAD_K -> S_STREAM_Q -> S_WAIT_DONE -> S_DONE
//
//   S_LOAD_K   : 16 cycles - load K columns one at a time
//   S_STREAM_Q : 16 cycles - stream Q rows into systolic column inputs
//   S_WAIT_DONE: wait for exp_valid from the systolic array + softmax latency
//   S_DONE    : outputs captured, return to idle
//
// I/O FORMAT:
//   q_flat[token*128 + dim*8 +: 8] = Q[token][dim]  (16 tokens x 16 dims, INT8)
//   k_flat[token*128 + dim*8 +: 8] = K[token][dim]
//   attn_out[r*8 +: 8]             = sm[Q_token][r]   Q1.7 unsigned
//   lsm_out[r*8 +: 8]              = lsm[Q_token][r]  Q3.5 signed (debug)
//
//   Because the array computes all 16 rows of the attention score for ONE Q
//   row at a time, the caller typically time-multiplexes over Q rows to build
//   the full 16x16 attention matrix.
//
// PAPER MAPPING (Section V-A):
//   Paper Fig. 6 shows BSPE array feeding SM. Unit (softmax).  Our new
//   softmax_from_exp_16 eliminates the redundant exp that plagued the old
//   softmax_16.
// =============================================================================

module mhsa_16 #(
    parameter BOOTH_LSB_SCALE = 1,
    parameter THRESHOLD       = 10
)(
    input  wire         clk,
    input  wire         rst,

    input  wire [2047:0] q_flat,    // 16 tokens x 16 dims packed
    input  wire [2047:0] k_flat,    // 16 tokens x 16 dims packed

    input  wire          start,      // pulse to begin computation

    // Outputs: attention weights for LAST streamed Q row (row 15)
    output reg  [127:0]  attn_out,   // Q1.7 unsigned softmax          <-- PRIMARY
    output reg  [127:0]  lsm_out,    // Q3.5 signed log-softmax        <-- DEBUG
    output reg  [127:0]  exp_out,    // Q1.7 unsigned exp              <-- DEBUG
    output reg  [11:0]   es_out,     // sum of exp                     <-- DEBUG
    output reg           attn_valid
);

    // =========================================================================
    // State machine
    // =========================================================================
    localparam S_IDLE      = 3'd0;
    localparam S_LOAD_K    = 3'd1;
    localparam S_STREAM_Q  = 3'd2;
    localparam S_WAIT_DONE = 3'd3;
    localparam S_DONE      = 3'd4;

    reg [2:0]  state;
    reg [4:0]  col_cnt;
    reg [5:0]  wait_cnt;

    // =========================================================================
    // K column packing: during S_LOAD_K, column col_cnt of K goes to all rows.
    // k_col_packed[r*8+:8] = K[r][col_cnt]
    // =========================================================================
    reg [127:0] k_col_packed;
    integer ri;
    always @(*) begin
        k_col_packed = 128'd0;
        for (ri = 0; ri < 16; ri = ri + 1)
            k_col_packed[ri*8 +: 8] = k_flat[ri*128 + col_cnt*8 +: 8];
    end

    // =========================================================================
    // Q row selection: during S_STREAM_Q, stream Q[col_cnt] token as the
    // activation vector. q_vec[d] = Q[col_cnt][d] goes to column d.
    // =========================================================================
    reg [7:0] q_vec [0:15];
    always @(*) begin
        for (ri = 0; ri < 16; ri = ri + 1)
            q_vec[ri] = q_flat[col_cnt*128 + ri*8 +: 8];
    end

    // =========================================================================
    // Control regs for attention_head
    // =========================================================================
    reg        load_k_en_r;
    reg [3:0]  load_k_col_r;
    reg        valid_q_r;

    // =========================================================================
    // attention_head outputs (live wires)
    // =========================================================================
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

    // =========================================================================
    // State machine
    // =========================================================================
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
                        state <= S_DONE;                  // safety timeout
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
