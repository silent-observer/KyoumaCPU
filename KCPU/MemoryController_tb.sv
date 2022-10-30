`timescale 1ns/1ns
module MemoryController_tb();

logic[31:0] addrI, addrD, dataI, dataD, writeData;
logic clk, writeEnable;

MemoryController mem(
    .addrI, .addrD,
    .writeEnable,
    .clk,
    .writeData,
    .dataI, .dataD
);

int i;

initial begin
    clk = 0;
    writeData = 0;
    writeEnable = 0;
    addrI = 32'h00000000;
    addrD = 32'h00000000;
    for (i = 0; i < 10; i++) begin
        #20 addrI = i;
        #20 addrD = i + 1;
    end
    #20 addrD = 32'h10000010;
    writeData = 32'hDEADBEEF;
    #20 writeEnable = 1;
    #20 writeEnable = 0;
    #20 addrD = 32'h10000020;
    writeData = 32'h42424242;
    #20 writeEnable = 1;
    #20 writeEnable = 0;
    #20 addrD = 32'h10000010;
    #20 addrD = 32'h10000020;
    #20 addrI = 32'h10000010;
    #20 addrI = 32'h10000020;

    #20 addrD = 32'hDFFFFF10;
    writeData = 32'hDEADBEEF;
    #20 writeEnable = 1;
    #20 writeEnable = 0;
    #20 addrD = 32'hDFFFFF20;
    writeData = 32'h42424242;
    #20 writeEnable = 1;
    #20 writeEnable = 0;
    #20 addrD = 32'hDFFFFF10;
    #20 addrD = 32'hDFFFFF20;
    #20 addrI = 32'hDFFFFF10;
    #20 addrI = 32'hDFFFFF20;
    #20 $stop;
end

initial begin
    forever
        #10 clk = ~clk;
end

endmodule