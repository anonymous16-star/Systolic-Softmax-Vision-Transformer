`timescale 1ns / 1ps

module linear_proj (
    input  wire        clk,
    input  wire        rst,
    input  wire load_wc1,  load_wc2,  load_wc3,  load_wc4,
    input  wire load_wc5,  load_wc6,  load_wc7,  load_wc8,
    input  wire load_wc9,  load_wc10, load_wc11, load_wc12,
    input  wire load_wc13, load_wc14, load_wc15, load_wc16,
    input  wire [127:0] w,         
    input  wire [7:0]  x0,  x1,  x2,  x3,
    input  wire [7:0]  x4,  x5,  x6,  x7,
    input  wire [7:0]  x8,  x9,  x10, x11,
    input  wire [7:0]  x12, x13, x14, x15,
    input  wire        valid_x,
    output reg  [7:0]  y0,  y1,  y2,  y3,
    output reg  [7:0]  y4,  y5,  y6,  y7,
    output reg  [7:0]  y8,  y9,  y10, y11,
    output reg  [7:0]  y12, y13, y14, y15,
    output reg         out_valid
);

    wire [7:0] e1, e2, e3, e4, e5, e6, e7, e8;
    wire [7:0] e9, e10, e11, e12, e13, e14, e15, e16;

    systolic_16x16 u_sa (
        .clk       (clk),
        .rst       (rst),
        .load_kc1  (load_wc1),  .load_kc2  (load_wc2),
        .load_kc3  (load_wc3),  .load_kc4  (load_wc4),
        .load_kc5  (load_wc5),  .load_kc6  (load_wc6),
        .load_kc7  (load_wc7),  .load_kc8  (load_wc8),
        .load_kc9  (load_wc9),  .load_kc10 (load_wc10),
        .load_kc11 (load_wc11), .load_kc12 (load_wc12),
        .load_kc13 (load_wc13), .load_kc14 (load_wc14),
        .load_kc15 (load_wc15), .load_kc16 (load_wc16),
        .k         (w),
        .q0(x0), .q1(x1), .q2(x2), .q3(x3),
        .q4(x4), .q5(x5), .q6(x6), .q7(x7),
        .q8(x8), .q9(x9), .q10(x10), .q11(x11),
        .q12(x12), .q13(x13), .q14(x14), .q15(x15),
        .valid_q   (valid_x),
        .e1(e1),   .e2(e2),   .e3(e3),   .e4(e4),
        .e5(e5),   .e6(e6),   .e7(e7),   .e8(e8),
        .e9(e9),   .e10(e10), .e11(e11), .e12(e12),
        .e13(e13), .e14(e14), .e15(e15), .e16(e16)
    );
    reg [11:0] valid_sr;
    always @(posedge clk) begin
        if (rst) valid_sr <= 12'd0;
        else     valid_sr <= {valid_sr[10:0], valid_x};
    end

    always @(posedge clk) begin
        if (rst) begin
            {y0,y1,y2,y3,y4,y5,y6,y7,y8,y9,y10,y11,y12,y13,y14,y15} <= 128'd0;
            out_valid <= 1'b0;
        end else begin
            out_valid <= valid_sr[11];
            if (valid_sr[11]) begin
                y0  <= e1;  y1  <= e2;  y2  <= e3;  y3  <= e4;
                y4  <= e5;  y5  <= e6;  y6  <= e7;  y7  <= e8;
                y8  <= e9;  y9  <= e10; y10 <= e11; y11 <= e12;
                y12 <= e13; y13 <= e14; y14 <= e15; y15 <= e16;
            end
        end
    end

endmodule
