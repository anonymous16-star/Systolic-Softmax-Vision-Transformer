`timescale 1ns / 1ps
// =============================================================================
// softmax_from_exp_16  --  16-input softmax, CONSUMES pre-computed exp values
// =============================================================================
//
// INPUT  : e_in [127:0]   16 x Q1.7 unsigned exp values (from expcalc_v2)
// OUTPUTS:
//   sm_out   [127:0]   16 x Q1.7 unsigned softmax  (PRIMARY, used by MHSA * V)
//   lsm_out  [127:0]   16 x Q3.5 signed log-softmax  (DEBUG / paper style)
//   es_sum   [11:0]    debug: sum of all 16 exps
//
// CORNER-CASE FIXES (vs original):
//   [M2] diff = log_ei - log_sum used to simply take diff[7:0] which can
//        silently wrap if log_sum is huge (e.g. 0 exp edge case).  Now
//        saturates to signed 8-bit range [-128, 127] before packing.
//   [M3] es=0 guard retained (divide-by-zero protection).
//   - Division retained as combinational `/`.  For Vivado this maps to a
//     ripple divider that meets ~500 MHz for 15/12-bit operands, matching
//     the paper's target frequency.  If tighter timing needed, swap to a
//     reciprocal LUT + multiply.
// =============================================================================
module softmax_from_exp_16 (
    input  wire [127:0] e_in,
    output wire [127:0] sm_out,
    output wire [127:0] lsm_out,
    output wire [11:0]  es_sum
);

    // ---------- Stage 1: accumulator tree es = Sum e[i] ----------
    wire [11:0] partial [0:15];
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : GEN_SUM
            if (i == 0)
                assign partial[0] = {4'b0, e_in[7:0]};
            else
                assign partial[i] = partial[i-1] + {4'b0, e_in[i*8 +: 8]};
        end
    endgenerate

    wire [11:0] es      = partial[15];
    wire [11:0] es_safe = (es == 12'd0) ? 12'd1 : es;
    assign es_sum = es;

    // ---------- Stage 2: sm[i] = (e[i]<<7 + es/2) / es  (Q1.7) ----------
    generate
        for (i = 0; i < 16; i = i + 1) begin : GEN_SM
            wire [14:0] numer     = {e_in[i*8 +: 8], 7'b0};
            wire [14:0] numer_rnd = numer + {3'b0, es_safe[11:1]};
            wire [14:0] quot      = numer_rnd / {3'b0, es_safe};
            assign sm_out[i*8 +: 8] = (quot > 15'd255) ? 8'd255 : quot[7:0];
        end
    endgenerate

    // ---------- Stage 3: log-softmax ----------
    wire [15:0] log_sum;
    logcalc_wide_v2 u_logsum (
        .x     ({8'b0, es}),
        .log_x (log_sum)
    );

    generate
        for (i = 0; i < 16; i = i + 1) begin : GEN_LOG
            wire [7:0]   log_ei;
            wire signed [16:0] diff_s;   // wide signed to catch any overflow

            logcalc_v2 u_log (
                .x     ({2'b00, e_in[i*8 +: 8]}),
                .log_x (log_ei)
            );

            // [M2 FIX] saturate diff to signed int8 before assignment
            assign diff_s = $signed({1'b0, 8'b0, log_ei}) -
                            $signed({1'b0, log_sum});

            assign lsm_out[i*8 +: 8] =
                   (diff_s >  17'sd127)  ? 8'sh7F :
                   (diff_s < -17'sd128)  ? 8'sh80 :
                                           diff_s[7:0];
        end
    endgenerate

endmodule
