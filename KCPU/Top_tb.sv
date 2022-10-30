`timescale 1ns/1ns
module Top_tb();

logic cpuClk, trueRst;
logic[31:0] dr;
logic[31:0] addrI, addrD, writeData, dataI, dataD;
logic[3:0] writeMask;
logic writeEnable;

logic lcdRS, lcdRW, lcdE;
logic[7:0] lcdDataIn, lcdDataOut;

MemoryController mem(
    .addrI, .addrD,
    .writeEnable,
    .clk(!cpuClk), .rst(trueRst),
    .writeData, .writeMask,
    .dataI, .dataD, .cpuSpeed(2'd2),
    .lcdRS, .lcdRW, .lcdE, .lcdDataIn, .lcdDataOut
);
KCPU cpu(
    .clk(cpuClk), .rst(trueRst),
    .addrI, .addrD,
    .writeEnable,
    .writeData, .writeMask,
    .dataI, .dataD,
    .dr, .drSelect(5'd1)
);

int i;

initial begin
    cpuClk = 0;
    lcdDataIn = 8'b0;
    trueRst = 1;
    #40 trueRst = 0;
    #100000 $stop;
end

initial begin
    forever
        #10 cpuClk = ~cpuClk;
end

endmodule