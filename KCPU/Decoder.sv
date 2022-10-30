/*
 * Struct for representing all control signals. Pipelined.
 */

package signalStruct;
    typedef struct {
        logic[4:0] regSelectA; // ALU first input register
        logic[4:0] regSelectB; // ALU second input register
        logic regWE; // Write Enable for register
        logic[4:0] regSelectW; // Written register
        logic[2:0] aluFunc; // ALU function selector
        logic[3:0] condition; // Condition of the current instruction
        logic isShort;
        logic isImm;
        logic isLoad;
        logic isStore;
        logic isLoadSigned;
        logic isLoadStore8Bit;
        logic isLoadStore16Bit;
        logic isCND;
        logic isLDI;
        logic isMult;
        logic isMultSigned;
        logic isDiv;
        logic isDivSigned;
        logic isMVHI;
        logic isMVLO;
        logic isPCModified;
        logic enableFlagsUpdate;
        logic[11:0] nextConditions; // Conditions for the next 3 instruction (queue)
    } ctrlSignals;
endpackage

/*
 * Decodes next instruction and produces control signals.
 * Fully combinatorial
 */

module Decoder (
    input logic[31:0] instr, // Instruction opcode (after fetch)
    input logic cpuMode, // Supervisor (0) or User (1)
    input logic rst,
    input logic clk,
    input logic halfWordSelector, // 2nd least significant bit of address
    output signalStruct::ctrlSignals signals // Output control signals
);

// Current short instruction. Selected according to halfWordSelector.
logic[15:0] shortInstr;
assign shortInstr = halfWordSelector? instr[31:16]: instr[15:0];

always_comb begin
    // Zero all unused signals
    signals.isShort = 1'b0;
    signals.isImm = 1'b0;
    signals.isCND = 1'b0;
    signals.isLDI = 1'b0;
    signals.isMult = 1'b0;
    signals.isMultSigned = 1'b0;
    signals.isDiv = 1'b0;
    signals.isDivSigned = 1'b0;
    signals.isMVHI = 1'b0;
    signals.isMVLO = 1'b0;
    signals.isLoad = 1'b0;
    signals.isStore = 1'b0;
    signals.isLoadSigned = 1'b0;
    signals.isLoadStore8Bit = 1'b0;
    signals.isLoadStore16Bit = 1'b0;
    signals.condition = 4'b0;
    signals.nextConditions = 12'b0;
    signals.regSelectA = 5'b0;
    signals.regSelectB = 5'b0;
    signals.regSelectW = 5'b0;
    signals.regWE = 1'b0;
    signals.aluFunc = 3'b000;
    signals.enableFlagsUpdate = 1'b0;

    if (instr[31] == 1'b0) begin // Short instruction
        signals.isShort = 1'b1;
        if (instr[30:16] == 7'h00) // Skip second NOP
            signals.isShort = 1'b0;
        if (shortInstr[14:12] != 3'b111) begin // Normal short instruction
            signals.regSelectW = {cpuMode, shortInstr[11:8]}; // Destination
            signals.regSelectA = {cpuMode, shortInstr[7:4]}; // Source 1
            signals.regSelectB = {cpuMode, shortInstr[3:0]}; // Source 2
            signals.regWE = 1'b1; // Write to register
            signals.aluFunc = shortInstr[14:12]; // Opcode
            signals.enableFlagsUpdate = shortInstr != 16'h0000; // Flags should be updated if not NOP
        end else begin // CND instruction
            signals.isCND = 1'b1;
            signals.nextConditions = shortInstr[11:0]; // Update nextConditions queue
        end
    end else if (instr[31:29] == 3'b100) begin // Immediate value instruction
        signals.condition = instr[3:0]; // Current instruction condition
        signals.isImm = 1'b1;
        signals.aluFunc = instr[28:26]; // Opcode
        signals.regSelectA = {cpuMode, instr[21:18]}; // Source
        signals.regSelectW = {cpuMode, instr[25:22]}; // Destination
        signals.regWE = 1'b1; // Write to register
        signals.enableFlagsUpdate = 1'b1; // Flags should be updated
    end else if (instr[31:30] == 2'b11) begin // Load/store
        signals.condition = instr[3:0]; // Current instruction condition
        if (instr[29:27] == 3'b000) begin
            signals.isLoad = 1'b1;
            {signals.isLoadStore16Bit, signals.isLoadStore8Bit, signals.isLoadSigned} = 3'b000;
            signals.regSelectA = {cpuMode, instr[22:19]}; // Address register
            signals.regSelectW = {cpuMode, instr[26:23]}; // Destination
            signals.regWE = 1'b1;
        end else if (instr[29] == 1'b1) begin
            signals.isLoad = 1'b1;
            signals.isLoadStore16Bit = !instr[28];
            signals.isLoadStore8Bit = instr[28];
            signals.isLoadSigned = instr[27];
            signals.regSelectA = {cpuMode, instr[22:19]}; // Address register
            signals.regSelectW = {cpuMode, instr[26:23]}; // Destination
            signals.regWE = 1'b1;
        end else begin
            signals.isStore = 1'b1;
            signals.isLoadStore16Bit = instr[28:27] == 2'b10;
            signals.isLoadStore8Bit = instr[28:27] == 2'b11;
            signals.regSelectA = {cpuMode, instr[22:19]}; // Address register
            signals.regSelectB = {cpuMode, instr[26:23]}; // Data register
        end
    end else begin // Miscellaneous
        signals.condition = instr[3:0];
        if (instr[28] == 1'b0) begin // LDI
            signals.regSelectA = 5'b0;
            signals.regSelectW = {cpuMode, instr[27:24]};
            signals.isLDI = 1'b1;
            signals.regWE = 1'b1;
        end else if (instr[28:26] == 3'b110) begin // MVSU/MVUS
            if (cpuMode == 1'b0) begin
                signals.regSelectA = {!instr[25], instr[20:17]};
                signals.regSelectB = 5'b0;
                signals.regSelectW = {instr[25], instr[24:21]};
                signals.regWE = 1'b1;
            end
        end else if (instr[28:26] == 3'b100) begin // MLTU/MLTS
            signals.regSelectA = {cpuMode, instr[24:21]};
            signals.regSelectB = {cpuMode, instr[20:17]};
            signals.isMult = 1'b1;
            signals.isMultSigned = instr[25];
        end else if (instr[28:26] == 3'b111) begin // MVHI/MVLO
            signals.regSelectW = {cpuMode, instr[24:21]};
            signals.regWE = 1'b1;
            signals.isMVHI = !instr[25];
            signals.isMVLO = instr[25];
        end else if (instr[28:26] == 3'b101) begin // DIVU/DIVS
            signals.regSelectA = {cpuMode, instr[24:21]};
            signals.regSelectB = {cpuMode, instr[20:17]};
            signals.isDiv = 1'b1;
            signals.isDivSigned = instr[25];
        end
    end
    // Test if current instruction explicitly modifies the Program Counter (i.e. it's a jump)
    signals.isPCModified = signals.regWE && (signals.regSelectW == {cpuMode, 4'b1111});
end

endmodule