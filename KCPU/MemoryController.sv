/*
 * Memory controller. In the future it will be a full-fledged MMU.
 */

module MemoryController (
    input logic[31:0] addrI, addrD, // Instruction and data read addresses
    input logic writeEnable, // Enable data write
    input logic clk, rst,
    input logic[31:0] writeData, // Actual value to write
    input logic[3:0] writeMask, // Write data mask
    output logic[31:0] dataI, dataD, // Read values
    output logic lcdRS, lcdRW, lcdE, // LCD control outputs
    input logic[7:0] lcdDataIn, // LCD data input
    output logic[7:0] lcdDataOut, // LCD data output
    input logic[1:0] cpuSpeed // CPU speed
);

logic[7:0] addrILowerBits, addrDLowerBits;
logic[9:0] addrILowerBitsBig, addrDLowerBitsBig;
// Currently there are only 4 KB in ROM and code sections and 1 KB in every other, 
// so this part of address selects a word inside the section.
assign addrILowerBits = addrI[9:2];
assign addrDLowerBits = addrD[9:2];
assign addrILowerBitsBig = addrI[11:2];
assign addrDLowerBitsBig = addrD[11:2];

logic isIInUStack, isDInUStack, isIInSStack, isDInSStack, 
      isIInHeap, isDInHeap, isIInCode, isDInCode, isIInROM, isDInROM;
// Tests which section each address is in
assign isIInUStack = addrI[31:10] == 22'b1101_1111_1111_1111_1111_11;
assign isDInUStack = addrD[31:10] == 22'b1101_1111_1111_1111_1111_11;
assign isIInSStack = addrI[31:10] == 22'b1110_1111_1111_1111_1111_11;
assign isDInSStack = addrD[31:10] == 22'b1110_1111_1111_1111_1111_11;
assign isIInHeap = addrI[31:10] == 22'b0001_0000_0000_0000_0000_00;
assign isDInHeap = addrD[31:10] == 22'b0001_0000_0000_0000_0000_00;
assign isIInCode = addrI[31:12] == 22'h10;
assign isDInCode = addrD[31:12] == 22'h10;
assign isIInROM = addrI[31:12] == 0;
assign isDInROM = addrD[31:12] == 0;

logic isLcdData, isLcdCtrl, isCpuSpeed;


assign isLcdCtrl = addrD == 32'hFFFFFFFF;
assign isLcdData = addrD == 32'hFFFFFFFE;
assign isCpuSpeed = addrD == 32'hFFFFFFFD;

always_ff @(posedge clk) begin
    if (rst) begin
        {lcdE, lcdRW, lcdRS} <= 3'b000;
        lcdDataOut <= 8'h00;
    end else if (writeEnable && isLcdData) begin
        lcdDataOut <= writeData[7:0];
    end else if (writeEnable && isLcdCtrl) begin
        {lcdE, lcdRW, lcdRS} <= writeData[2:0];
    end
end

logic[31:0] uStackI, uStackD, sStackI, sStackD, heapI, heapD, codeI, codeD, romI, romD;

// Memory blocks themselves
RAM ustack(
    .address_a(addrILowerBits),
    .address_b(addrDLowerBits),
    .byteena_a(4'b1111),
    .byteena_b(writeMask),
    .clock(clk),
    .data_a(0),
    .data_b(writeData),
    .wren_a(1'b0),
    .wren_b(writeEnable & isDInUStack),
    .q_a(uStackI),
    .q_b(uStackD)
);
RAM sstack(
    .address_a(addrILowerBits),
    .address_b(addrDLowerBits),
    .byteena_a(4'b1111),
    .byteena_b(writeMask),
    .clock(clk),
    .data_a(0),
    .data_b(writeData),
    .wren_a(1'b0),
    .wren_b(writeEnable & isDInSStack),
    .q_a(sStackI),
    .q_b(sStackD)
);
RAM heap(
    .address_a(addrILowerBits),
    .address_b(addrDLowerBits),
    .byteena_a(4'b1111),
    .byteena_b(writeMask),
    .clock(clk),
    .data_a(0),
    .data_b(writeData),
    .wren_a(1'b0),
    .wren_b(writeEnable & isDInHeap),
    .q_a(heapI),
    .q_b(heapD)
);
RAMBig code(
    .address_a(addrILowerBitsBig),
    .address_b(addrDLowerBitsBig),
    .byteena_a(4'b1111),
    .byteena_b(writeMask),
    .clock(clk),
    .data_a(0),
    .data_b(writeData),
    .wren_a(1'b0),
    .wren_b(writeEnable & isDInCode),
    .q_a(codeI),
    .q_b(codeD)
);
ROM rom(
    .addrA(addrILowerBitsBig), 
    .addrB(addrDLowerBitsBig),
    .clk,
    .dataA(romI), 
    .dataB(romD)
);

// Select from where instruction is read
always_comb begin
    if (isIInUStack)
        dataI = uStackI;
    else if (isIInSStack)
        dataI = sStackI;
    else if (isIInHeap)
        dataI = heapI;
    else if (isIInCode)
        dataI = codeI;
    else if (isIInROM)
        dataI = romI;
    else
        dataI = 0;
end

// Select from where data is read
always_comb begin
    if (isDInUStack)
        dataD = uStackD;
    else if (isDInSStack)
        dataD = sStackD;
    else if (isDInHeap)
        dataD = heapD;
    else if (isDInCode)
        dataD = codeD;
    else if (isDInROM)
        dataD = romD;
    else if (isLcdData)
        dataD = {4{lcdDataIn}};
    else if (isCpuSpeed)
        dataD = {4{6'b0, cpuSpeed}};
    else
        dataD = 0;
end

endmodule