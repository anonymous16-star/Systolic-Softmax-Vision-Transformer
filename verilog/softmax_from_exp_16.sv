`timescale 1ns / 1ps


module softmax_from_exp_16 (
    input  wire [127:0] e_in,
    output wire [127:0] sm_out,
    output wire [127:0] lsm_out,
    output wire [11:0]  es_sum
);

    
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

    
    generate
        for (i = 0; i < 16; i = i + 1) begin : GEN_SM
            wire [14:0] numer     = {e_in[i*8 +: 8], 7'b0};
            wire [14:0] numer_rnd = numer + {3'b0, es_safe[11:1]};
            wire [14:0] quot      = numer_rnd / {3'b0, es_safe};
            assign sm_out[i*8 +: 8] = (quot > 15'd255) ? 8'd255 : quot[7:0];
        end
    endgenerate

    wire [15:0] log_sum;
    logcalc_wide_v2 u_logsum (
        .x     ({8'b0, es}),
        .log_x (log_sum)
    );

    generate
        for (i = 0; i < 16; i = i + 1) begin : GEN_LOG
            wire [7:0]   log_ei;
            wire signed [16:0] diff_s;   

            logcalc_v2 u_log (
                .x     ({2'b00, e_in[i*8 +: 8]}),
                .log_x (log_ei)
            );

            assign diff_s = $signed({1'b0, 8'b0, log_ei}) -
                            $signed({1'b0, log_sum});

            assign lsm_out[i*8 +: 8] =
                   (diff_s >  17'sd127)  ? 8'sh7F :
                   (diff_s < -17'sd128)  ? 8'sh80 :
                                           diff_s[7:0];
        end
    endgenerate

endmodule
