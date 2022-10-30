/*
 * Register of specified width. Has synchronous reset.
 */

module Register #(parameter WIDTH = 32) (
    input logic clk,
    input logic rst,
    input logic writeEnable,
    input logic[WIDTH-1:0] in,
    output logic[WIDTH-1:0] out
);

always_ff @ (posedge clk)
begin
    if (rst) begin
        out <= 0;
    end else if (writeEnable) begin
        out <= in;
    end
end

endmodule

/*
 * Register file. It also updates the PC, sets the flags and calculates all possible conditions.
 */

module RegFile (
    input logic clk,
    input logic rst,
    input logic writeEnable,
    input logic[4:0] writeSelect, // Which register is written to
    input logic[31:0] writeData, // Value to write
    input logic[4:0] readASelect, // First read port
    input logic[4:0] readBSelect, // Second read port
    input logic pcIncBy2, // Is current instruction short?
    input logic[3:0] inFlags, // ALU flags
    input logic[3:0] inFlagsMask, // ALU flag mask
    input logic setDivisionBy0, // Division by 0 happened, interrupt
    input logic setHardwareInterrupt, // Hardware interrupt happened
    input logic[1:0] hardwareInterruptType,
    input logic[31:0] hardwareInterruptData,
    input logic[4:0] drSelect, // Debug register select
    output logic[7:0] nextConditions, // Condition values of the next instruction (currently in Execute Stage)
    output logic[7:0] outConditions, // Current condition values (instruction in Write Stage)
    output logic[31:0] readAData, // First read port output
    output logic[31:0] readBData, // Second read port output
    output logic[31:0] pc, // Current PC (for fetching)
    output logic cpuMode, // Supervisor (0) or User (1)
    output logic modeSwitch, // Set if CPU mode is about to switch
    output logic[31:0] pcDecode, // PC value of previous instruction. This PC should be read if it is read explicitly.
    output logic[31:0] dr // Debug Register output
);

logic[31:0] regOutputsA[0:31];
logic[31:0] regOutputsB[0:31];
logic[31:0] regOutputsD[0:31];
logic[31:0] pcS, pcU; // PCs of Supervisor and User modes
logic[31:0] srS, srU; // SRs of Supervisor and User modes

logic[31:0] mainDr;
logic[31:0] pcD, pcR, pcE, pcW;
logic[1:0] isJumpA, isJump;
assign dr = drSelect[4]? pcW: mainDr;
assign isJump = isJumpA[0] || isJumpA[1];

assign pcDecode = pcD;
always_ff @ (posedge clk) begin
    if (rst) begin
        pcD <= 32'b0;
        pcR <= 32'b0;
        pcE <= 32'b0;
        pcW <= 32'b0;
    end else if (isJump) begin
        pcD <= writeData;
        pcR <= writeData;
        pcE <= writeData;
        pcW <= writeData;
    end else begin
        pcD <= pc;
        pcR <= pcD;
        pcE <= pcR;
        pcW <= pcE;
    end
end

StatusRegister sr(
    .clk,
    .rst,
    .inFlags,
    .inFlagsMask,
    .in(writeData),
    .writeEnable(writeEnable && (writeSelect[3:0] == 4'b1011)),
    .writeSelector(writeSelect[4]), .setDivisionBy0, .setHardwareInterrupt,
    .outS(srS), .outU(srU),
    .currentCond(outConditions),
    .nextCond(nextConditions),
    .cpuMode, .modeSwitch
);

genvar i;
generate
    for (i = 0; i < 32; i++) begin : registerLoop
        if (i == 15 || i == 31) begin // PC
            logic[31:0] out, pcIn, pcIncreased;
            logic isOverwritten, isCurrentPC;
            // Is PC explicitly written (by instruction)
            assign isOverwritten = writeEnable && (writeSelect == i);
            assign isCurrentPC = cpuMode == i[4];
            if (i == 15)
                assign pcS = out;
            if (i == 31)
                assign pcU = out;
            assign pcIn = isOverwritten? writeData: out;
            assign pcIncreased = modeSwitch? pcE : // Backtrack PC if switching mode
                (setDivisionBy0 || setHardwareInterrupt)? pcR : // Or if interrupted
                (pcIncBy2? pcIn + 2 : pcIn + 4); // Next PC value
            // Note: if overwritten, still increment PC, because that instruction was 
            // already fetched (before updating the PC)
            assign isJumpA[i[4]] = isOverwritten && isCurrentPC;
            Register r(
                .clk,
                .rst,
                .writeEnable(isCurrentPC || isOverwritten),
                .in(isCurrentPC? pcIncreased : pcIn),
                .out
            );
            // If current PC is read explicitly, then use previous pcValue, if it is not current PC - just read it.
            assign regOutputsA[i] = readASelect == i ? (isCurrentPC ? pcD : out) : 0;
            assign regOutputsB[i] = readBSelect == i ? (isCurrentPC ? pcD : out) : 0;
            assign regOutputsD[i] = {cpuMode, drSelect[3:0]} == i ? (isCurrentPC ? pcD : out) : 0;
        end else if (i == 0 || i == 16) begin // R0
            assign regOutputsA[i] = 0;
            assign regOutputsB[i] = 0;
            assign regOutputsD[i] = 0;
        end else if (i == 11) begin // sSR
            assign regOutputsA[i] = readASelect == i ? srS : 0;
            assign regOutputsB[i] = readBSelect == i ? srS : 0;
            assign regOutputsD[i] = {cpuMode, drSelect[3:0]} == i ? srS : 0;
        end else if (i == 27) begin // uSR
            assign regOutputsA[i] = readASelect == i ? srU : 0;
            assign regOutputsB[i] = readBSelect == i ? srU : 0;
            assign regOutputsD[i] = {cpuMode, drSelect[3:0]} == i ? srU : 0;
        end else if (i == 1) begin // uR1
            logic[31:0] in, out;
            logic we;
            assign we = writeEnable && (writeSelect == i);
            assign in = setHardwareInterrupt? {30'b0, hardwareInterruptType} : writeData;
            Register r(
                .clk,
                .rst,
                .writeEnable(we || setHardwareInterrupt),
                .in(in),
                .out
            );
            assign regOutputsA[i] = readASelect == i ? out : 0;
            assign regOutputsB[i] = readBSelect == i ? out : 0;
            assign regOutputsD[i] = {cpuMode, drSelect[3:0]} == i ? out : 0;
        end else if (i == 2) begin // uR2
            logic[31:0] in, out;
            logic we;
            assign we = writeEnable && (writeSelect == i);
            assign in = setHardwareInterrupt? hardwareInterruptData : writeData;
            Register r(
                .clk,
                .rst,
                .writeEnable(we || setHardwareInterrupt),
                .in(in),
                .out
            );
            assign regOutputsA[i] = readASelect == i ? out : 0;
            assign regOutputsB[i] = readBSelect == i ? out : 0;
            assign regOutputsD[i] = {cpuMode, drSelect[3:0]} == i ? out : 0;
        end else begin // Other registers
            logic[31:0] out;
            logic we;
            assign we = writeEnable && (writeSelect == i);
            Register r(
                .clk,
                .rst,
                .writeEnable(we),
                .in(writeData),
                .out
            );
            assign regOutputsA[i] = readASelect == i ? out : 0;
            assign regOutputsB[i] = readBSelect == i ? out : 0;
            assign regOutputsD[i] = {cpuMode, drSelect[3:0]} == i ? out : 0;
        end
    end
endgenerate

// Select which register is active
assign readAData = regOutputsA.or;
assign readBData = regOutputsB.or;
assign mainDr = regOutputsD.or;
assign pc = cpuMode? pcU : pcS;

endmodule