`timescale 1ns / 1ps
// =============================================================================
// softmax_16  --  16-input log-softmax (DEPRECATED; use softmax_from_exp_16)
// =============================================================================
//
// NOTE: systolic_16x16_softmax now uses softmax_from_exp_16 (which takes
//       pre-computed exp values and avoids redundant exp evaluation).
//       This file is retained for backward-compatibility testbenches.
//
// CORNER-CASE FIX [M1]: saturate diff = log_ei - log_sum before taking
//   lower 8 bits, preventing silent wrap if log_sum goes outside the
//   expected [-127..127] relative range.
// =============================================================================
module softmax_16 (
    input  wire [127:0] psum_in,
    output wire [127:0] lsm_out,
    output wire [127:0] e_dbg,
    output wire [11:0]  es_dbg
);

    wire [7:0] e [0:15];
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : GEN_EXP
            expcalc_v2 u_exp (
                .psum     (psum_in[i*8 +: 8]),
                .psum_exp (e[i])
            );
            assign e_dbg[i*8 +: 8] = e[i];
        end
    endgenerate

    wire [11:0] partial [0:15];
    generate
        for (i = 0; i < 16; i = i + 1) begin : GEN_ACC
            if (i == 0)
                assign partial[0] = {4'b0, e[0]};
            else
                assign partial[i] = partial[i-1] + {4'b0, e[i]};
        end
    endgenerate

    wire [11:0] es = partial[15];
    assign es_dbg = es;

    wire [15:0] log_sum;
    logcalc_wide_v2 u_logsum (
        .x     ({8'b0, es}),
        .log_x (log_sum)
    );

    generate
        for (i = 0; i < 16; i = i + 1) begin : GEN_LOG
            wire [7:0]         log_ei;
            wire signed [16:0] diff_s;

            logcalc_v2 u_log (
                .x     ({2'b00, e[i]}),
                .log_x (log_ei)
            );

            // [M1 FIX] saturate
            assign diff_s = $signed({1'b0, 8'b0, log_ei}) -
                            $signed({1'b0, log_sum});
            assign lsm_out[i*8 +: 8] =
                   (diff_s >  17'sd127)  ? 8'sh7F :
                   (diff_s < -17'sd128)  ? 8'sh80 :
                                           diff_s[7:0];
        end
    endgenerate

endmodule
