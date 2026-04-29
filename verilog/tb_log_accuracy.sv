`timescale 1ns / 1ps


module tb_log_accuracy;

    reg  [9:0] x;
    wire [7:0] log_x;

    logcalc_v2 DUT (
        .x     (x),
        .log_x (log_x)
    );

    integer i, ref_int;
    real    ln_real, ln_ref;
    real    err, abs_err;
    real    sum_abs_err_main, max_abs_err_main;
    real    sum_abs_err_full, max_abs_err_full;
    integer n_main, n_full;
    integer hist [0:10];

    initial begin
        $display("");
        $display("================================================================");
        $display("  tb_log_accuracy: logcalc_v2 exhaustive accuracy              ");
        $display("  Reference: round( ln(x) * 32 ), clamped to [0, 255]          ");
        $display("================================================================");

        for (i = 0; i < 11; i = i + 1) hist[i] = 0;
        sum_abs_err_main = 0.0;  max_abs_err_main = 0.0;
        sum_abs_err_full = 0.0;  max_abs_err_full = 0.0;
        n_main = 0;  n_full = 0;

        for (i = 1; i <= 1023; i = i + 1) begin
            x = i[9:0];
            #1;

            ln_real = $ln($itor(i));
            ln_ref  = ln_real * 32.0 + 0.5;
            ref_int = $rtoi(ln_ref);
            if (ref_int < 0)   ref_int = 0;
            if (ref_int > 255) ref_int = 255;

            err     = $itor(log_x) - $itor(ref_int);
            abs_err = (err < 0.0) ? -err : err;

            if (abs_err >= 10.0) hist[10] = hist[10] + 1;
            else begin
                for (integer h = 0; h < 10; h = h + 1)
                    if (abs_err >= $itor(h) && abs_err < $itor(h+1))
                        hist[h] = hist[h] + 1;
            end

            sum_abs_err_full = sum_abs_err_full + abs_err;
            if (abs_err > max_abs_err_full) max_abs_err_full = abs_err;
            n_full = n_full + 1;

            if (i <= 255) begin
                sum_abs_err_main = sum_abs_err_main + abs_err;
                if (abs_err > max_abs_err_main) max_abs_err_main = abs_err;
                n_main = n_main + 1;
            end

            if (i == 1 || i == 2 || i == 8 || i == 47 || i == 128 ||
                i == 255 || i == 512 || i == 1023)
                $display("  x = %4d | HW = %3d | Ref = %3d | |err| = %4.1f ULP (Q3.5)",
                         i, log_x, ref_int, abs_err);
        end

        $display("");
        $display("  ULP-error histogram (|HW - Ref|, Q3.5):");
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
        $display("  logcalc_v2 accuracy summary");
        $display("================================================================");
        $display("  Domain                       |   N   | MAE (ULP) | Max (ULP)");
        $display("  -----------------------------+-------+-----------+----------");
        $display("  Main (x in [1, 255])         | %5d |  %7.3f  |  %6.2f",
                 n_main, sum_abs_err_main / n_main, max_abs_err_main);
        $display("  Full (x in [1, 1023])        | %5d |  %7.3f  |  %6.2f",
                 n_full, sum_abs_err_full / n_full, max_abs_err_full);
        $display("");
        $display("  (Q3.5 ULP = 1/32 of ln(x); 1 ULP ~= 0.03 in natural units)");
        $display("================================================================");
        $finish;
    end

endmodule
