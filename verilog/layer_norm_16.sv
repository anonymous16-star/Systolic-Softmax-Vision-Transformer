`timescale 1ns / 1ps


module layer_norm_16 (
    input  wire [127:0] x_in,      
    input  wire [7:0]   gamma,     
    input  wire [7:0]   beta,      
    output wire [127:0] y_out      
);
 
    wire signed [11:0] sum_x;
    wire signed [7:0]  xi [0:15];

    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1)
            assign xi[gi] = x_in[gi*8 +: 8];
    endgenerate

    
    wire signed [11:0] xi_ext [0:15];
    generate
        for (gi = 0; gi < 16; gi = gi + 1)
            assign xi_ext[gi] = {{4{xi[gi][7]}}, xi[gi]};
    endgenerate

    wire signed [11:0] partial_sum [0:15];
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : GEN_PSUM
            if (gi == 0)
                assign partial_sum[0] = xi_ext[0];
            else
                assign partial_sum[gi] = partial_sum[gi-1] + xi_ext[gi];
        end
    endgenerate

    assign sum_x = partial_sum[15];

    
    wire signed [7:0] mean = sum_x[11:4];  

    wire signed [7:0] centered [0:15];
    generate
        for (gi = 0; gi < 16; gi = gi + 1)
            assign centered[gi] = xi[gi] - mean;
    endgenerate
 
    wire [7:0]  sq [0:15];
    wire [11:0] sq_sum_partial [0:15];

    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : GEN_SQ
            
            wire [3:0] mag = centered[gi][7] ?
                             (~centered[gi][3:0] + 4'd1) : centered[gi][3:0];
            assign sq[gi] = {2'b00, mag, mag[3:0]};   
        end
    endgenerate

    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : GEN_SQSUM
            if (gi == 0)
                assign sq_sum_partial[0] = {4'b0, sq[0]};
            else
                assign sq_sum_partial[gi] = sq_sum_partial[gi-1] + {4'b0, sq[gi]};
        end
    endgenerate

    wire [7:0] var_approx = sq_sum_partial[15][11:4];  
    
    reg [7:0] isqrt;
    always @(*) begin
        case (var_approx[7:5])   
            3'd0: isqrt = 8'd128;  
            3'd1: isqrt = 8'd91;   
            3'd2: isqrt = 8'd64;   
            3'd3: isqrt = 8'd52;   
            3'd4: isqrt = 8'd45;   
            3'd5: isqrt = 8'd40;   
            3'd6: isqrt = 8'd36;   
            3'd7: isqrt = 8'd32;   
        endcase
    end

    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : GEN_OUT
            wire signed [15:0] prod;
            wire signed [7:0]  scaled;
            wire signed [8:0]  with_beta;
            wire signed [7:0]  saturated;

            
            assign prod      = $signed(centered[gi]) * $signed({1'b0, isqrt});
            assign scaled    = prod[14:7];           

          
            assign with_beta = {scaled[7], scaled} + {{1{beta[7]}}, beta};

            assign saturated = (with_beta >  9'sd127)  ? 8'sh7F :
                               (with_beta < -9'sd128)  ? 8'sh80 :
                                with_beta[7:0];

            assign y_out[gi*8 +: 8] = saturated;
        end
    endgenerate

endmodule
