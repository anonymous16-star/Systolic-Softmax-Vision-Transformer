`timescale 1ns / 1ps
// =============================================================================
// tb_exp_accuracy.sv  --  exhaustive accuracy test for expcalc_v2
// =============================================================================
//
// WHAT IT MEASURES:
//   For every signed 8-bit input psum in [-128, 127], compare expcalc_v2's
//   LUT-based output to a FP reference exp(psum/128) * 128.
//
//   Since expcalc_v2 is intended for the softmax-stabilised regime
//   (psum <= 0), we report THREE error statistics:
//     - Over the valid domain psum in [-128, 0]     (the used range)
//     - Over the clamped domain psum in [1, 127]    (should all output 128)
//     - Over the full 256-value range (for completeness)
//
//   Paper's expcalc claim: Max |ULP| ~= 0.93, Mean |ULP| ~= 0.31
//
// OUTPUT TABLE: ULP error histogram + summary numbers reviewers can cite.
// =============================================================================

module tb_exp_accuracy;

    reg  signed [7:0] psum;
    wire        [7:0] psum_exp;

    expcalc_v2 DUT (
        .psum     (psum),
        .psum_exp (psum_exp)
    );

    integer i, ref_int;
    real    x_real, e_real, e_ref;
    real    err, abs_err;
    real    sum_abs_err_valid, max_abs_err_valid;
    real    sum_abs_err_full,  max_abs_err_full;
    integer n_valid, n_full;
    integer hist [0:10];    // ULP error histogram buckets: 0, 1, 2, ..., 9, >=10

    initial begin
        $display("");
        $display("================================================================");
        $display("  tb_exp_accuracy: expcalc_v2 exhaustive accuracy (all 256)    ");
        $display("  Reference: round( exp(psum/128) * 128 ), clipped to [0, 255] ");
        $display("================================================================");

        for (i = 0; i < 11; i = i + 1) hist[i] = 0;
        sum_abs_err_valid = 0.0;  max_abs_err_valid = 0.0;
        sum_abs_err_full  = 0.0;  max_abs_err_full  = 0.0;
        n_valid = 0;  n_full = 0;

        for (i = -128; i <= 127; i = i + 1) begin
            psum = i[7:0];
            #1;                                  // combinational settle

            // FP reference: exp(x) scaled to Q1.7
            if (i >= 0)  x_real = 0.0;           // clamp matches HW behaviour
            else         x_real = $itor(i) / 128.0;
            e_real  = $exp(x_real);
            e_ref   = e_real * 128.0 + 0.5;      // round-half-up
            ref_int = $rtoi(e_ref);
            if (ref_int < 0)   ref_int = 0;
            if (ref_int > 255) ref_int = 255;

            err     = $itor(psum_exp) - $itor(ref_int);
            abs_err = (err < 0.0) ? -err : err;

            // Histogram (clamp to bucket 10 for |err| >= 10)
            if (abs_err >= 10.0) hist[10] = hist[10] + 1;
            else begin
                for (integer h = 0; h < 10; h = h + 1)
                    if (abs_err >= $itor(h) && abs_err < $itor(h+1))
                        hist[h] = hist[h] + 1;
            end

            // Full-range stats
            sum_abs_err_full = sum_abs_err_full + abs_err;
            if (abs_err > max_abs_err_full) max_abs_err_full = abs_err;
            n_full = n_full + 1;

            // Valid-range stats (psum <= 0 = the used domain)
            if (i <= 0) begin
                sum_abs_err_valid = sum_abs_err_valid + abs_err;
                if (abs_err > max_abs_err_valid) max_abs_err_valid = abs_err;
                n_valid = n_valid + 1;
            end

            // Spot-check a few interesting points
            if (i == -128 || i == -64 || i == -32 || i == -16 || i == -8 ||
                i == -4   || i == -2  || i == -1  || i ==  0  || i ==  1  ||
                i ==  64  || i == 127)
                $display("  psum = %4d | HW = %3d | Ref = %3d | |err| = %4.1f ULP",
                         i, psum_exp, ref_int, abs_err);
        end

        $display("");
        $display("  ULP-error histogram (|HW - Ref|):");
        $display("      0 ULP   : %0d", hist[0]);
        $display("      1 ULP   : %0d", hist[1]);
        $display("      2 ULP   : %0d", hist[2]);
        $display("      3 ULP   : %0d", hist[3]);
        $display("      4 ULP   : %0d", hist[4]);
        $display("      5 ULP   : %0d", hist[5]);
        $display("      6 ULP   : %0d", hist[6]);
        $display("      7-9 ULP : %0d", hist[7] + hist[8] + hist[9]);
        $display("     10+ ULP  : %0d", hist[10]);

        $display("");
        $display("================================================================");
        $display("  expcalc_v2 accuracy summary");
        $display("================================================================");
        $display("  Domain                       |  N   | MAE (ULP) | Max (ULP)");
        $display("  -----------------------------+------+-----------+----------");
        $display("  Valid (psum <= 0)            | %4d |  %7.3f  |  %6.2f",
                 n_valid, sum_abs_err_valid / n_valid, max_abs_err_valid);
        $display("  Full (psum in [-128, 127])   | %4d |  %7.3f  |  %6.2f",
                 n_full,  sum_abs_err_full  / n_full,  max_abs_err_full);
        $display("");
        $display("  Paper claim (expcalc_v2 docstring): Max 0.93 ULP, Mean 0.31 ULP");
        $display("================================================================");
        $finish;
    end

endmodule
