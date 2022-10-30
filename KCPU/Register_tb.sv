`timescale 1ns/1ns

module Register_tb ();

logic clk, rst, we, cpuMode;
logic[4:0] writeSelect, readASelect, readBSelect;
logic[31:0] writeData, readAData, readBData, pc;

int i;

initial begin
    clk = 0;
    we = 0;
    rst = 1;
    cpuMode = 0;
    writeSelect = 0;
    readASelect = 0;
    readBSelect = 0;
    #20 rst = 0;
    for (i = 0; i < 32; i++) begin
        #20 writeSelect = i;
        readASelect = i;
        #20 writeData = i * 1000 + 1;
        #210 we = 1;
        #20 we = 0;
    end
    #20 cpuMode = 1;
    for (i = 0; i < 32; i++) begin
        #20 writeSelect = i;
        readBSelect = i;
        #20 writeData = i * 1000 + 13;
        #20 we = 1;
        #20 we = 0;
    end
    for (i = 0; i < 32; i++) begin
        #20 readASelect = i;
    end
    for (i = 0; i < 32; i++) begin
        #20 readBSelect = i;
    end
    #20 rst = 1;
    #20 rst = 0;
    #20 $stop;
end

initial begin
    forever
        #10 clk = ~clk;
end

RegFile r(
    .clk, .rst, .writeEnable(we), .cpuMode, 
    .writeSelect, .readASelect, .readBSelect,
    .writeData, .readAData, .readBData, .pc
);

endmodule