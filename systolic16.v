`timescale 1ns / 1ps

module systolic_16x16 (
    input        clk,
    input        rst,

    // Per-column load_k strobes (load K into all rows of that column)
    input  load_kc1,  load_kc2,  load_kc3,  load_kc4,
    input  load_kc5,  load_kc6,  load_kc7,  load_kc8,
    input  load_kc9,  load_kc10, load_kc11, load_kc12,
    input  load_kc13, load_kc14, load_kc15, load_kc16,

    // 128-bit K bus: row r uses k[(r*8+7):(r*8)]
    input  [127:0] k,

    // Q inputs: one per COLUMN (enters at top row, flows downward)
    input  [7:0]  q0,  q1,  q2,  q3,
    input  [7:0]  q4,  q5,  q6,  q7,
    input  [7:0]  q8,  q9,  q10, q11,
    input  [7:0]  q12, q13, q14, q15,
    input         valid_q,

    // Row outputs: fifo_out_right of rightmost PE per row
    output [7:0]  e1,  e2,  e3,  e4,
    output [7:0]  e5,  e6,  e7,  e8,
    output [7:0]  e9,  e10, e11, e12,
    output [7:0]  e13, e14, e15, e16
);

    // =========================================================
    // fifo_out_right wires f[row][col]  (horizontal, left?right)
    // =========================================================
    wire [7:0] f00,f01,f02,f03,f04,f05,f06,f07,f08,f09,f010,f011,f012,f013,f014,f015;
    wire [7:0] f10,f11,f12,f13,f14,f15,f16,f17,f18,f19,f110,f111,f112,f113,f114,f115;
    wire [7:0] f20,f21,f22,f23,f24,f25,f26,f27,f28,f29,f210,f211,f212,f213,f214,f215;
    wire [7:0] f30,f31,f32,f33,f34,f35,f36,f37,f38,f39,f310,f311,f312,f313,f314,f315;
    wire [7:0] f40,f41,f42,f43,f44,f45,f46,f47,f48,f49,f410,f411,f412,f413,f414,f415;
    wire [7:0] f50,f51,f52,f53,f54,f55,f56,f57,f58,f59,f510,f511,f512,f513,f514,f515;
    wire [7:0] f60,f61,f62,f63,f64,f65,f66,f67,f68,f69,f610,f611,f612,f613,f614,f615;
    wire [7:0] f70,f71,f72,f73,f74,f75,f76,f77,f78,f79,f710,f711,f712,f713,f714,f715;
    wire [7:0] f80,f81,f82,f83,f84,f85,f86,f87,f88,f89,f810,f811,f812,f813,f814,f815;
    wire [7:0] f90,f91,f92,f93,f94,f95,f96,f97,f98,f99,f910,f911,f912,f913,f914,f915;
    wire [7:0] fa0,fa1,fa2,fa3,fa4,fa5,fa6,fa7,fa8,fa9,fa10,fa11,fa12,fa13,fa14,fa15;
    wire [7:0] fb0,fb1,fb2,fb3,fb4,fb5,fb6,fb7,fb8,fb9,fb10,fb11,fb12,fb13,fb14,fb15;
    wire [7:0] fc0,fc1,fc2,fc3,fc4,fc5,fc6,fc7,fc8,fc9,fc10,fc11,fc12,fc13,fc14,fc15;
    wire [7:0] fd0,fd1,fd2,fd3,fd4,fd5,fd6,fd7,fd8,fd9,fd10,fd11,fd12,fd13,fd14,fd15;
    wire [7:0] fe0,fe1,fe2,fe3,fe4,fe5,fe6,fe7,fe8,fe9,fe10,fe11,fe12,fe13,fe14,fe15;
    wire [7:0] ff0,ff1,ff2,ff3,ff4,ff5,ff6,ff7,ff8,ff9,ff10,ff11,ff12,ff13,ff14,ff15;

    // =========================================================
    // data_out wires dout[row][col]  (= q passed through, vertical)
    // dout[r][c] feeds q input of pe[r+1][c]
    // =========================================================
    wire [7:0] d00,d01,d02,d03,d04,d05,d06,d07,d08,d09,d010,d011,d012,d013,d014,d015;
    wire [7:0] d10,d11,d12,d13,d14,d15,d16,d17,d18,d19,d110,d111,d112,d113,d114,d115;
    wire [7:0] d20,d21,d22,d23,d24,d25,d26,d27,d28,d29,d210,d211,d212,d213,d214,d215;
    wire [7:0] d30,d31,d32,d33,d34,d35,d36,d37,d38,d39,d310,d311,d312,d313,d314,d315;
    wire [7:0] d40,d41,d42,d43,d44,d45,d46,d47,d48,d49,d410,d411,d412,d413,d414,d415;
    wire [7:0] d50,d51,d52,d53,d54,d55,d56,d57,d58,d59,d510,d511,d512,d513,d514,d515;
    wire [7:0] d60,d61,d62,d63,d64,d65,d66,d67,d68,d69,d610,d611,d612,d613,d614,d615;
    wire [7:0] d70,d71,d72,d73,d74,d75,d76,d77,d78,d79,d710,d711,d712,d713,d714,d715;
    wire [7:0] d80,d81,d82,d83,d84,d85,d86,d87,d88,d89,d810,d811,d812,d813,d814,d815;
    wire [7:0] d90,d91,d92,d93,d94,d95,d96,d97,d98,d99,d910,d911,d912,d913,d914,d915;
    wire [7:0] da0,da1,da2,da3,da4,da5,da6,da7,da8,da9,da10,da11,da12,da13,da14,da15;
    wire [7:0] db0,db1,db2,db3,db4,db5,db6,db7,db8,db9,db10,db11,db12,db13,db14,db15;
    wire [7:0] dc0,dc1,dc2,dc3,dc4,dc5,dc6,dc7,dc8,dc9,dc10,dc11,dc12,dc13,dc14,dc15;
    wire [7:0] dd0,dd1,dd2,dd3,dd4,dd5,dd6,dd7,dd8,dd9,dd10,dd11,dd12,dd13,dd14,dd15;
    wire [7:0] de0,de1,de2,de3,de4,de5,de6,de7,de8,de9,de10,de11,de12,de13,de14,de15;

    // =========================================================
    // psum wires ps[row][col]  (vertical: ps[r][c] ? pin of pe[r+1][c])
    // =========================================================
    wire [7:0] ps00,ps01,ps02,ps03,ps04,ps05,ps06,ps07,ps08,ps09,ps010,ps011,ps012,ps013,ps014,ps015;
    wire [7:0] ps10,ps11,ps12,ps13,ps14,ps15,ps16,ps17,ps18,ps19,ps110,ps111,ps112,ps113,ps114,ps115;
    wire [7:0] ps20,ps21,ps22,ps23,ps24,ps25,ps26,ps27,ps28,ps29,ps210,ps211,ps212,ps213,ps214,ps215;
    wire [7:0] ps30,ps31,ps32,ps33,ps34,ps35,ps36,ps37,ps38,ps39,ps310,ps311,ps312,ps313,ps314,ps315;
    wire [7:0] ps40,ps41,ps42,ps43,ps44,ps45,ps46,ps47,ps48,ps49,ps410,ps411,ps412,ps413,ps414,ps415;
    wire [7:0] ps50,ps51,ps52,ps53,ps54,ps55,ps56,ps57,ps58,ps59,ps510,ps511,ps512,ps513,ps514,ps515;
    wire [7:0] ps60,ps61,ps62,ps63,ps64,ps65,ps66,ps67,ps68,ps69,ps610,ps611,ps612,ps613,ps614,ps615;
    wire [7:0] ps70,ps71,ps72,ps73,ps74,ps75,ps76,ps77,ps78,ps79,ps710,ps711,ps712,ps713,ps714,ps715;
    wire [7:0] ps80,ps81,ps82,ps83,ps84,ps85,ps86,ps87,ps88,ps89,ps810,ps811,ps812,ps813,ps814,ps815;
    wire [7:0] ps90,ps91,ps92,ps93,ps94,ps95,ps96,ps97,ps98,ps99,ps910,ps911,ps912,ps913,ps914,ps915;
    wire [7:0] psa0,psa1,psa2,psa3,psa4,psa5,psa6,psa7,psa8,psa9,psa10,psa11,psa12,psa13,psa14,psa15;
    wire [7:0] psb0,psb1,psb2,psb3,psb4,psb5,psb6,psb7,psb8,psb9,psb10,psb11,psb12,psb13,psb14,psb15;
    wire [7:0] psc0,psc1,psc2,psc3,psc4,psc5,psc6,psc7,psc8,psc9,psc10,psc11,psc12,psc13,psc14,psc15;
    wire [7:0] psd0,psd1,psd2,psd3,psd4,psd5,psd6,psd7,psd8,psd9,psd10,psd11,psd12,psd13,psd14,psd15;
    wire [7:0] pse0,pse1,pse2,pse3,pse4,pse5,pse6,pse7,pse8,pse9,pse10,pse11,pse12,pse13,pse14,pse15;
    wire [7:0] psf0,psf1,psf2,psf3,psf4,psf5,psf6,psf7,psf8,psf9,psf10,psf11,psf12,psf13,psf14,psf15;

    // =========================================================
    // PE ARRAY
    //
    // pe[row][col]:
    //   .k    = k[(row*8+7):(row*8)]       stationary weight for this row
    //   .q    = data_out of pe[row-1][col]  Q flows downward
    //           (row 0: external q input)
    //   .pin  = psum of pe[row-1][col]      partial sum flows downward
    //           (row 0: 8'd0)
    //   .psum = ps[row][col]                captured, fed to row below as pin
    //   .left_fifo_out = f[row][col-1]      horizontal accumulation
    //           (col 0: 8'd0)
    //   .fifo_out_right = f[row][col]       passed to col+1
    //   .data_out = d[row][col]             = q, passed to row below
    //   .load_k = load_kc(col+1)            per-column load strobe
    //   .valid_q = valid_q                  same for all PEs (no skew needed)
    // =========================================================

    // ---- ROW 0  (pin=0, q from external inputs) ----
    BSPE pe00 (.clk(clk),.rst(rst),.k(k[7:0]),   .q(q0), .pin(8'd0),.psum(ps00),.valid_q(valid_q),.load_k(load_kc1), .left_valid(1'b1),.left_fifo_out(8'd0),.left_read(),.right_inread(1'b1),.fifo_out_right(f00), .fifo_read_out(),.data_out(d00));
    BSPE pe01 (.clk(clk),.rst(rst),.k(k[7:0]),   .q(q1), .pin(8'd0),.psum(ps01),.valid_q(valid_q),.load_k(load_kc2), .left_valid(1'b1),.left_fifo_out(f00), .left_read(),.right_inread(1'b1),.fifo_out_right(f01), .fifo_read_out(),.data_out(d01));
    BSPE pe02 (.clk(clk),.rst(rst),.k(k[7:0]),   .q(q2), .pin(8'd0),.psum(ps02),.valid_q(valid_q),.load_k(load_kc3), .left_valid(1'b1),.left_fifo_out(f01), .left_read(),.right_inread(1'b1),.fifo_out_right(f02), .fifo_read_out(),.data_out(d02));
    BSPE pe03 (.clk(clk),.rst(rst),.k(k[7:0]),   .q(q3), .pin(8'd0),.psum(ps03),.valid_q(valid_q),.load_k(load_kc4), .left_valid(1'b1),.left_fifo_out(f02), .left_read(),.right_inread(1'b1),.fifo_out_right(f03), .fifo_read_out(),.data_out(d03));
    BSPE pe04 (.clk(clk),.rst(rst),.k(k[7:0]),   .q(q4), .pin(8'd0),.psum(ps04),.valid_q(valid_q),.load_k(load_kc5), .left_valid(1'b1),.left_fifo_out(f03), .left_read(),.right_inread(1'b1),.fifo_out_right(f04), .fifo_read_out(),.data_out(d04));
    BSPE pe05 (.clk(clk),.rst(rst),.k(k[7:0]),   .q(q5), .pin(8'd0),.psum(ps05),.valid_q(valid_q),.load_k(load_kc6), .left_valid(1'b1),.left_fifo_out(f04), .left_read(),.right_inread(1'b1),.fifo_out_right(f05), .fifo_read_out(),.data_out(d05));
    BSPE pe06 (.clk(clk),.rst(rst),.k(k[7:0]),   .q(q6), .pin(8'd0),.psum(ps06),.valid_q(valid_q),.load_k(load_kc7), .left_valid(1'b1),.left_fifo_out(f05), .left_read(),.right_inread(1'b1),.fifo_out_right(f06), .fifo_read_out(),.data_out(d06));
    BSPE pe07 (.clk(clk),.rst(rst),.k(k[7:0]),   .q(q7), .pin(8'd0),.psum(ps07),.valid_q(valid_q),.load_k(load_kc8), .left_valid(1'b1),.left_fifo_out(f06), .left_read(),.right_inread(1'b1),.fifo_out_right(f07), .fifo_read_out(),.data_out(d07));
    BSPE pe08 (.clk(clk),.rst(rst),.k(k[7:0]),   .q(q8), .pin(8'd0),.psum(ps08),.valid_q(valid_q),.load_k(load_kc9), .left_valid(1'b1),.left_fifo_out(f07), .left_read(),.right_inread(1'b1),.fifo_out_right(f08), .fifo_read_out(),.data_out(d08));
    BSPE pe09 (.clk(clk),.rst(rst),.k(k[7:0]),   .q(q9), .pin(8'd0),.psum(ps09),.valid_q(valid_q),.load_k(load_kc10),.left_valid(1'b1),.left_fifo_out(f08), .left_read(),.right_inread(1'b1),.fifo_out_right(f09), .fifo_read_out(),.data_out(d09));
    BSPE pe010(.clk(clk),.rst(rst),.k(k[7:0]),   .q(q10),.pin(8'd0),.psum(ps010),.valid_q(valid_q),.load_k(load_kc11),.left_valid(1'b1),.left_fifo_out(f09), .left_read(),.right_inread(1'b1),.fifo_out_right(f010),.fifo_read_out(),.data_out(d010));
    BSPE pe011(.clk(clk),.rst(rst),.k(k[7:0]),   .q(q11),.pin(8'd0),.psum(ps011),.valid_q(valid_q),.load_k(load_kc12),.left_valid(1'b1),.left_fifo_out(f010),.left_read(),.right_inread(1'b1),.fifo_out_right(f011),.fifo_read_out(),.data_out(d011));
    BSPE pe012(.clk(clk),.rst(rst),.k(k[7:0]),   .q(q12),.pin(8'd0),.psum(ps012),.valid_q(valid_q),.load_k(load_kc13),.left_valid(1'b1),.left_fifo_out(f011),.left_read(),.right_inread(1'b1),.fifo_out_right(f012),.fifo_read_out(),.data_out(d012));
    BSPE pe013(.clk(clk),.rst(rst),.k(k[7:0]),   .q(q13),.pin(8'd0),.psum(ps013),.valid_q(valid_q),.load_k(load_kc14),.left_valid(1'b1),.left_fifo_out(f012),.left_read(),.right_inread(1'b1),.fifo_out_right(f013),.fifo_read_out(),.data_out(d013));
    BSPE pe014(.clk(clk),.rst(rst),.k(k[7:0]),   .q(q14),.pin(8'd0),.psum(ps014),.valid_q(valid_q),.load_k(load_kc15),.left_valid(1'b1),.left_fifo_out(f013),.left_read(),.right_inread(1'b1),.fifo_out_right(f014),.fifo_read_out(),.data_out(d014));
    BSPE pe015(.clk(clk),.rst(rst),.k(k[7:0]),   .q(q15),.pin(8'd0),.psum(ps015),.valid_q(valid_q),.load_k(load_kc16),.left_valid(1'b1),.left_fifo_out(f014),.left_read(),.right_inread(1'b1),.fifo_out_right(f015),.fifo_read_out(),.data_out(d015));

    // ---- ROW 1  (q = data_out of row 0, pin = psum of row 0) ----
    BSPE pe10 (.clk(clk),.rst(rst),.k(k[15:8]),  .q(d00),.pin(ps00),.psum(ps10),.valid_q(valid_q),.load_k(load_kc1), .left_valid(1'b1),.left_fifo_out(8'd0),.left_read(),.right_inread(1'b1),.fifo_out_right(f10), .fifo_read_out(),.data_out(d10));
    BSPE pe11 (.clk(clk),.rst(rst),.k(k[15:8]),  .q(d01),.pin(ps01),.psum(ps11),.valid_q(valid_q),.load_k(load_kc2), .left_valid(1'b1),.left_fifo_out(f10), .left_read(),.right_inread(1'b1),.fifo_out_right(f11), .fifo_read_out(),.data_out(d11));
    BSPE pe12 (.clk(clk),.rst(rst),.k(k[15:8]),  .q(d02),.pin(ps02),.psum(ps12),.valid_q(valid_q),.load_k(load_kc3), .left_valid(1'b1),.left_fifo_out(f11), .left_read(),.right_inread(1'b1),.fifo_out_right(f12), .fifo_read_out(),.data_out(d12));
    BSPE pe13 (.clk(clk),.rst(rst),.k(k[15:8]),  .q(d03),.pin(ps03),.psum(ps13),.valid_q(valid_q),.load_k(load_kc4), .left_valid(1'b1),.left_fifo_out(f12), .left_read(),.right_inread(1'b1),.fifo_out_right(f13), .fifo_read_out(),.data_out(d13));
    BSPE pe14 (.clk(clk),.rst(rst),.k(k[15:8]),  .q(d04),.pin(ps04),.psum(ps14),.valid_q(valid_q),.load_k(load_kc5), .left_valid(1'b1),.left_fifo_out(f13), .left_read(),.right_inread(1'b1),.fifo_out_right(f14), .fifo_read_out(),.data_out(d14));
    BSPE pe15 (.clk(clk),.rst(rst),.k(k[15:8]),  .q(d05),.pin(ps05),.psum(ps15),.valid_q(valid_q),.load_k(load_kc6), .left_valid(1'b1),.left_fifo_out(f14), .left_read(),.right_inread(1'b1),.fifo_out_right(f15), .fifo_read_out(),.data_out(d15));
    BSPE pe16 (.clk(clk),.rst(rst),.k(k[15:8]),  .q(d06),.pin(ps06),.psum(ps16),.valid_q(valid_q),.load_k(load_kc7), .left_valid(1'b1),.left_fifo_out(f15), .left_read(),.right_inread(1'b1),.fifo_out_right(f16), .fifo_read_out(),.data_out(d16));
    BSPE pe17 (.clk(clk),.rst(rst),.k(k[15:8]),  .q(d07),.pin(ps07),.psum(ps17),.valid_q(valid_q),.load_k(load_kc8), .left_valid(1'b1),.left_fifo_out(f16), .left_read(),.right_inread(1'b1),.fifo_out_right(f17), .fifo_read_out(),.data_out(d17));
    BSPE pe18 (.clk(clk),.rst(rst),.k(k[15:8]),  .q(d08),.pin(ps08),.psum(ps18),.valid_q(valid_q),.load_k(load_kc9), .left_valid(1'b1),.left_fifo_out(f17), .left_read(),.right_inread(1'b1),.fifo_out_right(f18), .fifo_read_out(),.data_out(d18));
    BSPE pe19 (.clk(clk),.rst(rst),.k(k[15:8]),  .q(d09),.pin(ps09),.psum(ps19),.valid_q(valid_q),.load_k(load_kc10),.left_valid(1'b1),.left_fifo_out(f18), .left_read(),.right_inread(1'b1),.fifo_out_right(f19), .fifo_read_out(),.data_out(d19));
    BSPE pe110(.clk(clk),.rst(rst),.k(k[15:8]),  .q(d010),.pin(ps010),.psum(ps110),.valid_q(valid_q),.load_k(load_kc11),.left_valid(1'b1),.left_fifo_out(f19), .left_read(),.right_inread(1'b1),.fifo_out_right(f110),.fifo_read_out(),.data_out(d110));
    BSPE pe111(.clk(clk),.rst(rst),.k(k[15:8]),  .q(d011),.pin(ps011),.psum(ps111),.valid_q(valid_q),.load_k(load_kc12),.left_valid(1'b1),.left_fifo_out(f110),.left_read(),.right_inread(1'b1),.fifo_out_right(f111),.fifo_read_out(),.data_out(d111));
    BSPE pe112(.clk(clk),.rst(rst),.k(k[15:8]),  .q(d012),.pin(ps012),.psum(ps112),.valid_q(valid_q),.load_k(load_kc13),.left_valid(1'b1),.left_fifo_out(f111),.left_read(),.right_inread(1'b1),.fifo_out_right(f112),.fifo_read_out(),.data_out(d112));
    BSPE pe113(.clk(clk),.rst(rst),.k(k[15:8]),  .q(d013),.pin(ps013),.psum(ps113),.valid_q(valid_q),.load_k(load_kc14),.left_valid(1'b1),.left_fifo_out(f112),.left_read(),.right_inread(1'b1),.fifo_out_right(f113),.fifo_read_out(),.data_out(d113));
    BSPE pe114(.clk(clk),.rst(rst),.k(k[15:8]),  .q(d014),.pin(ps014),.psum(ps114),.valid_q(valid_q),.load_k(load_kc15),.left_valid(1'b1),.left_fifo_out(f113),.left_read(),.right_inread(1'b1),.fifo_out_right(f114),.fifo_read_out(),.data_out(d114));
    BSPE pe115(.clk(clk),.rst(rst),.k(k[15:8]),  .q(d015),.pin(ps015),.psum(ps115),.valid_q(valid_q),.load_k(load_kc16),.left_valid(1'b1),.left_fifo_out(f114),.left_read(),.right_inread(1'b1),.fifo_out_right(f115),.fifo_read_out(),.data_out(d115));

    // ---- ROW 2 ----
    BSPE pe20 (.clk(clk),.rst(rst),.k(k[23:16]), .q(d10),.pin(ps10),.psum(ps20),.valid_q(valid_q),.load_k(load_kc1), .left_valid(1'b1),.left_fifo_out(8'd0),.left_read(),.right_inread(1'b1),.fifo_out_right(f20), .fifo_read_out(),.data_out(d20));
    BSPE pe21 (.clk(clk),.rst(rst),.k(k[23:16]), .q(d11),.pin(ps11),.psum(ps21),.valid_q(valid_q),.load_k(load_kc2), .left_valid(1'b1),.left_fifo_out(f20), .left_read(),.right_inread(1'b1),.fifo_out_right(f21), .fifo_read_out(),.data_out(d21));
    BSPE pe22 (.clk(clk),.rst(rst),.k(k[23:16]), .q(d12),.pin(ps12),.psum(ps22),.valid_q(valid_q),.load_k(load_kc3), .left_valid(1'b1),.left_fifo_out(f21), .left_read(),.right_inread(1'b1),.fifo_out_right(f22), .fifo_read_out(),.data_out(d22));
    BSPE pe23 (.clk(clk),.rst(rst),.k(k[23:16]), .q(d13),.pin(ps13),.psum(ps23),.valid_q(valid_q),.load_k(load_kc4), .left_valid(1'b1),.left_fifo_out(f22), .left_read(),.right_inread(1'b1),.fifo_out_right(f23), .fifo_read_out(),.data_out(d23));
    BSPE pe24 (.clk(clk),.rst(rst),.k(k[23:16]), .q(d14),.pin(ps14),.psum(ps24),.valid_q(valid_q),.load_k(load_kc5), .left_valid(1'b1),.left_fifo_out(f23), .left_read(),.right_inread(1'b1),.fifo_out_right(f24), .fifo_read_out(),.data_out(d24));
    BSPE pe25 (.clk(clk),.rst(rst),.k(k[23:16]), .q(d15),.pin(ps15),.psum(ps25),.valid_q(valid_q),.load_k(load_kc6), .left_valid(1'b1),.left_fifo_out(f24), .left_read(),.right_inread(1'b1),.fifo_out_right(f25), .fifo_read_out(),.data_out(d25));
    BSPE pe26 (.clk(clk),.rst(rst),.k(k[23:16]), .q(d16),.pin(ps16),.psum(ps26),.valid_q(valid_q),.load_k(load_kc7), .left_valid(1'b1),.left_fifo_out(f25), .left_read(),.right_inread(1'b1),.fifo_out_right(f26), .fifo_read_out(),.data_out(d26));
    BSPE pe27 (.clk(clk),.rst(rst),.k(k[23:16]), .q(d17),.pin(ps17),.psum(ps27),.valid_q(valid_q),.load_k(load_kc8), .left_valid(1'b1),.left_fifo_out(f26), .left_read(),.right_inread(1'b1),.fifo_out_right(f27), .fifo_read_out(),.data_out(d27));
    BSPE pe28 (.clk(clk),.rst(rst),.k(k[23:16]), .q(d18),.pin(ps18),.psum(ps28),.valid_q(valid_q),.load_k(load_kc9), .left_valid(1'b1),.left_fifo_out(f27), .left_read(),.right_inread(1'b1),.fifo_out_right(f28), .fifo_read_out(),.data_out(d28));
    BSPE pe29 (.clk(clk),.rst(rst),.k(k[23:16]), .q(d19),.pin(ps19),.psum(ps29),.valid_q(valid_q),.load_k(load_kc10),.left_valid(1'b1),.left_fifo_out(f28), .left_read(),.right_inread(1'b1),.fifo_out_right(f29), .fifo_read_out(),.data_out(d29));
    BSPE pe210(.clk(clk),.rst(rst),.k(k[23:16]), .q(d110),.pin(ps110),.psum(ps210),.valid_q(valid_q),.load_k(load_kc11),.left_valid(1'b1),.left_fifo_out(f29), .left_read(),.right_inread(1'b1),.fifo_out_right(f210),.fifo_read_out(),.data_out(d210));
    BSPE pe211(.clk(clk),.rst(rst),.k(k[23:16]), .q(d111),.pin(ps111),.psum(ps211),.valid_q(valid_q),.load_k(load_kc12),.left_valid(1'b1),.left_fifo_out(f210),.left_read(),.right_inread(1'b1),.fifo_out_right(f211),.fifo_read_out(),.data_out(d211));
    BSPE pe212(.clk(clk),.rst(rst),.k(k[23:16]), .q(d112),.pin(ps112),.psum(ps212),.valid_q(valid_q),.load_k(load_kc13),.left_valid(1'b1),.left_fifo_out(f211),.left_read(),.right_inread(1'b1),.fifo_out_right(f212),.fifo_read_out(),.data_out(d212));
    BSPE pe213(.clk(clk),.rst(rst),.k(k[23:16]), .q(d113),.pin(ps113),.psum(ps213),.valid_q(valid_q),.load_k(load_kc14),.left_valid(1'b1),.left_fifo_out(f212),.left_read(),.right_inread(1'b1),.fifo_out_right(f213),.fifo_read_out(),.data_out(d213));
    BSPE pe214(.clk(clk),.rst(rst),.k(k[23:16]), .q(d114),.pin(ps114),.psum(ps214),.valid_q(valid_q),.load_k(load_kc15),.left_valid(1'b1),.left_fifo_out(f213),.left_read(),.right_inread(1'b1),.fifo_out_right(f214),.fifo_read_out(),.data_out(d214));
    BSPE pe215(.clk(clk),.rst(rst),.k(k[23:16]), .q(d115),.pin(ps115),.psum(ps215),.valid_q(valid_q),.load_k(load_kc16),.left_valid(1'b1),.left_fifo_out(f214),.left_read(),.right_inread(1'b1),.fifo_out_right(f215),.fifo_read_out(),.data_out(d215));

    // ---- ROW 3 ----
    BSPE pe30 (.clk(clk),.rst(rst),.k(k[31:24]), .q(d20),.pin(ps20),.psum(ps30),.valid_q(valid_q),.load_k(load_kc1), .left_valid(1'b1),.left_fifo_out(8'd0),.left_read(),.right_inread(1'b1),.fifo_out_right(f30), .fifo_read_out(),.data_out(d30));
    BSPE pe31 (.clk(clk),.rst(rst),.k(k[31:24]), .q(d21),.pin(ps21),.psum(ps31),.valid_q(valid_q),.load_k(load_kc2), .left_valid(1'b1),.left_fifo_out(f30), .left_read(),.right_inread(1'b1),.fifo_out_right(f31), .fifo_read_out(),.data_out(d31));
    BSPE pe32 (.clk(clk),.rst(rst),.k(k[31:24]), .q(d22),.pin(ps22),.psum(ps32),.valid_q(valid_q),.load_k(load_kc3), .left_valid(1'b1),.left_fifo_out(f31), .left_read(),.right_inread(1'b1),.fifo_out_right(f32), .fifo_read_out(),.data_out(d32));
    BSPE pe33 (.clk(clk),.rst(rst),.k(k[31:24]), .q(d23),.pin(ps23),.psum(ps33),.valid_q(valid_q),.load_k(load_kc4), .left_valid(1'b1),.left_fifo_out(f32), .left_read(),.right_inread(1'b1),.fifo_out_right(f33), .fifo_read_out(),.data_out(d33));
    BSPE pe34 (.clk(clk),.rst(rst),.k(k[31:24]), .q(d24),.pin(ps24),.psum(ps34),.valid_q(valid_q),.load_k(load_kc5), .left_valid(1'b1),.left_fifo_out(f33), .left_read(),.right_inread(1'b1),.fifo_out_right(f34), .fifo_read_out(),.data_out(d34));
    BSPE pe35 (.clk(clk),.rst(rst),.k(k[31:24]), .q(d25),.pin(ps25),.psum(ps35),.valid_q(valid_q),.load_k(load_kc6), .left_valid(1'b1),.left_fifo_out(f34), .left_read(),.right_inread(1'b1),.fifo_out_right(f35), .fifo_read_out(),.data_out(d35));
    BSPE pe36 (.clk(clk),.rst(rst),.k(k[31:24]), .q(d26),.pin(ps26),.psum(ps36),.valid_q(valid_q),.load_k(load_kc7), .left_valid(1'b1),.left_fifo_out(f35), .left_read(),.right_inread(1'b1),.fifo_out_right(f36), .fifo_read_out(),.data_out(d36));
    BSPE pe37 (.clk(clk),.rst(rst),.k(k[31:24]), .q(d27),.pin(ps27),.psum(ps37),.valid_q(valid_q),.load_k(load_kc8), .left_valid(1'b1),.left_fifo_out(f36), .left_read(),.right_inread(1'b1),.fifo_out_right(f37), .fifo_read_out(),.data_out(d37));
    BSPE pe38 (.clk(clk),.rst(rst),.k(k[31:24]), .q(d28),.pin(ps28),.psum(ps38),.valid_q(valid_q),.load_k(load_kc9), .left_valid(1'b1),.left_fifo_out(f37), .left_read(),.right_inread(1'b1),.fifo_out_right(f38), .fifo_read_out(),.data_out(d38));
    BSPE pe39 (.clk(clk),.rst(rst),.k(k[31:24]), .q(d29),.pin(ps29),.psum(ps39),.valid_q(valid_q),.load_k(load_kc10),.left_valid(1'b1),.left_fifo_out(f38), .left_read(),.right_inread(1'b1),.fifo_out_right(f39), .fifo_read_out(),.data_out(d39));
    BSPE pe310(.clk(clk),.rst(rst),.k(k[31:24]), .q(d210),.pin(ps210),.psum(ps310),.valid_q(valid_q),.load_k(load_kc11),.left_valid(1'b1),.left_fifo_out(f39), .left_read(),.right_inread(1'b1),.fifo_out_right(f310),.fifo_read_out(),.data_out(d310));
    BSPE pe311(.clk(clk),.rst(rst),.k(k[31:24]), .q(d211),.pin(ps211),.psum(ps311),.valid_q(valid_q),.load_k(load_kc12),.left_valid(1'b1),.left_fifo_out(f310),.left_read(),.right_inread(1'b1),.fifo_out_right(f311),.fifo_read_out(),.data_out(d311));
    BSPE pe312(.clk(clk),.rst(rst),.k(k[31:24]), .q(d212),.pin(ps212),.psum(ps312),.valid_q(valid_q),.load_k(load_kc13),.left_valid(1'b1),.left_fifo_out(f311),.left_read(),.right_inread(1'b1),.fifo_out_right(f312),.fifo_read_out(),.data_out(d312));
    BSPE pe313(.clk(clk),.rst(rst),.k(k[31:24]), .q(d213),.pin(ps213),.psum(ps313),.valid_q(valid_q),.load_k(load_kc14),.left_valid(1'b1),.left_fifo_out(f312),.left_read(),.right_inread(1'b1),.fifo_out_right(f313),.fifo_read_out(),.data_out(d313));
    BSPE pe314(.clk(clk),.rst(rst),.k(k[31:24]), .q(d214),.pin(ps214),.psum(ps314),.valid_q(valid_q),.load_k(load_kc15),.left_valid(1'b1),.left_fifo_out(f313),.left_read(),.right_inread(1'b1),.fifo_out_right(f314),.fifo_read_out(),.data_out(d314));
    BSPE pe315(.clk(clk),.rst(rst),.k(k[31:24]), .q(d215),.pin(ps215),.psum(ps315),.valid_q(valid_q),.load_k(load_kc16),.left_valid(1'b1),.left_fifo_out(f314),.left_read(),.right_inread(1'b1),.fifo_out_right(f315),.fifo_read_out(),.data_out(d315));

    // ---- ROW 4 ----
    BSPE pe40 (.clk(clk),.rst(rst),.k(k[39:32]), .q(d30),.pin(ps30),.psum(ps40),.valid_q(valid_q),.load_k(load_kc1), .left_valid(1'b1),.left_fifo_out(8'd0),.left_read(),.right_inread(1'b1),.fifo_out_right(f40), .fifo_read_out(),.data_out(d40));
    BSPE pe41 (.clk(clk),.rst(rst),.k(k[39:32]), .q(d31),.pin(ps31),.psum(ps41),.valid_q(valid_q),.load_k(load_kc2), .left_valid(1'b1),.left_fifo_out(f40), .left_read(),.right_inread(1'b1),.fifo_out_right(f41), .fifo_read_out(),.data_out(d41));
    BSPE pe42 (.clk(clk),.rst(rst),.k(k[39:32]), .q(d32),.pin(ps32),.psum(ps42),.valid_q(valid_q),.load_k(load_kc3), .left_valid(1'b1),.left_fifo_out(f41), .left_read(),.right_inread(1'b1),.fifo_out_right(f42), .fifo_read_out(),.data_out(d42));
    BSPE pe43 (.clk(clk),.rst(rst),.k(k[39:32]), .q(d33),.pin(ps33),.psum(ps43),.valid_q(valid_q),.load_k(load_kc4), .left_valid(1'b1),.left_fifo_out(f42), .left_read(),.right_inread(1'b1),.fifo_out_right(f43), .fifo_read_out(),.data_out(d43));
    BSPE pe44 (.clk(clk),.rst(rst),.k(k[39:32]), .q(d34),.pin(ps34),.psum(ps44),.valid_q(valid_q),.load_k(load_kc5), .left_valid(1'b1),.left_fifo_out(f43), .left_read(),.right_inread(1'b1),.fifo_out_right(f44), .fifo_read_out(),.data_out(d44));
    BSPE pe45 (.clk(clk),.rst(rst),.k(k[39:32]), .q(d35),.pin(ps35),.psum(ps45),.valid_q(valid_q),.load_k(load_kc6), .left_valid(1'b1),.left_fifo_out(f44), .left_read(),.right_inread(1'b1),.fifo_out_right(f45), .fifo_read_out(),.data_out(d45));
    BSPE pe46 (.clk(clk),.rst(rst),.k(k[39:32]), .q(d36),.pin(ps36),.psum(ps46),.valid_q(valid_q),.load_k(load_kc7), .left_valid(1'b1),.left_fifo_out(f45), .left_read(),.right_inread(1'b1),.fifo_out_right(f46), .fifo_read_out(),.data_out(d46));
    BSPE pe47 (.clk(clk),.rst(rst),.k(k[39:32]), .q(d37),.pin(ps37),.psum(ps47),.valid_q(valid_q),.load_k(load_kc8), .left_valid(1'b1),.left_fifo_out(f46), .left_read(),.right_inread(1'b1),.fifo_out_right(f47), .fifo_read_out(),.data_out(d47));
    BSPE pe48 (.clk(clk),.rst(rst),.k(k[39:32]), .q(d38),.pin(ps38),.psum(ps48),.valid_q(valid_q),.load_k(load_kc9), .left_valid(1'b1),.left_fifo_out(f47), .left_read(),.right_inread(1'b1),.fifo_out_right(f48), .fifo_read_out(),.data_out(d48));
    BSPE pe49 (.clk(clk),.rst(rst),.k(k[39:32]), .q(d39),.pin(ps39),.psum(ps49),.valid_q(valid_q),.load_k(load_kc10),.left_valid(1'b1),.left_fifo_out(f48), .left_read(),.right_inread(1'b1),.fifo_out_right(f49), .fifo_read_out(),.data_out(d49));
    BSPE pe410(.clk(clk),.rst(rst),.k(k[39:32]), .q(d310),.pin(ps310),.psum(ps410),.valid_q(valid_q),.load_k(load_kc11),.left_valid(1'b1),.left_fifo_out(f49), .left_read(),.right_inread(1'b1),.fifo_out_right(f410),.fifo_read_out(),.data_out(d410));
    BSPE pe411(.clk(clk),.rst(rst),.k(k[39:32]), .q(d311),.pin(ps311),.psum(ps411),.valid_q(valid_q),.load_k(load_kc12),.left_valid(1'b1),.left_fifo_out(f410),.left_read(),.right_inread(1'b1),.fifo_out_right(f411),.fifo_read_out(),.data_out(d411));
    BSPE pe412(.clk(clk),.rst(rst),.k(k[39:32]), .q(d312),.pin(ps312),.psum(ps412),.valid_q(valid_q),.load_k(load_kc13),.left_valid(1'b1),.left_fifo_out(f411),.left_read(),.right_inread(1'b1),.fifo_out_right(f412),.fifo_read_out(),.data_out(d412));
    BSPE pe413(.clk(clk),.rst(rst),.k(k[39:32]), .q(d313),.pin(ps313),.psum(ps413),.valid_q(valid_q),.load_k(load_kc14),.left_valid(1'b1),.left_fifo_out(f412),.left_read(),.right_inread(1'b1),.fifo_out_right(f413),.fifo_read_out(),.data_out(d413));
    BSPE pe414(.clk(clk),.rst(rst),.k(k[39:32]), .q(d314),.pin(ps314),.psum(ps414),.valid_q(valid_q),.load_k(load_kc15),.left_valid(1'b1),.left_fifo_out(f413),.left_read(),.right_inread(1'b1),.fifo_out_right(f414),.fifo_read_out(),.data_out(d414));
    BSPE pe415(.clk(clk),.rst(rst),.k(k[39:32]), .q(d315),.pin(ps315),.psum(ps415),.valid_q(valid_q),.load_k(load_kc16),.left_valid(1'b1),.left_fifo_out(f414),.left_read(),.right_inread(1'b1),.fifo_out_right(f415),.fifo_read_out(),.data_out(d415));

    // ---- ROW 5 ----
    BSPE pe50 (.clk(clk),.rst(rst),.k(k[47:40]), .q(d40),.pin(ps40),.psum(ps50),.valid_q(valid_q),.load_k(load_kc1), .left_valid(1'b1),.left_fifo_out(8'd0),.left_read(),.right_inread(1'b1),.fifo_out_right(f50), .fifo_read_out(),.data_out(d50));
    BSPE pe51 (.clk(clk),.rst(rst),.k(k[47:40]), .q(d41),.pin(ps41),.psum(ps51),.valid_q(valid_q),.load_k(load_kc2), .left_valid(1'b1),.left_fifo_out(f50), .left_read(),.right_inread(1'b1),.fifo_out_right(f51), .fifo_read_out(),.data_out(d51));
    BSPE pe52 (.clk(clk),.rst(rst),.k(k[47:40]), .q(d42),.pin(ps42),.psum(ps52),.valid_q(valid_q),.load_k(load_kc3), .left_valid(1'b1),.left_fifo_out(f51), .left_read(),.right_inread(1'b1),.fifo_out_right(f52), .fifo_read_out(),.data_out(d52));
    BSPE pe53 (.clk(clk),.rst(rst),.k(k[47:40]), .q(d43),.pin(ps43),.psum(ps53),.valid_q(valid_q),.load_k(load_kc4), .left_valid(1'b1),.left_fifo_out(f52), .left_read(),.right_inread(1'b1),.fifo_out_right(f53), .fifo_read_out(),.data_out(d53));
    BSPE pe54 (.clk(clk),.rst(rst),.k(k[47:40]), .q(d44),.pin(ps44),.psum(ps54),.valid_q(valid_q),.load_k(load_kc5), .left_valid(1'b1),.left_fifo_out(f53), .left_read(),.right_inread(1'b1),.fifo_out_right(f54), .fifo_read_out(),.data_out(d54));
    BSPE pe55 (.clk(clk),.rst(rst),.k(k[47:40]), .q(d45),.pin(ps45),.psum(ps55),.valid_q(valid_q),.load_k(load_kc6), .left_valid(1'b1),.left_fifo_out(f54), .left_read(),.right_inread(1'b1),.fifo_out_right(f55), .fifo_read_out(),.data_out(d55));
    BSPE pe56 (.clk(clk),.rst(rst),.k(k[47:40]), .q(d46),.pin(ps46),.psum(ps56),.valid_q(valid_q),.load_k(load_kc7), .left_valid(1'b1),.left_fifo_out(f55), .left_read(),.right_inread(1'b1),.fifo_out_right(f56), .fifo_read_out(),.data_out(d56));
    BSPE pe57 (.clk(clk),.rst(rst),.k(k[47:40]), .q(d47),.pin(ps47),.psum(ps57),.valid_q(valid_q),.load_k(load_kc8), .left_valid(1'b1),.left_fifo_out(f56), .left_read(),.right_inread(1'b1),.fifo_out_right(f57), .fifo_read_out(),.data_out(d57));
    BSPE pe58 (.clk(clk),.rst(rst),.k(k[47:40]), .q(d48),.pin(ps48),.psum(ps58),.valid_q(valid_q),.load_k(load_kc9), .left_valid(1'b1),.left_fifo_out(f57), .left_read(),.right_inread(1'b1),.fifo_out_right(f58), .fifo_read_out(),.data_out(d58));
    BSPE pe59 (.clk(clk),.rst(rst),.k(k[47:40]), .q(d49),.pin(ps49),.psum(ps59),.valid_q(valid_q),.load_k(load_kc10),.left_valid(1'b1),.left_fifo_out(f58), .left_read(),.right_inread(1'b1),.fifo_out_right(f59), .fifo_read_out(),.data_out(d59));
    BSPE pe510(.clk(clk),.rst(rst),.k(k[47:40]), .q(d410),.pin(ps410),.psum(ps510),.valid_q(valid_q),.load_k(load_kc11),.left_valid(1'b1),.left_fifo_out(f59), .left_read(),.right_inread(1'b1),.fifo_out_right(f510),.fifo_read_out(),.data_out(d510));
    BSPE pe511(.clk(clk),.rst(rst),.k(k[47:40]), .q(d411),.pin(ps411),.psum(ps511),.valid_q(valid_q),.load_k(load_kc12),.left_valid(1'b1),.left_fifo_out(f510),.left_read(),.right_inread(1'b1),.fifo_out_right(f511),.fifo_read_out(),.data_out(d511));
    BSPE pe512(.clk(clk),.rst(rst),.k(k[47:40]), .q(d412),.pin(ps412),.psum(ps512),.valid_q(valid_q),.load_k(load_kc13),.left_valid(1'b1),.left_fifo_out(f511),.left_read(),.right_inread(1'b1),.fifo_out_right(f512),.fifo_read_out(),.data_out(d512));
    BSPE pe513(.clk(clk),.rst(rst),.k(k[47:40]), .q(d413),.pin(ps413),.psum(ps513),.valid_q(valid_q),.load_k(load_kc14),.left_valid(1'b1),.left_fifo_out(f512),.left_read(),.right_inread(1'b1),.fifo_out_right(f513),.fifo_read_out(),.data_out(d513));
    BSPE pe514(.clk(clk),.rst(rst),.k(k[47:40]), .q(d414),.pin(ps414),.psum(ps514),.valid_q(valid_q),.load_k(load_kc15),.left_valid(1'b1),.left_fifo_out(f513),.left_read(),.right_inread(1'b1),.fifo_out_right(f514),.fifo_read_out(),.data_out(d514));
    BSPE pe515(.clk(clk),.rst(rst),.k(k[47:40]), .q(d415),.pin(ps415),.psum(ps515),.valid_q(valid_q),.load_k(load_kc16),.left_valid(1'b1),.left_fifo_out(f514),.left_read(),.right_inread(1'b1),.fifo_out_right(f515),.fifo_read_out(),.data_out(d515));

    // ---- ROW 6 ----
    BSPE pe60 (.clk(clk),.rst(rst),.k(k[55:48]), .q(d50),.pin(ps50),.psum(ps60),.valid_q(valid_q),.load_k(load_kc1), .left_valid(1'b1),.left_fifo_out(8'd0),.left_read(),.right_inread(1'b1),.fifo_out_right(f60), .fifo_read_out(),.data_out(d60));
    BSPE pe61 (.clk(clk),.rst(rst),.k(k[55:48]), .q(d51),.pin(ps51),.psum(ps61),.valid_q(valid_q),.load_k(load_kc2), .left_valid(1'b1),.left_fifo_out(f60), .left_read(),.right_inread(1'b1),.fifo_out_right(f61), .fifo_read_out(),.data_out(d61));
    BSPE pe62 (.clk(clk),.rst(rst),.k(k[55:48]), .q(d52),.pin(ps52),.psum(ps62),.valid_q(valid_q),.load_k(load_kc3), .left_valid(1'b1),.left_fifo_out(f61), .left_read(),.right_inread(1'b1),.fifo_out_right(f62), .fifo_read_out(),.data_out(d62));
    BSPE pe63 (.clk(clk),.rst(rst),.k(k[55:48]), .q(d53),.pin(ps53),.psum(ps63),.valid_q(valid_q),.load_k(load_kc4), .left_valid(1'b1),.left_fifo_out(f62), .left_read(),.right_inread(1'b1),.fifo_out_right(f63), .fifo_read_out(),.data_out(d63));
    BSPE pe64 (.clk(clk),.rst(rst),.k(k[55:48]), .q(d54),.pin(ps54),.psum(ps64),.valid_q(valid_q),.load_k(load_kc5), .left_valid(1'b1),.left_fifo_out(f63), .left_read(),.right_inread(1'b1),.fifo_out_right(f64), .fifo_read_out(),.data_out(d64));
    BSPE pe65 (.clk(clk),.rst(rst),.k(k[55:48]), .q(d55),.pin(ps55),.psum(ps65),.valid_q(valid_q),.load_k(load_kc6), .left_valid(1'b1),.left_fifo_out(f64), .left_read(),.right_inread(1'b1),.fifo_out_right(f65), .fifo_read_out(),.data_out(d65));
    BSPE pe66 (.clk(clk),.rst(rst),.k(k[55:48]), .q(d56),.pin(ps56),.psum(ps66),.valid_q(valid_q),.load_k(load_kc7), .left_valid(1'b1),.left_fifo_out(f65), .left_read(),.right_inread(1'b1),.fifo_out_right(f66), .fifo_read_out(),.data_out(d66));
    BSPE pe67 (.clk(clk),.rst(rst),.k(k[55:48]), .q(d57),.pin(ps57),.psum(ps67),.valid_q(valid_q),.load_k(load_kc8), .left_valid(1'b1),.left_fifo_out(f66), .left_read(),.right_inread(1'b1),.fifo_out_right(f67), .fifo_read_out(),.data_out(d67));
    BSPE pe68 (.clk(clk),.rst(rst),.k(k[55:48]), .q(d58),.pin(ps58),.psum(ps68),.valid_q(valid_q),.load_k(load_kc9), .left_valid(1'b1),.left_fifo_out(f67), .left_read(),.right_inread(1'b1),.fifo_out_right(f68), .fifo_read_out(),.data_out(d68));
    BSPE pe69 (.clk(clk),.rst(rst),.k(k[55:48]), .q(d59),.pin(ps59),.psum(ps69),.valid_q(valid_q),.load_k(load_kc10),.left_valid(1'b1),.left_fifo_out(f68), .left_read(),.right_inread(1'b1),.fifo_out_right(f69), .fifo_read_out(),.data_out(d69));
    BSPE pe610(.clk(clk),.rst(rst),.k(k[55:48]), .q(d510),.pin(ps510),.psum(ps610),.valid_q(valid_q),.load_k(load_kc11),.left_valid(1'b1),.left_fifo_out(f69), .left_read(),.right_inread(1'b1),.fifo_out_right(f610),.fifo_read_out(),.data_out(d610));
    BSPE pe611(.clk(clk),.rst(rst),.k(k[55:48]), .q(d511),.pin(ps511),.psum(ps611),.valid_q(valid_q),.load_k(load_kc12),.left_valid(1'b1),.left_fifo_out(f610),.left_read(),.right_inread(1'b1),.fifo_out_right(f611),.fifo_read_out(),.data_out(d611));
    BSPE pe612(.clk(clk),.rst(rst),.k(k[55:48]), .q(d512),.pin(ps512),.psum(ps612),.valid_q(valid_q),.load_k(load_kc13),.left_valid(1'b1),.left_fifo_out(f611),.left_read(),.right_inread(1'b1),.fifo_out_right(f612),.fifo_read_out(),.data_out(d612));
    BSPE pe613(.clk(clk),.rst(rst),.k(k[55:48]), .q(d513),.pin(ps513),.psum(ps613),.valid_q(valid_q),.load_k(load_kc14),.left_valid(1'b1),.left_fifo_out(f612),.left_read(),.right_inread(1'b1),.fifo_out_right(f613),.fifo_read_out(),.data_out(d613));
    BSPE pe614(.clk(clk),.rst(rst),.k(k[55:48]), .q(d514),.pin(ps514),.psum(ps614),.valid_q(valid_q),.load_k(load_kc15),.left_valid(1'b1),.left_fifo_out(f613),.left_read(),.right_inread(1'b1),.fifo_out_right(f614),.fifo_read_out(),.data_out(d614));
    BSPE pe615(.clk(clk),.rst(rst),.k(k[55:48]), .q(d515),.pin(ps515),.psum(ps615),.valid_q(valid_q),.load_k(load_kc16),.left_valid(1'b1),.left_fifo_out(f614),.left_read(),.right_inread(1'b1),.fifo_out_right(f615),.fifo_read_out(),.data_out(d615));

    // ---- ROW 7 ----
    BSPE pe70 (.clk(clk),.rst(rst),.k(k[63:56]), .q(d60),.pin(ps60),.psum(ps70),.valid_q(valid_q),.load_k(load_kc1), .left_valid(1'b1),.left_fifo_out(8'd0),.left_read(),.right_inread(1'b1),.fifo_out_right(f70), .fifo_read_out(),.data_out(d70));
    BSPE pe71 (.clk(clk),.rst(rst),.k(k[63:56]), .q(d61),.pin(ps61),.psum(ps71),.valid_q(valid_q),.load_k(load_kc2), .left_valid(1'b1),.left_fifo_out(f70), .left_read(),.right_inread(1'b1),.fifo_out_right(f71), .fifo_read_out(),.data_out(d71));
    BSPE pe72 (.clk(clk),.rst(rst),.k(k[63:56]), .q(d62),.pin(ps62),.psum(ps72),.valid_q(valid_q),.load_k(load_kc3), .left_valid(1'b1),.left_fifo_out(f71), .left_read(),.right_inread(1'b1),.fifo_out_right(f72), .fifo_read_out(),.data_out(d72));
    BSPE pe73 (.clk(clk),.rst(rst),.k(k[63:56]), .q(d63),.pin(ps63),.psum(ps73),.valid_q(valid_q),.load_k(load_kc4), .left_valid(1'b1),.left_fifo_out(f72), .left_read(),.right_inread(1'b1),.fifo_out_right(f73), .fifo_read_out(),.data_out(d73));
    BSPE pe74 (.clk(clk),.rst(rst),.k(k[63:56]), .q(d64),.pin(ps64),.psum(ps74),.valid_q(valid_q),.load_k(load_kc5), .left_valid(1'b1),.left_fifo_out(f73), .left_read(),.right_inread(1'b1),.fifo_out_right(f74), .fifo_read_out(),.data_out(d74));
    BSPE pe75 (.clk(clk),.rst(rst),.k(k[63:56]), .q(d65),.pin(ps65),.psum(ps75),.valid_q(valid_q),.load_k(load_kc6), .left_valid(1'b1),.left_fifo_out(f74), .left_read(),.right_inread(1'b1),.fifo_out_right(f75), .fifo_read_out(),.data_out(d75));
    BSPE pe76 (.clk(clk),.rst(rst),.k(k[63:56]), .q(d66),.pin(ps66),.psum(ps76),.valid_q(valid_q),.load_k(load_kc7), .left_valid(1'b1),.left_fifo_out(f75), .left_read(),.right_inread(1'b1),.fifo_out_right(f76), .fifo_read_out(),.data_out(d76));
    BSPE pe77 (.clk(clk),.rst(rst),.k(k[63:56]), .q(d67),.pin(ps67),.psum(ps77),.valid_q(valid_q),.load_k(load_kc8), .left_valid(1'b1),.left_fifo_out(f76), .left_read(),.right_inread(1'b1),.fifo_out_right(f77), .fifo_read_out(),.data_out(d77));
    BSPE pe78 (.clk(clk),.rst(rst),.k(k[63:56]), .q(d68),.pin(ps68),.psum(ps78),.valid_q(valid_q),.load_k(load_kc9), .left_valid(1'b1),.left_fifo_out(f77), .left_read(),.right_inread(1'b1),.fifo_out_right(f78), .fifo_read_out(),.data_out(d78));
    BSPE pe79 (.clk(clk),.rst(rst),.k(k[63:56]), .q(d69),.pin(ps69),.psum(ps79),.valid_q(valid_q),.load_k(load_kc10),.left_valid(1'b1),.left_fifo_out(f78), .left_read(),.right_inread(1'b1),.fifo_out_right(f79), .fifo_read_out(),.data_out(d79));
    BSPE pe710(.clk(clk),.rst(rst),.k(k[63:56]), .q(d610),.pin(ps610),.psum(ps710),.valid_q(valid_q),.load_k(load_kc11),.left_valid(1'b1),.left_fifo_out(f79), .left_read(),.right_inread(1'b1),.fifo_out_right(f710),.fifo_read_out(),.data_out(d710));
    BSPE pe711(.clk(clk),.rst(rst),.k(k[63:56]), .q(d611),.pin(ps611),.psum(ps711),.valid_q(valid_q),.load_k(load_kc12),.left_valid(1'b1),.left_fifo_out(f710),.left_read(),.right_inread(1'b1),.fifo_out_right(f711),.fifo_read_out(),.data_out(d711));
    BSPE pe712(.clk(clk),.rst(rst),.k(k[63:56]), .q(d612),.pin(ps612),.psum(ps712),.valid_q(valid_q),.load_k(load_kc13),.left_valid(1'b1),.left_fifo_out(f711),.left_read(),.right_inread(1'b1),.fifo_out_right(f712),.fifo_read_out(),.data_out(d712));
    BSPE pe713(.clk(clk),.rst(rst),.k(k[63:56]), .q(d613),.pin(ps613),.psum(ps713),.valid_q(valid_q),.load_k(load_kc14),.left_valid(1'b1),.left_fifo_out(f712),.left_read(),.right_inread(1'b1),.fifo_out_right(f713),.fifo_read_out(),.data_out(d713));
    BSPE pe714(.clk(clk),.rst(rst),.k(k[63:56]), .q(d614),.pin(ps614),.psum(ps714),.valid_q(valid_q),.load_k(load_kc15),.left_valid(1'b1),.left_fifo_out(f713),.left_read(),.right_inread(1'b1),.fifo_out_right(f714),.fifo_read_out(),.data_out(d714));
    BSPE pe715(.clk(clk),.rst(rst),.k(k[63:56]), .q(d615),.pin(ps615),.psum(ps715),.valid_q(valid_q),.load_k(load_kc16),.left_valid(1'b1),.left_fifo_out(f714),.left_read(),.right_inread(1'b1),.fifo_out_right(f715),.fifo_read_out(),.data_out(d715));

    // ---- ROW 8 ----
    BSPE pe80 (.clk(clk),.rst(rst),.k(k[71:64]), .q(d70),.pin(ps70),.psum(ps80),.valid_q(valid_q),.load_k(load_kc1), .left_valid(1'b1),.left_fifo_out(8'd0),.left_read(),.right_inread(1'b1),.fifo_out_right(f80), .fifo_read_out(),.data_out(d80));
    BSPE pe81 (.clk(clk),.rst(rst),.k(k[71:64]), .q(d71),.pin(ps71),.psum(ps81),.valid_q(valid_q),.load_k(load_kc2), .left_valid(1'b1),.left_fifo_out(f80), .left_read(),.right_inread(1'b1),.fifo_out_right(f81), .fifo_read_out(),.data_out(d81));
    BSPE pe82 (.clk(clk),.rst(rst),.k(k[71:64]), .q(d72),.pin(ps72),.psum(ps82),.valid_q(valid_q),.load_k(load_kc3), .left_valid(1'b1),.left_fifo_out(f81), .left_read(),.right_inread(1'b1),.fifo_out_right(f82), .fifo_read_out(),.data_out(d82));
    BSPE pe83 (.clk(clk),.rst(rst),.k(k[71:64]), .q(d73),.pin(ps73),.psum(ps83),.valid_q(valid_q),.load_k(load_kc4), .left_valid(1'b1),.left_fifo_out(f82), .left_read(),.right_inread(1'b1),.fifo_out_right(f83), .fifo_read_out(),.data_out(d83));
    BSPE pe84 (.clk(clk),.rst(rst),.k(k[71:64]), .q(d74),.pin(ps74),.psum(ps84),.valid_q(valid_q),.load_k(load_kc5), .left_valid(1'b1),.left_fifo_out(f83), .left_read(),.right_inread(1'b1),.fifo_out_right(f84), .fifo_read_out(),.data_out(d84));
    BSPE pe85 (.clk(clk),.rst(rst),.k(k[71:64]), .q(d75),.pin(ps75),.psum(ps85),.valid_q(valid_q),.load_k(load_kc6), .left_valid(1'b1),.left_fifo_out(f84), .left_read(),.right_inread(1'b1),.fifo_out_right(f85), .fifo_read_out(),.data_out(d85));
    BSPE pe86 (.clk(clk),.rst(rst),.k(k[71:64]), .q(d76),.pin(ps76),.psum(ps86),.valid_q(valid_q),.load_k(load_kc7), .left_valid(1'b1),.left_fifo_out(f85), .left_read(),.right_inread(1'b1),.fifo_out_right(f86), .fifo_read_out(),.data_out(d86));
    BSPE pe87 (.clk(clk),.rst(rst),.k(k[71:64]), .q(d77),.pin(ps77),.psum(ps87),.valid_q(valid_q),.load_k(load_kc8), .left_valid(1'b1),.left_fifo_out(f86), .left_read(),.right_inread(1'b1),.fifo_out_right(f87), .fifo_read_out(),.data_out(d87));
    BSPE pe88 (.clk(clk),.rst(rst),.k(k[71:64]), .q(d78),.pin(ps78),.psum(ps88),.valid_q(valid_q),.load_k(load_kc9), .left_valid(1'b1),.left_fifo_out(f87), .left_read(),.right_inread(1'b1),.fifo_out_right(f88), .fifo_read_out(),.data_out(d88));
    BSPE pe89 (.clk(clk),.rst(rst),.k(k[71:64]), .q(d79),.pin(ps79),.psum(ps89),.valid_q(valid_q),.load_k(load_kc10),.left_valid(1'b1),.left_fifo_out(f88), .left_read(),.right_inread(1'b1),.fifo_out_right(f89), .fifo_read_out(),.data_out(d89));
    BSPE pe810(.clk(clk),.rst(rst),.k(k[71:64]), .q(d710),.pin(ps710),.psum(ps810),.valid_q(valid_q),.load_k(load_kc11),.left_valid(1'b1),.left_fifo_out(f89), .left_read(),.right_inread(1'b1),.fifo_out_right(f810),.fifo_read_out(),.data_out(d810));
    BSPE pe811(.clk(clk),.rst(rst),.k(k[71:64]), .q(d711),.pin(ps711),.psum(ps811),.valid_q(valid_q),.load_k(load_kc12),.left_valid(1'b1),.left_fifo_out(f810),.left_read(),.right_inread(1'b1),.fifo_out_right(f811),.fifo_read_out(),.data_out(d811));
    BSPE pe812(.clk(clk),.rst(rst),.k(k[71:64]), .q(d712),.pin(ps712),.psum(ps812),.valid_q(valid_q),.load_k(load_kc13),.left_valid(1'b1),.left_fifo_out(f811),.left_read(),.right_inread(1'b1),.fifo_out_right(f812),.fifo_read_out(),.data_out(d812));
    BSPE pe813(.clk(clk),.rst(rst),.k(k[71:64]), .q(d713),.pin(ps713),.psum(ps813),.valid_q(valid_q),.load_k(load_kc14),.left_valid(1'b1),.left_fifo_out(f812),.left_read(),.right_inread(1'b1),.fifo_out_right(f813),.fifo_read_out(),.data_out(d813));
    BSPE pe814(.clk(clk),.rst(rst),.k(k[71:64]), .q(d714),.pin(ps714),.psum(ps814),.valid_q(valid_q),.load_k(load_kc15),.left_valid(1'b1),.left_fifo_out(f813),.left_read(),.right_inread(1'b1),.fifo_out_right(f814),.fifo_read_out(),.data_out(d814));
    BSPE pe815(.clk(clk),.rst(rst),.k(k[71:64]), .q(d715),.pin(ps715),.psum(ps815),.valid_q(valid_q),.load_k(load_kc16),.left_valid(1'b1),.left_fifo_out(f814),.left_read(),.right_inread(1'b1),.fifo_out_right(f815),.fifo_read_out(),.data_out(d815));

    // ---- ROW 9 ----
    BSPE pe90 (.clk(clk),.rst(rst),.k(k[79:72]), .q(d80),.pin(ps80),.psum(ps90),.valid_q(valid_q),.load_k(load_kc1), .left_valid(1'b1),.left_fifo_out(8'd0),.left_read(),.right_inread(1'b1),.fifo_out_right(f90), .fifo_read_out(),.data_out(d90));
    BSPE pe91 (.clk(clk),.rst(rst),.k(k[79:72]), .q(d81),.pin(ps81),.psum(ps91),.valid_q(valid_q),.load_k(load_kc2), .left_valid(1'b1),.left_fifo_out(f90), .left_read(),.right_inread(1'b1),.fifo_out_right(f91), .fifo_read_out(),.data_out(d91));
    BSPE pe92 (.clk(clk),.rst(rst),.k(k[79:72]), .q(d82),.pin(ps82),.psum(ps92),.valid_q(valid_q),.load_k(load_kc3), .left_valid(1'b1),.left_fifo_out(f91), .left_read(),.right_inread(1'b1),.fifo_out_right(f92), .fifo_read_out(),.data_out(d92));
    BSPE pe93 (.clk(clk),.rst(rst),.k(k[79:72]), .q(d83),.pin(ps83),.psum(ps93),.valid_q(valid_q),.load_k(load_kc4), .left_valid(1'b1),.left_fifo_out(f92), .left_read(),.right_inread(1'b1),.fifo_out_right(f93), .fifo_read_out(),.data_out(d93));
    BSPE pe94 (.clk(clk),.rst(rst),.k(k[79:72]), .q(d84),.pin(ps84),.psum(ps94),.valid_q(valid_q),.load_k(load_kc5), .left_valid(1'b1),.left_fifo_out(f93), .left_read(),.right_inread(1'b1),.fifo_out_right(f94), .fifo_read_out(),.data_out(d94));
    BSPE pe95 (.clk(clk),.rst(rst),.k(k[79:72]), .q(d85),.pin(ps85),.psum(ps95),.valid_q(valid_q),.load_k(load_kc6), .left_valid(1'b1),.left_fifo_out(f94), .left_read(),.right_inread(1'b1),.fifo_out_right(f95), .fifo_read_out(),.data_out(d95));
    BSPE pe96 (.clk(clk),.rst(rst),.k(k[79:72]), .q(d86),.pin(ps86),.psum(ps96),.valid_q(valid_q),.load_k(load_kc7), .left_valid(1'b1),.left_fifo_out(f95), .left_read(),.right_inread(1'b1),.fifo_out_right(f96), .fifo_read_out(),.data_out(d96));
    BSPE pe97 (.clk(clk),.rst(rst),.k(k[79:72]), .q(d87),.pin(ps87),.psum(ps97),.valid_q(valid_q),.load_k(load_kc8), .left_valid(1'b1),.left_fifo_out(f96), .left_read(),.right_inread(1'b1),.fifo_out_right(f97), .fifo_read_out(),.data_out(d97));
    BSPE pe98 (.clk(clk),.rst(rst),.k(k[79:72]), .q(d88),.pin(ps88),.psum(ps98),.valid_q(valid_q),.load_k(load_kc9), .left_valid(1'b1),.left_fifo_out(f97), .left_read(),.right_inread(1'b1),.fifo_out_right(f98), .fifo_read_out(),.data_out(d98));
    BSPE pe99 (.clk(clk),.rst(rst),.k(k[79:72]), .q(d89),.pin(ps89),.psum(ps99),.valid_q(valid_q),.load_k(load_kc10),.left_valid(1'b1),.left_fifo_out(f98), .left_read(),.right_inread(1'b1),.fifo_out_right(f99), .fifo_read_out(),.data_out(d99));
    BSPE pe910(.clk(clk),.rst(rst),.k(k[79:72]), .q(d810),.pin(ps810),.psum(ps910),.valid_q(valid_q),.load_k(load_kc11),.left_valid(1'b1),.left_fifo_out(f99), .left_read(),.right_inread(1'b1),.fifo_out_right(f910),.fifo_read_out(),.data_out(d910));
    BSPE pe911(.clk(clk),.rst(rst),.k(k[79:72]), .q(d811),.pin(ps811),.psum(ps911),.valid_q(valid_q),.load_k(load_kc12),.left_valid(1'b1),.left_fifo_out(f910),.left_read(),.right_inread(1'b1),.fifo_out_right(f911),.fifo_read_out(),.data_out(d911));
    BSPE pe912(.clk(clk),.rst(rst),.k(k[79:72]), .q(d812),.pin(ps812),.psum(ps912),.valid_q(valid_q),.load_k(load_kc13),.left_valid(1'b1),.left_fifo_out(f911),.left_read(),.right_inread(1'b1),.fifo_out_right(f912),.fifo_read_out(),.data_out(d912));
    BSPE pe913(.clk(clk),.rst(rst),.k(k[79:72]), .q(d813),.pin(ps813),.psum(ps913),.valid_q(valid_q),.load_k(load_kc14),.left_valid(1'b1),.left_fifo_out(f912),.left_read(),.right_inread(1'b1),.fifo_out_right(f913),.fifo_read_out(),.data_out(d913));
    BSPE pe914(.clk(clk),.rst(rst),.k(k[79:72]), .q(d814),.pin(ps814),.psum(ps914),.valid_q(valid_q),.load_k(load_kc15),.left_valid(1'b1),.left_fifo_out(f913),.left_read(),.right_inread(1'b1),.fifo_out_right(f914),.fifo_read_out(),.data_out(d914));
    BSPE pe915(.clk(clk),.rst(rst),.k(k[79:72]), .q(d815),.pin(ps815),.psum(ps915),.valid_q(valid_q),.load_k(load_kc16),.left_valid(1'b1),.left_fifo_out(f914),.left_read(),.right_inread(1'b1),.fifo_out_right(f915),.fifo_read_out(),.data_out(d915));

    // ---- ROW 10 ----
    BSPE pea0 (.clk(clk),.rst(rst),.k(k[87:80]), .q(d90),.pin(ps90),.psum(psa0),.valid_q(valid_q),.load_k(load_kc1), .left_valid(1'b1),.left_fifo_out(8'd0),.left_read(),.right_inread(1'b1),.fifo_out_right(fa0), .fifo_read_out(),.data_out(da0));
    BSPE pea1 (.clk(clk),.rst(rst),.k(k[87:80]), .q(d91),.pin(ps91),.psum(psa1),.valid_q(valid_q),.load_k(load_kc2), .left_valid(1'b1),.left_fifo_out(fa0), .left_read(),.right_inread(1'b1),.fifo_out_right(fa1), .fifo_read_out(),.data_out(da1));
    BSPE pea2 (.clk(clk),.rst(rst),.k(k[87:80]), .q(d92),.pin(ps92),.psum(psa2),.valid_q(valid_q),.load_k(load_kc3), .left_valid(1'b1),.left_fifo_out(fa1), .left_read(),.right_inread(1'b1),.fifo_out_right(fa2), .fifo_read_out(),.data_out(da2));
    BSPE pea3 (.clk(clk),.rst(rst),.k(k[87:80]), .q(d93),.pin(ps93),.psum(psa3),.valid_q(valid_q),.load_k(load_kc4), .left_valid(1'b1),.left_fifo_out(fa2), .left_read(),.right_inread(1'b1),.fifo_out_right(fa3), .fifo_read_out(),.data_out(da3));
    BSPE pea4 (.clk(clk),.rst(rst),.k(k[87:80]), .q(d94),.pin(ps94),.psum(psa4),.valid_q(valid_q),.load_k(load_kc5), .left_valid(1'b1),.left_fifo_out(fa3), .left_read(),.right_inread(1'b1),.fifo_out_right(fa4), .fifo_read_out(),.data_out(da4));
    BSPE pea5 (.clk(clk),.rst(rst),.k(k[87:80]), .q(d95),.pin(ps95),.psum(psa5),.valid_q(valid_q),.load_k(load_kc6), .left_valid(1'b1),.left_fifo_out(fa4), .left_read(),.right_inread(1'b1),.fifo_out_right(fa5), .fifo_read_out(),.data_out(da5));
    BSPE pea6 (.clk(clk),.rst(rst),.k(k[87:80]), .q(d96),.pin(ps96),.psum(psa6),.valid_q(valid_q),.load_k(load_kc7), .left_valid(1'b1),.left_fifo_out(fa5), .left_read(),.right_inread(1'b1),.fifo_out_right(fa6), .fifo_read_out(),.data_out(da6));
    BSPE pea7 (.clk(clk),.rst(rst),.k(k[87:80]), .q(d97),.pin(ps97),.psum(psa7),.valid_q(valid_q),.load_k(load_kc8), .left_valid(1'b1),.left_fifo_out(fa6), .left_read(),.right_inread(1'b1),.fifo_out_right(fa7), .fifo_read_out(),.data_out(da7));
    BSPE pea8 (.clk(clk),.rst(rst),.k(k[87:80]), .q(d98),.pin(ps98),.psum(psa8),.valid_q(valid_q),.load_k(load_kc9), .left_valid(1'b1),.left_fifo_out(fa7), .left_read(),.right_inread(1'b1),.fifo_out_right(fa8), .fifo_read_out(),.data_out(da8));
    BSPE pea9 (.clk(clk),.rst(rst),.k(k[87:80]), .q(d99),.pin(ps99),.psum(psa9),.valid_q(valid_q),.load_k(load_kc10),.left_valid(1'b1),.left_fifo_out(fa8), .left_read(),.right_inread(1'b1),.fifo_out_right(fa9), .fifo_read_out(),.data_out(da9));
    BSPE pea10(.clk(clk),.rst(rst),.k(k[87:80]), .q(d910),.pin(ps910),.psum(psa10),.valid_q(valid_q),.load_k(load_kc11),.left_valid(1'b1),.left_fifo_out(fa9), .left_read(),.right_inread(1'b1),.fifo_out_right(fa10),.fifo_read_out(),.data_out(da10));
    BSPE pea11(.clk(clk),.rst(rst),.k(k[87:80]), .q(d911),.pin(ps911),.psum(psa11),.valid_q(valid_q),.load_k(load_kc12),.left_valid(1'b1),.left_fifo_out(fa10),.left_read(),.right_inread(1'b1),.fifo_out_right(fa11),.fifo_read_out(),.data_out(da11));
    BSPE pea12(.clk(clk),.rst(rst),.k(k[87:80]), .q(d912),.pin(ps912),.psum(psa12),.valid_q(valid_q),.load_k(load_kc13),.left_valid(1'b1),.left_fifo_out(fa11),.left_read(),.right_inread(1'b1),.fifo_out_right(fa12),.fifo_read_out(),.data_out(da12));
    BSPE pea13(.clk(clk),.rst(rst),.k(k[87:80]), .q(d913),.pin(ps913),.psum(psa13),.valid_q(valid_q),.load_k(load_kc14),.left_valid(1'b1),.left_fifo_out(fa12),.left_read(),.right_inread(1'b1),.fifo_out_right(fa13),.fifo_read_out(),.data_out(da13));
    BSPE pea14(.clk(clk),.rst(rst),.k(k[87:80]), .q(d914),.pin(ps914),.psum(psa14),.valid_q(valid_q),.load_k(load_kc15),.left_valid(1'b1),.left_fifo_out(fa13),.left_read(),.right_inread(1'b1),.fifo_out_right(fa14),.fifo_read_out(),.data_out(da14));
    BSPE pea15(.clk(clk),.rst(rst),.k(k[87:80]), .q(d915),.pin(ps915),.psum(psa15),.valid_q(valid_q),.load_k(load_kc16),.left_valid(1'b1),.left_fifo_out(fa14),.left_read(),.right_inread(1'b1),.fifo_out_right(fa15),.fifo_read_out(),.data_out(da15));

    // ---- ROW 11 ----
    BSPE peb0 (.clk(clk),.rst(rst),.k(k[95:88]), .q(da0),.pin(psa0),.psum(psb0),.valid_q(valid_q),.load_k(load_kc1), .left_valid(1'b1),.left_fifo_out(8'd0),.left_read(),.right_inread(1'b1),.fifo_out_right(fb0), .fifo_read_out(),.data_out(db0));
    BSPE peb1 (.clk(clk),.rst(rst),.k(k[95:88]), .q(da1),.pin(psa1),.psum(psb1),.valid_q(valid_q),.load_k(load_kc2), .left_valid(1'b1),.left_fifo_out(fb0), .left_read(),.right_inread(1'b1),.fifo_out_right(fb1), .fifo_read_out(),.data_out(db1));
    BSPE peb2 (.clk(clk),.rst(rst),.k(k[95:88]), .q(da2),.pin(psa2),.psum(psb2),.valid_q(valid_q),.load_k(load_kc3), .left_valid(1'b1),.left_fifo_out(fb1), .left_read(),.right_inread(1'b1),.fifo_out_right(fb2), .fifo_read_out(),.data_out(db2));
    BSPE peb3 (.clk(clk),.rst(rst),.k(k[95:88]), .q(da3),.pin(psa3),.psum(psb3),.valid_q(valid_q),.load_k(load_kc4), .left_valid(1'b1),.left_fifo_out(fb2), .left_read(),.right_inread(1'b1),.fifo_out_right(fb3), .fifo_read_out(),.data_out(db3));
    BSPE peb4 (.clk(clk),.rst(rst),.k(k[95:88]), .q(da4),.pin(psa4),.psum(psb4),.valid_q(valid_q),.load_k(load_kc5), .left_valid(1'b1),.left_fifo_out(fb3), .left_read(),.right_inread(1'b1),.fifo_out_right(fb4), .fifo_read_out(),.data_out(db4));
    BSPE peb5 (.clk(clk),.rst(rst),.k(k[95:88]), .q(da5),.pin(psa5),.psum(psb5),.valid_q(valid_q),.load_k(load_kc6), .left_valid(1'b1),.left_fifo_out(fb4), .left_read(),.right_inread(1'b1),.fifo_out_right(fb5), .fifo_read_out(),.data_out(db5));
    BSPE peb6 (.clk(clk),.rst(rst),.k(k[95:88]), .q(da6),.pin(psa6),.psum(psb6),.valid_q(valid_q),.load_k(load_kc7), .left_valid(1'b1),.left_fifo_out(fb5), .left_read(),.right_inread(1'b1),.fifo_out_right(fb6), .fifo_read_out(),.data_out(db6));
    BSPE peb7 (.clk(clk),.rst(rst),.k(k[95:88]), .q(da7),.pin(psa7),.psum(psb7),.valid_q(valid_q),.load_k(load_kc8), .left_valid(1'b1),.left_fifo_out(fb6), .left_read(),.right_inread(1'b1),.fifo_out_right(fb7), .fifo_read_out(),.data_out(db7));
    BSPE peb8 (.clk(clk),.rst(rst),.k(k[95:88]), .q(da8),.pin(psa8),.psum(psb8),.valid_q(valid_q),.load_k(load_kc9), .left_valid(1'b1),.left_fifo_out(fb7), .left_read(),.right_inread(1'b1),.fifo_out_right(fb8), .fifo_read_out(),.data_out(db8));
    BSPE peb9 (.clk(clk),.rst(rst),.k(k[95:88]), .q(da9),.pin(psa9),.psum(psb9),.valid_q(valid_q),.load_k(load_kc10),.left_valid(1'b1),.left_fifo_out(fb8), .left_read(),.right_inread(1'b1),.fifo_out_right(fb9), .fifo_read_out(),.data_out(db9));
    BSPE peb10(.clk(clk),.rst(rst),.k(k[95:88]), .q(da10),.pin(psa10),.psum(psb10),.valid_q(valid_q),.load_k(load_kc11),.left_valid(1'b1),.left_fifo_out(fb9), .left_read(),.right_inread(1'b1),.fifo_out_right(fb10),.fifo_read_out(),.data_out(db10));
    BSPE peb11(.clk(clk),.rst(rst),.k(k[95:88]), .q(da11),.pin(psa11),.psum(psb11),.valid_q(valid_q),.load_k(load_kc12),.left_valid(1'b1),.left_fifo_out(fb10),.left_read(),.right_inread(1'b1),.fifo_out_right(fb11),.fifo_read_out(),.data_out(db11));
    BSPE peb12(.clk(clk),.rst(rst),.k(k[95:88]), .q(da12),.pin(psa12),.psum(psb12),.valid_q(valid_q),.load_k(load_kc13),.left_valid(1'b1),.left_fifo_out(fb11),.left_read(),.right_inread(1'b1),.fifo_out_right(fb12),.fifo_read_out(),.data_out(db12));
    BSPE peb13(.clk(clk),.rst(rst),.k(k[95:88]), .q(da13),.pin(psa13),.psum(psb13),.valid_q(valid_q),.load_k(load_kc14),.left_valid(1'b1),.left_fifo_out(fb12),.left_read(),.right_inread(1'b1),.fifo_out_right(fb13),.fifo_read_out(),.data_out(db13));
    BSPE peb14(.clk(clk),.rst(rst),.k(k[95:88]), .q(da14),.pin(psa14),.psum(psb14),.valid_q(valid_q),.load_k(load_kc15),.left_valid(1'b1),.left_fifo_out(fb13),.left_read(),.right_inread(1'b1),.fifo_out_right(fb14),.fifo_read_out(),.data_out(db14));
    BSPE peb15(.clk(clk),.rst(rst),.k(k[95:88]), .q(da15),.pin(psa15),.psum(psb15),.valid_q(valid_q),.load_k(load_kc16),.left_valid(1'b1),.left_fifo_out(fb14),.left_read(),.right_inread(1'b1),.fifo_out_right(fb15),.fifo_read_out(),.data_out(db15));

    // ---- ROW 12 ----
    BSPE pec0 (.clk(clk),.rst(rst),.k(k[103:96]),.q(db0),.pin(psb0),.psum(psc0),.valid_q(valid_q),.load_k(load_kc1), .left_valid(1'b1),.left_fifo_out(8'd0),.left_read(),.right_inread(1'b1),.fifo_out_right(fc0), .fifo_read_out(),.data_out(dc0));
    BSPE pec1 (.clk(clk),.rst(rst),.k(k[103:96]),.q(db1),.pin(psb1),.psum(psc1),.valid_q(valid_q),.load_k(load_kc2), .left_valid(1'b1),.left_fifo_out(fc0), .left_read(),.right_inread(1'b1),.fifo_out_right(fc1), .fifo_read_out(),.data_out(dc1));
    BSPE pec2 (.clk(clk),.rst(rst),.k(k[103:96]),.q(db2),.pin(psb2),.psum(psc2),.valid_q(valid_q),.load_k(load_kc3), .left_valid(1'b1),.left_fifo_out(fc1), .left_read(),.right_inread(1'b1),.fifo_out_right(fc2), .fifo_read_out(),.data_out(dc2));
    BSPE pec3 (.clk(clk),.rst(rst),.k(k[103:96]),.q(db3),.pin(psb3),.psum(psc3),.valid_q(valid_q),.load_k(load_kc4), .left_valid(1'b1),.left_fifo_out(fc2), .left_read(),.right_inread(1'b1),.fifo_out_right(fc3), .fifo_read_out(),.data_out(dc3));
    BSPE pec4 (.clk(clk),.rst(rst),.k(k[103:96]),.q(db4),.pin(psb4),.psum(psc4),.valid_q(valid_q),.load_k(load_kc5), .left_valid(1'b1),.left_fifo_out(fc3), .left_read(),.right_inread(1'b1),.fifo_out_right(fc4), .fifo_read_out(),.data_out(dc4));
    BSPE pec5 (.clk(clk),.rst(rst),.k(k[103:96]),.q(db5),.pin(psb5),.psum(psc5),.valid_q(valid_q),.load_k(load_kc6), .left_valid(1'b1),.left_fifo_out(fc4), .left_read(),.right_inread(1'b1),.fifo_out_right(fc5), .fifo_read_out(),.data_out(dc5));
    BSPE pec6 (.clk(clk),.rst(rst),.k(k[103:96]),.q(db6),.pin(psb6),.psum(psc6),.valid_q(valid_q),.load_k(load_kc7), .left_valid(1'b1),.left_fifo_out(fc5), .left_read(),.right_inread(1'b1),.fifo_out_right(fc6), .fifo_read_out(),.data_out(dc6));
    BSPE pec7 (.clk(clk),.rst(rst),.k(k[103:96]),.q(db7),.pin(psb7),.psum(psc7),.valid_q(valid_q),.load_k(load_kc8), .left_valid(1'b1),.left_fifo_out(fc6), .left_read(),.right_inread(1'b1),.fifo_out_right(fc7), .fifo_read_out(),.data_out(dc7));
    BSPE pec8 (.clk(clk),.rst(rst),.k(k[103:96]),.q(db8),.pin(psb8),.psum(psc8),.valid_q(valid_q),.load_k(load_kc9), .left_valid(1'b1),.left_fifo_out(fc7), .left_read(),.right_inread(1'b1),.fifo_out_right(fc8), .fifo_read_out(),.data_out(dc8));
    BSPE pec9 (.clk(clk),.rst(rst),.k(k[103:96]),.q(db9),.pin(psb9),.psum(psc9),.valid_q(valid_q),.load_k(load_kc10),.left_valid(1'b1),.left_fifo_out(fc8), .left_read(),.right_inread(1'b1),.fifo_out_right(fc9), .fifo_read_out(),.data_out(dc9));
    BSPE pec10(.clk(clk),.rst(rst),.k(k[103:96]),.q(db10),.pin(psb10),.psum(psc10),.valid_q(valid_q),.load_k(load_kc11),.left_valid(1'b1),.left_fifo_out(fc9), .left_read(),.right_inread(1'b1),.fifo_out_right(fc10),.fifo_read_out(),.data_out(dc10));
    BSPE pec11(.clk(clk),.rst(rst),.k(k[103:96]),.q(db11),.pin(psb11),.psum(psc11),.valid_q(valid_q),.load_k(load_kc12),.left_valid(1'b1),.left_fifo_out(fc10),.left_read(),.right_inread(1'b1),.fifo_out_right(fc11),.fifo_read_out(),.data_out(dc11));
    BSPE pec12(.clk(clk),.rst(rst),.k(k[103:96]),.q(db12),.pin(psb12),.psum(psc12),.valid_q(valid_q),.load_k(load_kc13),.left_valid(1'b1),.left_fifo_out(fc11),.left_read(),.right_inread(1'b1),.fifo_out_right(fc12),.fifo_read_out(),.data_out(dc12));
    BSPE pec13(.clk(clk),.rst(rst),.k(k[103:96]),.q(db13),.pin(psb13),.psum(psc13),.valid_q(valid_q),.load_k(load_kc14),.left_valid(1'b1),.left_fifo_out(fc12),.left_read(),.right_inread(1'b1),.fifo_out_right(fc13),.fifo_read_out(),.data_out(dc13));
    BSPE pec14(.clk(clk),.rst(rst),.k(k[103:96]),.q(db14),.pin(psb14),.psum(psc14),.valid_q(valid_q),.load_k(load_kc15),.left_valid(1'b1),.left_fifo_out(fc13),.left_read(),.right_inread(1'b1),.fifo_out_right(fc14),.fifo_read_out(),.data_out(dc14));
    BSPE pec15(.clk(clk),.rst(rst),.k(k[103:96]),.q(db15),.pin(psb15),.psum(psc15),.valid_q(valid_q),.load_k(load_kc16),.left_valid(1'b1),.left_fifo_out(fc14),.left_read(),.right_inread(1'b1),.fifo_out_right(fc15),.fifo_read_out(),.data_out(dc15));

    // ---- ROW 13 ----
    BSPE ped0 (.clk(clk),.rst(rst),.k(k[111:104]),.q(dc0),.pin(psc0),.psum(psd0),.valid_q(valid_q),.load_k(load_kc1), .left_valid(1'b1),.left_fifo_out(8'd0),.left_read(),.right_inread(1'b1),.fifo_out_right(fd0), .fifo_read_out(),.data_out(dd0));
    BSPE ped1 (.clk(clk),.rst(rst),.k(k[111:104]),.q(dc1),.pin(psc1),.psum(psd1),.valid_q(valid_q),.load_k(load_kc2), .left_valid(1'b1),.left_fifo_out(fd0), .left_read(),.right_inread(1'b1),.fifo_out_right(fd1), .fifo_read_out(),.data_out(dd1));
    BSPE ped2 (.clk(clk),.rst(rst),.k(k[111:104]),.q(dc2),.pin(psc2),.psum(psd2),.valid_q(valid_q),.load_k(load_kc3), .left_valid(1'b1),.left_fifo_out(fd1), .left_read(),.right_inread(1'b1),.fifo_out_right(fd2), .fifo_read_out(),.data_out(dd2));
    BSPE ped3 (.clk(clk),.rst(rst),.k(k[111:104]),.q(dc3),.pin(psc3),.psum(psd3),.valid_q(valid_q),.load_k(load_kc4), .left_valid(1'b1),.left_fifo_out(fd2), .left_read(),.right_inread(1'b1),.fifo_out_right(fd3), .fifo_read_out(),.data_out(dd3));
    BSPE ped4 (.clk(clk),.rst(rst),.k(k[111:104]),.q(dc4),.pin(psc4),.psum(psd4),.valid_q(valid_q),.load_k(load_kc5), .left_valid(1'b1),.left_fifo_out(fd3), .left_read(),.right_inread(1'b1),.fifo_out_right(fd4), .fifo_read_out(),.data_out(dd4));
    BSPE ped5 (.clk(clk),.rst(rst),.k(k[111:104]),.q(dc5),.pin(psc5),.psum(psd5),.valid_q(valid_q),.load_k(load_kc6), .left_valid(1'b1),.left_fifo_out(fd4), .left_read(),.right_inread(1'b1),.fifo_out_right(fd5), .fifo_read_out(),.data_out(dd5));
    BSPE ped6 (.clk(clk),.rst(rst),.k(k[111:104]),.q(dc6),.pin(psc6),.psum(psd6),.valid_q(valid_q),.load_k(load_kc7), .left_valid(1'b1),.left_fifo_out(fd5), .left_read(),.right_inread(1'b1),.fifo_out_right(fd6), .fifo_read_out(),.data_out(dd6));
    BSPE ped7 (.clk(clk),.rst(rst),.k(k[111:104]),.q(dc7),.pin(psc7),.psum(psd7),.valid_q(valid_q),.load_k(load_kc8), .left_valid(1'b1),.left_fifo_out(fd6), .left_read(),.right_inread(1'b1),.fifo_out_right(fd7), .fifo_read_out(),.data_out(dd7));
    BSPE ped8 (.clk(clk),.rst(rst),.k(k[111:104]),.q(dc8),.pin(psc8),.psum(psd8),.valid_q(valid_q),.load_k(load_kc9), .left_valid(1'b1),.left_fifo_out(fd7), .left_read(),.right_inread(1'b1),.fifo_out_right(fd8), .fifo_read_out(),.data_out(dd8));
    BSPE ped9 (.clk(clk),.rst(rst),.k(k[111:104]),.q(dc9),.pin(psc9),.psum(psd9),.valid_q(valid_q),.load_k(load_kc10),.left_valid(1'b1),.left_fifo_out(fd8), .left_read(),.right_inread(1'b1),.fifo_out_right(fd9), .fifo_read_out(),.data_out(dd9));
    BSPE ped10(.clk(clk),.rst(rst),.k(k[111:104]),.q(dc10),.pin(psc10),.psum(psd10),.valid_q(valid_q),.load_k(load_kc11),.left_valid(1'b1),.left_fifo_out(fd9), .left_read(),.right_inread(1'b1),.fifo_out_right(fd10),.fifo_read_out(),.data_out(dd10));
    BSPE ped11(.clk(clk),.rst(rst),.k(k[111:104]),.q(dc11),.pin(psc11),.psum(psd11),.valid_q(valid_q),.load_k(load_kc12),.left_valid(1'b1),.left_fifo_out(fd10),.left_read(),.right_inread(1'b1),.fifo_out_right(fd11),.fifo_read_out(),.data_out(dd11));
    BSPE ped12(.clk(clk),.rst(rst),.k(k[111:104]),.q(dc12),.pin(psc12),.psum(psd12),.valid_q(valid_q),.load_k(load_kc13),.left_valid(1'b1),.left_fifo_out(fd11),.left_read(),.right_inread(1'b1),.fifo_out_right(fd12),.fifo_read_out(),.data_out(dd12));
    BSPE ped13(.clk(clk),.rst(rst),.k(k[111:104]),.q(dc13),.pin(psc13),.psum(psd13),.valid_q(valid_q),.load_k(load_kc14),.left_valid(1'b1),.left_fifo_out(fd12),.left_read(),.right_inread(1'b1),.fifo_out_right(fd13),.fifo_read_out(),.data_out(dd13));
    BSPE ped14(.clk(clk),.rst(rst),.k(k[111:104]),.q(dc14),.pin(psc14),.psum(psd14),.valid_q(valid_q),.load_k(load_kc15),.left_valid(1'b1),.left_fifo_out(fd13),.left_read(),.right_inread(1'b1),.fifo_out_right(fd14),.fifo_read_out(),.data_out(dd14));
    BSPE ped15(.clk(clk),.rst(rst),.k(k[111:104]),.q(dc15),.pin(psc15),.psum(psd15),.valid_q(valid_q),.load_k(load_kc16),.left_valid(1'b1),.left_fifo_out(fd14),.left_read(),.right_inread(1'b1),.fifo_out_right(fd15),.fifo_read_out(),.data_out(dd15));

    // ---- ROW 14 ----
    BSPE pee0 (.clk(clk),.rst(rst),.k(k[119:112]),.q(dd0),.pin(psd0),.psum(pse0),.valid_q(valid_q),.load_k(load_kc1), .left_valid(1'b1),.left_fifo_out(8'd0),.left_read(),.right_inread(1'b1),.fifo_out_right(fe0), .fifo_read_out(),.data_out(de0));
    BSPE pee1 (.clk(clk),.rst(rst),.k(k[119:112]),.q(dd1),.pin(psd1),.psum(pse1),.valid_q(valid_q),.load_k(load_kc2), .left_valid(1'b1),.left_fifo_out(fe0), .left_read(),.right_inread(1'b1),.fifo_out_right(fe1), .fifo_read_out(),.data_out(de1));
    BSPE pee2 (.clk(clk),.rst(rst),.k(k[119:112]),.q(dd2),.pin(psd2),.psum(pse2),.valid_q(valid_q),.load_k(load_kc3), .left_valid(1'b1),.left_fifo_out(fe1), .left_read(),.right_inread(1'b1),.fifo_out_right(fe2), .fifo_read_out(),.data_out(de2));
    BSPE pee3 (.clk(clk),.rst(rst),.k(k[119:112]),.q(dd3),.pin(psd3),.psum(pse3),.valid_q(valid_q),.load_k(load_kc4), .left_valid(1'b1),.left_fifo_out(fe2), .left_read(),.right_inread(1'b1),.fifo_out_right(fe3), .fifo_read_out(),.data_out(de3));
    BSPE pee4 (.clk(clk),.rst(rst),.k(k[119:112]),.q(dd4),.pin(psd4),.psum(pse4),.valid_q(valid_q),.load_k(load_kc5), .left_valid(1'b1),.left_fifo_out(fe3), .left_read(),.right_inread(1'b1),.fifo_out_right(fe4), .fifo_read_out(),.data_out(de4));
    BSPE pee5 (.clk(clk),.rst(rst),.k(k[119:112]),.q(dd5),.pin(psd5),.psum(pse5),.valid_q(valid_q),.load_k(load_kc6), .left_valid(1'b1),.left_fifo_out(fe4), .left_read(),.right_inread(1'b1),.fifo_out_right(fe5), .fifo_read_out(),.data_out(de5));
    BSPE pee6 (.clk(clk),.rst(rst),.k(k[119:112]),.q(dd6),.pin(psd6),.psum(pse6),.valid_q(valid_q),.load_k(load_kc7), .left_valid(1'b1),.left_fifo_out(fe5), .left_read(),.right_inread(1'b1),.fifo_out_right(fe6), .fifo_read_out(),.data_out(de6));
    BSPE pee7 (.clk(clk),.rst(rst),.k(k[119:112]),.q(dd7),.pin(psd7),.psum(pse7),.valid_q(valid_q),.load_k(load_kc8), .left_valid(1'b1),.left_fifo_out(fe6), .left_read(),.right_inread(1'b1),.fifo_out_right(fe7), .fifo_read_out(),.data_out(de7));
    BSPE pee8 (.clk(clk),.rst(rst),.k(k[119:112]),.q(dd8),.pin(psd8),.psum(pse8),.valid_q(valid_q),.load_k(load_kc9), .left_valid(1'b1),.left_fifo_out(fe7), .left_read(),.right_inread(1'b1),.fifo_out_right(fe8), .fifo_read_out(),.data_out(de8));
    BSPE pee9 (.clk(clk),.rst(rst),.k(k[119:112]),.q(dd9),.pin(psd9),.psum(pse9),.valid_q(valid_q),.load_k(load_kc10),.left_valid(1'b1),.left_fifo_out(fe8), .left_read(),.right_inread(1'b1),.fifo_out_right(fe9), .fifo_read_out(),.data_out(de9));
    BSPE pee10(.clk(clk),.rst(rst),.k(k[119:112]),.q(dd10),.pin(psd10),.psum(pse10),.valid_q(valid_q),.load_k(load_kc11),.left_valid(1'b1),.left_fifo_out(fe9), .left_read(),.right_inread(1'b1),.fifo_out_right(fe10),.fifo_read_out(),.data_out(de10));
    BSPE pee11(.clk(clk),.rst(rst),.k(k[119:112]),.q(dd11),.pin(psd11),.psum(pse11),.valid_q(valid_q),.load_k(load_kc12),.left_valid(1'b1),.left_fifo_out(fe10),.left_read(),.right_inread(1'b1),.fifo_out_right(fe11),.fifo_read_out(),.data_out(de11));
    BSPE pee12(.clk(clk),.rst(rst),.k(k[119:112]),.q(dd12),.pin(psd12),.psum(pse12),.valid_q(valid_q),.load_k(load_kc13),.left_valid(1'b1),.left_fifo_out(fe11),.left_read(),.right_inread(1'b1),.fifo_out_right(fe12),.fifo_read_out(),.data_out(de12));
    BSPE pee13(.clk(clk),.rst(rst),.k(k[119:112]),.q(dd13),.pin(psd13),.psum(pse13),.valid_q(valid_q),.load_k(load_kc14),.left_valid(1'b1),.left_fifo_out(fe12),.left_read(),.right_inread(1'b1),.fifo_out_right(fe13),.fifo_read_out(),.data_out(de13));
    BSPE pee14(.clk(clk),.rst(rst),.k(k[119:112]),.q(dd14),.pin(psd14),.psum(pse14),.valid_q(valid_q),.load_k(load_kc15),.left_valid(1'b1),.left_fifo_out(fe13),.left_read(),.right_inread(1'b1),.fifo_out_right(fe14),.fifo_read_out(),.data_out(de14));
    BSPE pee15(.clk(clk),.rst(rst),.k(k[119:112]),.q(dd15),.pin(psd15),.psum(pse15),.valid_q(valid_q),.load_k(load_kc16),.left_valid(1'b1),.left_fifo_out(fe14),.left_read(),.right_inread(1'b1),.fifo_out_right(fe15),.fifo_read_out(),.data_out(de15));

    // ---- ROW 15 ----
    BSPE pef0 (.clk(clk),.rst(rst),.k(k[127:120]),.q(de0),.pin(pse0),.psum(psf0),.valid_q(valid_q),.load_k(load_kc1), .left_valid(1'b1),.left_fifo_out(8'd0),.left_read(),.right_inread(1'b1),.fifo_out_right(ff0), .fifo_read_out(),.data_out());
    BSPE pef1 (.clk(clk),.rst(rst),.k(k[127:120]),.q(de1),.pin(pse1),.psum(psf1),.valid_q(valid_q),.load_k(load_kc2), .left_valid(1'b1),.left_fifo_out(ff0), .left_read(),.right_inread(1'b1),.fifo_out_right(ff1), .fifo_read_out(),.data_out());
    BSPE pef2 (.clk(clk),.rst(rst),.k(k[127:120]),.q(de2),.pin(pse2),.psum(psf2),.valid_q(valid_q),.load_k(load_kc3), .left_valid(1'b1),.left_fifo_out(ff1), .left_read(),.right_inread(1'b1),.fifo_out_right(ff2), .fifo_read_out(),.data_out());
    BSPE pef3 (.clk(clk),.rst(rst),.k(k[127:120]),.q(de3),.pin(pse3),.psum(psf3),.valid_q(valid_q),.load_k(load_kc4), .left_valid(1'b1),.left_fifo_out(ff2), .left_read(),.right_inread(1'b1),.fifo_out_right(ff3), .fifo_read_out(),.data_out());
    BSPE pef4 (.clk(clk),.rst(rst),.k(k[127:120]),.q(de4),.pin(pse4),.psum(psf4),.valid_q(valid_q),.load_k(load_kc5), .left_valid(1'b1),.left_fifo_out(ff3), .left_read(),.right_inread(1'b1),.fifo_out_right(ff4), .fifo_read_out(),.data_out());
    BSPE pef5 (.clk(clk),.rst(rst),.k(k[127:120]),.q(de5),.pin(pse5),.psum(psf5),.valid_q(valid_q),.load_k(load_kc6), .left_valid(1'b1),.left_fifo_out(ff4), .left_read(),.right_inread(1'b1),.fifo_out_right(ff5), .fifo_read_out(),.data_out());
    BSPE pef6 (.clk(clk),.rst(rst),.k(k[127:120]),.q(de6),.pin(pse6),.psum(psf6),.valid_q(valid_q),.load_k(load_kc7), .left_valid(1'b1),.left_fifo_out(ff5), .left_read(),.right_inread(1'b1),.fifo_out_right(ff6), .fifo_read_out(),.data_out());
    BSPE pef7 (.clk(clk),.rst(rst),.k(k[127:120]),.q(de7),.pin(pse7),.psum(psf7),.valid_q(valid_q),.load_k(load_kc8), .left_valid(1'b1),.left_fifo_out(ff6), .left_read(),.right_inread(1'b1),.fifo_out_right(ff7), .fifo_read_out(),.data_out());
    BSPE pef8 (.clk(clk),.rst(rst),.k(k[127:120]),.q(de8),.pin(pse8),.psum(psf8),.valid_q(valid_q),.load_k(load_kc9), .left_valid(1'b1),.left_fifo_out(ff7), .left_read(),.right_inread(1'b1),.fifo_out_right(ff8), .fifo_read_out(),.data_out());
    BSPE pef9 (.clk(clk),.rst(rst),.k(k[127:120]),.q(de9),.pin(pse9),.psum(psf9),.valid_q(valid_q),.load_k(load_kc10),.left_valid(1'b1),.left_fifo_out(ff8), .left_read(),.right_inread(1'b1),.fifo_out_right(ff9), .fifo_read_out(),.data_out());
    BSPE pef10(.clk(clk),.rst(rst),.k(k[127:120]),.q(de10),.pin(pse10),.psum(psf10),.valid_q(valid_q),.load_k(load_kc11),.left_valid(1'b1),.left_fifo_out(ff9), .left_read(),.right_inread(1'b1),.fifo_out_right(ff10),.fifo_read_out(),.data_out());
    BSPE pef11(.clk(clk),.rst(rst),.k(k[127:120]),.q(de11),.pin(pse11),.psum(psf11),.valid_q(valid_q),.load_k(load_kc12),.left_valid(1'b1),.left_fifo_out(ff10),.left_read(),.right_inread(1'b1),.fifo_out_right(ff11),.fifo_read_out(),.data_out());
    BSPE pef12(.clk(clk),.rst(rst),.k(k[127:120]),.q(de12),.pin(pse12),.psum(psf12),.valid_q(valid_q),.load_k(load_kc13),.left_valid(1'b1),.left_fifo_out(ff11),.left_read(),.right_inread(1'b1),.fifo_out_right(ff12),.fifo_read_out(),.data_out());
    BSPE pef13(.clk(clk),.rst(rst),.k(k[127:120]),.q(de13),.pin(pse13),.psum(psf13),.valid_q(valid_q),.load_k(load_kc14),.left_valid(1'b1),.left_fifo_out(ff12),.left_read(),.right_inread(1'b1),.fifo_out_right(ff13),.fifo_read_out(),.data_out());
    BSPE pef14(.clk(clk),.rst(rst),.k(k[127:120]),.q(de14),.pin(pse14),.psum(psf14),.valid_q(valid_q),.load_k(load_kc15),.left_valid(1'b1),.left_fifo_out(ff13),.left_read(),.right_inread(1'b1),.fifo_out_right(ff14),.fifo_read_out(),.data_out());
    BSPE pef15(.clk(clk),.rst(rst),.k(k[127:120]),.q(de15),.pin(pse15),.psum(psf15),.valid_q(valid_q),.load_k(load_kc16),.left_valid(1'b1),.left_fifo_out(ff14),.left_read(),.right_inread(1'b1),.fifo_out_right(ff15),.fifo_read_out(),.data_out());

    // =========================================================
    // Outputs: rightmost fifo_out_right per row
    // =========================================================
    assign e1  = f015;   assign e2  = f115;   assign e3  = f215;   assign e4  = f315;
    assign e5  = f415;   assign e6  = f515;   assign e7  = f615;   assign e8  = f715;
    assign e9  = f815;   assign e10 = f915;   assign e11 = fa15;   assign e12 = fb15;
    assign e13 = fc15;   assign e14 = fd15;   assign e15 = fe15;   assign e16 = ff15;

endmodule