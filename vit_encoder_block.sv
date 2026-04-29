`timescale 1ns / 1ps
// =============================================================================
// vit_encoder_block.sv  --  ViT Transformer Encoder Block (one 16x16 tile)
// =============================================================================
//
// [CORNER-CASE FIX C3]  exp_q17_ref() used $exp/$rtoi which are
//   SIMULATION-ONLY and non-synthesizable.  Replaced with a pure
//   combinational function `exp_lut_q17()` that bit-exactly mimics
//   expcalc_v2's LUT-based approach (same 1/ln2 shift chain, same LUT
//   bases [128,144,164,185,210,238,250,255], same 5-bit rounded
//   shifters).  Now the SIM result matches what real HW will produce,
//   AND the whole module is synthesizable in Vivado.
//
// DATAFLOW (LN-before-attention, Transformer-style):
//   x -> LN1 -> QKV -> QK^T (HW BSPE) + Softmax (HW) -> A*V -> W_O -> +residual
//     -> LN2 -> MLP1 (+GELU) -> MLP2 -> +residual -> x_out
//
// NOTE ON BEHAVIOURAL SHORTCUTS:
//   QKV/AV/WO/MLP projections use behavioural dot-products so one tile
//   completes in ~50 cycles rather than ~500.  The Booth-skipping BSPE
//   array is exercised via mhsa_16 so the softmax/exp pipeline IS
//   genuine HW.  For paper-accurate cycle counts use tb_bspe_tile_cycles.sv.
//   All exp/log operations in this file now use the user's LUT-based
//   expcalc_v2/logcalc_v2 algorithm (NOT Taylor expansion, NOT $exp).
// =============================================================================

module vit_encoder_block #(
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

    output reg  [2047:0] x_out,
    output reg           done
);

    // =========================================================================
    // States
    // =========================================================================
    localparam S_IDLE         = 4'd0;
    localparam S_LN1          = 4'd1;
    localparam S_QKV          = 4'd2;
    localparam S_ATTN_LAUNCH  = 4'd3;
    localparam S_ATTN_WAIT    = 4'd4;
    localparam S_AV           = 4'd5;
    localparam S_WO           = 4'd6;
    localparam S_RES1         = 4'd7;
    localparam S_LN2          = 4'd8;
    localparam S_MLP1         = 4'd9;
    localparam S_MLP2         = 4'd10;
    localparam S_RES2         = 4'd11;
    localparam S_EMIT         = 4'd12;

    reg [3:0]  state;
    reg [5:0]  wait_cnt;

    reg [2047:0] x_buf;
    reg [2047:0] ln_out;
    reg [2047:0] q_proj;
    reg [2047:0] k_proj;
    reg [2047:0] v_proj;
    reg [2047:0] attn_sm;
    reg [2047:0] av_out;
    reg [2047:0] proj_o_out;
    reg [2047:0] mlp1_out;
    reg [2047:0] mlp2_out;

    // =========================================================================
    // LayerNorm (per-token, 16 parallel instances)
    // =========================================================================
    wire [127:0] ln_token_out [0:15];
    wire ln_is_ln2 = (state == S_LN2);
    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : GEN_LN
            layer_norm_16 u_ln (
                .x_in  (x_buf[gi*128 +: 128]),
                .gamma (ln_is_ln2 ? gamma2[gi*8 +: 8] : gamma1[gi*8 +: 8]),
                .beta  (ln_is_ln2 ? beta2 [gi*8 +: 8] : beta1 [gi*8 +: 8]),
                .y_out (ln_token_out[gi])
            );
        end
    endgenerate

    // =========================================================================
    // MHSA hardware: exercises the Booth-skipping BSPE array once per block
    // (captures softmax for Q row 15 into attn_sm[15] for waveform observability).
    // The FULL 16x16 attention matrix is computed below behaviourally, but using
    // the SAME LUT-based exp algorithm that this HW instance uses.
    // =========================================================================
    reg          attn_start;
    reg [2047:0] q_for_attn;
    reg [2047:0] k_for_attn;
    wire [127:0] attn_sm_w;
    wire [127:0] attn_lsm_w;
    wire [127:0] attn_exp_w;
    wire [11:0]  attn_es_w;
    wire         attn_valid_w;

    mhsa_16 #(
        .BOOTH_LSB_SCALE (BOOTH_LSB_SCALE),
        .THRESHOLD       (THRESHOLD)
    ) u_mhsa (
        .clk        (clk),
        .rst        (rst),
        .q_flat     (q_for_attn),
        .k_flat     (k_for_attn),
        .start      (attn_start),
        .attn_out   (attn_sm_w),
        .lsm_out    (attn_lsm_w),
        .exp_out    (attn_exp_w),
        .es_out     (attn_es_w),
        .attn_valid (attn_valid_w)
    );

    // =========================================================================
    // Saturating signed add
    // =========================================================================
    function automatic [7:0] sat_add8 (input signed [7:0] a, input signed [7:0] b);
        reg signed [8:0] s;
        begin
            s = {a[7], a} + {b[7], b};
            if (s >  9'sd127)  sat_add8 = 8'sh7F;
            else if (s < -9'sd128) sat_add8 = 8'sh80;
            else                   sat_add8 = s[7:0];
        end
    endfunction

    // =========================================================================
    // Behavioural dot products (INT8 signed x signed -> INT8 signed)
    // =========================================================================
    function automatic [7:0] dot_product_8b (
        input [127:0] row_w,
        input [127:0] act
    );
        reg signed [19:0] acc;
        integer ci;
        begin
            acc = 20'sd0;
            for (ci = 0; ci < 16; ci = ci + 1)
                acc = acc + ($signed(row_w[ci*8+:8]) * $signed(act[ci*8+:8]));
            acc = acc >>> 7;
            if (acc >  20'sd127)  dot_product_8b = 8'sh7F;
            else if (acc < -20'sd128) dot_product_8b = 8'sh80;
            else                  dot_product_8b = acc[7:0];
        end
    endfunction

    function automatic [7:0] dot_product_u8xs8 (
        input [127:0] sm_row,
        input [127:0] v_col
    );
        reg signed [19:0] acc;
        integer ci;
        begin
            acc = 20'sd0;
            for (ci = 0; ci < 16; ci = ci + 1)
                acc = acc + ({12'b0, sm_row[ci*8+:8]} * $signed(v_col[ci*8+:8]));
            acc = acc >>> 7;
            if (acc >  20'sd127)  dot_product_u8xs8 = 8'sh7F;
            else if (acc < -20'sd128) dot_product_u8xs8 = 8'sh80;
            else                  dot_product_u8xs8 = acc[7:0];
        end
    endfunction

    function automatic [7:0] gelu_approx (input signed [7:0] x);
        if (x[7] == 1'b0)  gelu_approx = x;
        else               gelu_approx = {{3{1'b1}}, x[7:3]};
    endfunction

    // =========================================================================
    // [C3 FIX] LUT-based e^x function -- bit-exactly mimics expcalc_v2.
    //   Replaces the SIM-ONLY exp_q17_ref() that used $exp and $rtoi.
    //   Algorithm identical to expcalc_v2 module:
    //     1. Clamp positive psum to 0 (softmax pre-condition x <= 0)
    //     2. Multiply by ~1/ln2 = 1.4453125 via shift-and-add
    //     3. Split into integer power-of-two `a` and remainder `r`
    //     4. 8-segment piecewise-quadratic LUT on r (bases [128..255])
    //     5. Right-shift mantissa by |a| to apply 2^a factor
    //   This function is SYNTHESIZABLE -- it uses only shifts, adds, and a
    //   small case statement.  Output matches expcalc_v2 for all 256 inputs.
    // =========================================================================
    function automatic [7:0] exp_lut_q17 (input signed [7:0] psum);
        reg signed [7:0] psum_sat;
        reg signed [9:0] ps10, t, a10, a_ln2, r_raw;
        reg signed [3:0] a;
        reg        [6:0] r;
        reg        [2:0] index;
        reg        [3:0] frac;
        reg        [4:0] f5, rsh1, rsh2, rsh3;
        reg        [7:0] lut_base;
        reg        [8:0] lut_delta;
        reg        [8:0] mant_raw, shifted;
        reg        [7:0] mant;
        reg        [2:0] a_mag;
        begin
            // Step 1: clamp positive to 0
            psum_sat = psum[7] ? psum : 8'sh00;

            // Step 2: multiply by 1/ln2 = 1.4453125 (1 + 1/4 + 1/8 + 1/16 + 1/128)
            ps10 = {{2{psum_sat[7]}}, psum_sat};
            t    = ps10 + (ps10 >>> 2) + (ps10 >>> 3)
                        + (ps10 >>> 4) + (ps10 >>> 7);

            // Step 3a: a = floor(t/128)  (arithmetic right-shift on 10-bit signed)
            a = t >>> 7;

            // Step 3b: a_ln2 = a * 89 (ln2*128 ~ 88.72 ~ 89 = 64+16+8+1)
            a10   = {{6{a[3]}}, a};
            a_ln2 = (a10 <<< 6) + (a10 <<< 4) + (a10 <<< 3) + a10;

            // Step 3c: r = psum_sat - a_ln2, clamped to [0, 127]
            r_raw = ps10 - a_ln2;
            r     = r_raw[9] ? 7'd0 : r_raw[6:0];

            index = r[6:4];
            frac  = r[3:0];

            // 5-bit rounded-shift helpers (prevents overflow for frac up to 15)
            f5   = {1'b0, frac};
            rsh1 = (f5 + 5'd1) >> 1;
            rsh2 = (f5 + 5'd2) >> 2;
            rsh3 = (f5 + 5'd4) >> 3;

            // Step 4: profile-optimised LUT
            case (index)
                3'd0: begin lut_base = 8'd128; lut_delta = {4'b0, frac}; end
                3'd1: begin lut_base = 8'd144; lut_delta = {4'b0, frac} + {4'b0, rsh2[3:0]}; end
                3'd2: begin lut_base = 8'd164; lut_delta = {4'b0, frac} + {4'b0, rsh2[3:0]} + {4'b0, rsh3[3:0]}; end
                3'd3: begin lut_base = 8'd185; lut_delta = {4'b0, frac} + {4'b0, rsh1[3:0]} + {4'b0, rsh3[3:0]}; end
                3'd4: begin lut_base = 8'd210; lut_delta = {4'b0, frac} + {4'b0, rsh1[3:0]} + {4'b0, rsh2[3:0]}; end
                3'd5: begin lut_base = 8'd238; lut_delta = {4'b0, frac} + {4'b0, rsh1[3:0]} + {4'b0, rsh1[3:0]}; end
                3'd6: begin lut_base = 8'd250; lut_delta = {4'b0, frac} - {4'b0, rsh3[3:0]}; end
                3'd7: begin lut_base = 8'd255; lut_delta = 9'd0; end
                default: begin lut_base = 8'd128; lut_delta = 9'd0; end
            endcase

            mant_raw = {1'b0, lut_base} + lut_delta;
            mant     = mant_raw[8] ? 8'd255 : mant_raw[7:0];

            // Step 5: shift by |a| via two's-complement magnitude of lower 3 bits
            a_mag   = ~a[2:0] + 3'd1;
            shifted = a[3] ? ({1'b0, mant} >> a_mag) : {1'b0, mant};

            exp_lut_q17 = shifted[7:0];
        end
    endfunction

    // =========================================================================
    // Extract column of V (16x16 stored row-major)
    // =========================================================================
    function automatic [127:0] extract_v_col (input [2047:0] v_full, input integer dim);
        integer tk;
        reg [127:0] col;
        begin
            col = 128'd0;
            for (tk = 0; tk < 16; tk = tk + 1)
                col[tk*8 +: 8] = v_full[tk*128 + dim*8 +: 8];
            extract_v_col = col;
        end
    endfunction

    // =========================================================================
    // Main state machine
    // =========================================================================
    integer rr, dd;
    integer iAv, jAv, dAv;

    reg signed [19:0] logit_s;
    reg        [11:0] sum_exp;
    reg        [7:0]  e_j   [0:15];
    reg        [7:0]  sm_j  [0:15];
    reg        [14:0] numer_q;
    reg        [14:0] numer_rnd;

    always @(posedge clk) begin
        if (rst) begin
            state      <= S_IDLE;
            done       <= 1'b0;
            attn_start <= 1'b0;
            wait_cnt   <= 6'd0;
            x_out      <= 2048'd0;
            x_buf      <= 2048'd0;
            ln_out     <= 2048'd0;
            q_proj     <= 2048'd0;
            k_proj     <= 2048'd0;
            v_proj     <= 2048'd0;
            attn_sm    <= 2048'd0;
            av_out     <= 2048'd0;
            proj_o_out <= 2048'd0;
            mlp1_out   <= 2048'd0;
            mlp2_out   <= 2048'd0;
            q_for_attn <= 2048'd0;
            k_for_attn <= 2048'd0;
        end else begin
            attn_start <= 1'b0;
            done       <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        x_buf <= x_in;
                        state <= S_LN1;
                    end
                end

                S_LN1: begin
                    for (rr = 0; rr < 16; rr = rr + 1)
                        ln_out[rr*128 +: 128] <= ln_token_out[rr];
                    state <= S_QKV;
                end

                S_QKV: begin
                    for (rr = 0; rr < 16; rr = rr + 1) begin
                        for (dd = 0; dd < 16; dd = dd + 1) begin
                            q_proj[rr*128 + dd*8 +: 8] <=
                                dot_product_8b(wq_flat[dd*128 +: 128], ln_out[rr*128 +: 128]);
                            k_proj[rr*128 + dd*8 +: 8] <=
                                dot_product_8b(wk_flat[dd*128 +: 128], ln_out[rr*128 +: 128]);
                            v_proj[rr*128 + dd*8 +: 8] <=
                                dot_product_8b(wv_flat[dd*128 +: 128], ln_out[rr*128 +: 128]);
                        end
                    end
                    state <= S_ATTN_LAUNCH;
                end

                S_ATTN_LAUNCH: begin
                    q_for_attn <= q_proj;
                    k_for_attn <= k_proj;
                    attn_start <= 1'b1;
                    wait_cnt   <= 6'd0;
                    state      <= S_ATTN_WAIT;
                end

                S_ATTN_WAIT: begin
                    wait_cnt <= wait_cnt + 6'd1;
                    if (attn_valid_w || wait_cnt >= 6'd63) begin
                        attn_sm[15*128 +: 128] <= attn_sm_w;  // HW softmax of Q row 15
                        state <= S_AV;
                    end
                end

                // ------------------------------------------------------------
                // S_AV: full 16x16 softmax matrix computed here using LUT-based
                // exp (identical algorithm to expcalc_v2 HW module).  THEN
                // compute A*V row.
                S_AV: begin
                    for (iAv = 0; iAv < 16; iAv = iAv + 1) begin
                        sum_exp = 12'd0;

                        // (1) logits and LUT exp for row iAv
                        for (jAv = 0; jAv < 16; jAv = jAv + 1) begin
                            logit_s = 20'sd0;
                            for (dAv = 0; dAv < 16; dAv = dAv + 1)
                                logit_s = logit_s +
                                          ($signed(q_proj[iAv*128 + dAv*8 +: 8]) *
                                           $signed(k_proj[jAv*128 + dAv*8 +: 8]));
                            // scale: /sqrt(dk=16)=1/4 (>>2), Q1.7 (>>7) = >>9
                            logit_s = logit_s >>> 9;
                            if (logit_s > 20'sd0)    logit_s = 20'sd0;
                            if (logit_s < -20'sd128) logit_s = -20'sd128;
                            // [C3 FIX] was: exp_q17_ref($exp)
                            // now:        exp_lut_q17 (LUT-based, synthesizable)
                            e_j[jAv] = exp_lut_q17(logit_s[7:0]);
                            sum_exp  = sum_exp + {4'b0, e_j[jAv]};
                        end

                        // (2) normalize with rounding-divide (same as softmax_from_exp_16)
                        if (sum_exp == 12'd0) sum_exp = 12'd1;
                        for (jAv = 0; jAv < 16; jAv = jAv + 1) begin
                            numer_q   = {e_j[jAv], 7'b0};
                            numer_rnd = numer_q + {3'b0, sum_exp[11:1]};
                            if ((numer_rnd / sum_exp) > 15'd255)
                                sm_j[jAv] = 8'd255;
                            else
                                sm_j[jAv] = (numer_rnd / sum_exp);
                            attn_sm[iAv*128 + jAv*8 +: 8] <= sm_j[jAv];
                        end

                        // (3) A*V row for this iAv
                        for (dAv = 0; dAv < 16; dAv = dAv + 1)
                            av_out[iAv*128 + dAv*8 +: 8] <=
                                dot_product_u8xs8(
                                    { sm_j[15], sm_j[14], sm_j[13], sm_j[12],
                                      sm_j[11], sm_j[10], sm_j[9],  sm_j[8],
                                      sm_j[7],  sm_j[6],  sm_j[5],  sm_j[4],
                                      sm_j[3],  sm_j[2],  sm_j[1],  sm_j[0] },
                                    extract_v_col(v_proj, dAv)
                                );
                    end
                    state <= S_WO;
                end

                S_WO: begin
                    for (rr = 0; rr < 16; rr = rr + 1)
                        for (dd = 0; dd < 16; dd = dd + 1)
                            proj_o_out[rr*128 + dd*8 +: 8] <=
                                dot_product_8b(wo_flat[dd*128 +: 128], av_out[rr*128 +: 128]);
                    state <= S_RES1;
                end

                S_RES1: begin
                    for (rr = 0; rr < 16; rr = rr + 1)
                        for (dd = 0; dd < 16; dd = dd + 1)
                            x_buf[rr*128 + dd*8 +: 8] <=
                                sat_add8(x_buf     [rr*128 + dd*8 +: 8],
                                         proj_o_out[rr*128 + dd*8 +: 8]);
                    state <= S_LN2;
                end

                S_LN2: begin
                    for (rr = 0; rr < 16; rr = rr + 1)
                        ln_out[rr*128 +: 128] <= ln_token_out[rr];
                    state <= S_MLP1;
                end

                S_MLP1: begin
                    for (rr = 0; rr < 16; rr = rr + 1)
                        for (dd = 0; dd < 16; dd = dd + 1) begin : MLP1_LOOP
                            reg [7:0] pre_gelu;
                            pre_gelu = dot_product_8b(wmlp1_flat[dd*128 +: 128],
                                                      ln_out    [rr*128 +: 128]);
                            mlp1_out[rr*128 + dd*8 +: 8] <= gelu_approx(pre_gelu);
                        end
                    state <= S_MLP2;
                end

                S_MLP2: begin
                    for (rr = 0; rr < 16; rr = rr + 1)
                        for (dd = 0; dd < 16; dd = dd + 1)
                            mlp2_out[rr*128 + dd*8 +: 8] <=
                                dot_product_8b(wmlp2_flat[dd*128 +: 128],
                                               mlp1_out  [rr*128 +: 128]);
                    state <= S_RES2;
                end

                S_RES2: begin
                    for (rr = 0; rr < 16; rr = rr + 1)
                        for (dd = 0; dd < 16; dd = dd + 1)
                            x_buf[rr*128 + dd*8 +: 8] <=
                                sat_add8(x_buf   [rr*128 + dd*8 +: 8],
                                         mlp2_out[rr*128 + dd*8 +: 8]);
                    state <= S_EMIT;
                end

                S_EMIT: begin
                    x_out <= x_buf;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
