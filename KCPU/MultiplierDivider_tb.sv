`timescale 1ns/1ns

module MultiplierDivider_tb ();

logic clk, rst, enableDiv, isSignedDiv;
logic[31:0] divA, divB, hi, lo;

initial begin
    clk = 0;
    rst = 1;
    #20 rst = 0;
    divA = 32'd50000000;
    divB = 32'd1234;
    enableDiv = 1;
    isSignedDiv = 0;
    #20 enableDiv = 0;
    #240 

    rst = 1;
    #20 rst = 0;
    isSignedDiv = 1;
    enableDiv = 1;
    #20 enableDiv = 0;
    #240 

    rst = 1;
    #20 rst = 0;
    divA = 32'd50000000;
    divB = -32'd1234;
    enableDiv = 1;
    #20 enableDiv = 0;
    #240 

    rst = 1;
    #20 rst = 0;
    divA = -32'd50000000;
    divB = -32'd1234;
    enableDiv = 1;
    #20 enableDiv = 0;
    #240 

    rst = 1;
    #20 rst = 0;
    divA = -32'd50000000;
    divB = 32'd1234;
    enableDiv = 1;
    #20 enableDiv = 0;
    #240 
    
    $stop;
end

initial begin
    forever
        #10 clk = ~clk;
end

MultiplierDivider multDiv(
    .clk, .rst,
    .multA(32'b0), .multB(32'b0),
    .enableMult(1'b0),
    .divA, .divB,
    .enableDiv,
    .isSignedMult(1'b0),
    .isSignedDiv,
    .hi, .lo
);

endmodule