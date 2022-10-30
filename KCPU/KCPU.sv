import signalStruct::*;

/*
 * CPU itself
 */

module KCPU (
    input logic clk,
    input logic rst,
    input logic[31:0] dataI, dataD, // Read values
    input logic[4:0] drSelect, // Debug register select
    output logic writeEnable, // Enable write to memory
    output logic[31:0] addrI, addrD, // Read addresses
    output logic[31:0] writeData, // Data to write
    output logic[3:0] writeMask, // Write data mask
    input logic irIrq, // IR interrupt request
    output logic irResponse, // Signal to clear IR interrupt request
    input logic[3:0] irData, // IR interrupt data
    output logic[31:0] dr // Debug register write
);
    logic[31:0] instr;
    logic cpuMode, modeSwitch;
    // Signal at different pipeline stages
    ctrlSignals signalsDecode, signalsRead, signalsExec, signalsWrite;
    logic[19:0] immRead, immExec; // 6 most significant bits are ignored in immediate value instrctions

    ctrlSignals emptySignals;
    assign emptySignals = '{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};

    logic[31:0] readAData, readBData; // Register values at Read (ALU operands)
    logic[31:0] regWriteData; // Data to write to register (Write Stage)
    logic[31:0] pc; // PC (Fetch Stage)
    logic[31:0] pcDecode; // PC (Decode Stage)
    logic[31:0] readBypassFromExec, readBypassFromWrite; // Data coming through bypasses
    logic[31:0] readADataBypassed, readBDataBypassed; // ALU operands after bypass (End of Read Stage)
    logic[31:0] readADataExec, readBDataExec; // ALU operands at Exec
    logic[31:0] aluOut; // ALU output (Exec Stage)
    logic[3:0] aluFlags, aluFlagsMask; // New flags and flag mask (Exec)
    logic[3:0] inFlags, inFlagsMask; // Flags and flag mask to write (Write)
    logic[7:0] outConditions, nextConditions; // Current (Write) and next (Exec) condition values
    logic[31:0] addressExec; // Address in load/store instructions (Exec Stage)

    Decoder decoder(
        .instr, .cpuMode, .rst, .clk, .halfWordSelector(pcDecode[1]),
        .signals(signalsDecode)
    );

    logic[2:0] cond, execCond; // Condition index at Write and at Exec
    logic freezeFlags, isConditionTrue, isExecConditionTrue, isPCModified, isDivisionBy0;
    logic isInterrupt;

    assign writeEnable = signalsExec.isStore && isExecConditionTrue;
    assign addrD = (signalsExec.isLoad || signalsExec.isStore)? addressExec : 32'b0;
    
    always_comb begin
        writeData = 32'b0;
        writeMask = 4'b0000;
        if (signalsExec.isStore) begin
            if (signalsExec.isLoadStore8Bit) begin
                writeData = {4{readBDataExec[7:0]}};
                case(addressExec[1:0])
                    2'b00: writeMask = 4'b0001;
                    2'b01: writeMask = 4'b0010;
                    2'b10: writeMask = 4'b0100;
                    2'b11: writeMask = 4'b1000;
                endcase
            end else if (signalsExec.isLoadStore16Bit) begin
                writeData = {2{readBDataExec[15:0]}};
                writeMask = addressExec[1]? 4'b1100 : 4'b0011;
            end else begin
                writeData = readBDataExec;
                writeMask = 4'b1111;
            end
        end
    end
    
    assign cond = signalsWrite.condition[2:0]; // Condition of instruction at Write
    assign execCond = signalsExec.condition[2:0]; // Condition of instruction at Exec
    assign freezeFlags = signalsWrite.condition[3]; // Should we freeze flags
    assign isConditionTrue = outConditions[cond]; // Check condition at Write
    assign isExecConditionTrue = nextConditions[execCond]; // Check condition at Exec
    assign isPCModified = signalsWrite.isPCModified && isConditionTrue; // Is PC modified right now (Write Stage)

    // Bypasses
    logic bypassFromExecANeeded, bypassFromExecBNeeded;
    logic bypassFromWriteANeeded, bypassFromWriteBNeeded;
    // Bypass from Exec Stage if previous instruction overwrites the value and if its condition is true
    assign bypassFromExecANeeded = signalsExec.regWE && isExecConditionTrue &&
        (signalsExec.regSelectW == signalsRead.regSelectA) &&
        (signalsExec.regSelectW[3:0] != 4'h0);
    assign bypassFromExecBNeeded = signalsExec.regWE && isExecConditionTrue &&
        (signalsExec.regSelectW == signalsRead.regSelectB) &&
        (signalsExec.regSelectW[3:0] != 4'h0);
    // Bypass from Write Stage if instruction before previous overwrites the value and if its condition is true
    assign bypassFromWriteANeeded = signalsWrite.regWE && isConditionTrue &&
        (signalsWrite.regSelectW == signalsRead.regSelectA) &&
        (signalsWrite.regSelectW[3:0] != 4'h0);
    assign bypassFromWriteBNeeded = signalsWrite.regWE && isConditionTrue &&
        (signalsWrite.regSelectW == signalsRead.regSelectB) &&
        (signalsWrite.regSelectW[3:0] != 4'h0);

    RegFile regs(
        .clk, .rst,
        .writeEnable(signalsWrite.regWE && isConditionTrue), // Write only if condition is true
        .writeSelect(signalsWrite.regSelectW),
        .readASelect(signalsRead.regSelectA),
        .readBSelect(signalsRead.regSelectB),
        .pcIncBy2(!dataI[31]), // Is current (Fetch) instruction short?
        .cpuMode, .inFlags, .modeSwitch,
        // Write only if not freezed and if condition is true
        .inFlagsMask((freezeFlags || !isConditionTrue)? 4'b0000 : inFlagsMask), 
        .outConditions, .nextConditions,
        .readAData, .readBData, .writeData(regWriteData), .pc, .pcDecode,
        .setDivisionBy0(isDivisionBy0), 
        .setHardwareInterrupt(irIrq), .hardwareInterruptType(2'b0),
        .hardwareInterruptData({28'b0, irData})
        .drSelect, .dr
    );

    // Read at new PC value or at old one
    assign addrI = isPCModified? regWriteData : pc;

    // Immediate value (Exec stage)
    logic[31:0] immExtended;
    assign immExtended = 
        signalsExec.isLDI? 
        {{12{immExec[19]}}, immExec} :
        {{18{immExec[13]}}, immExec[13:0]};

    ALU alu(
        .a(readADataExec),
        .b((signalsExec.isImm || signalsExec.isLDI)? 
            immExtended : readBDataExec), // Second operand could be a register or immediate
        .func(signalsExec.aluFunc),
        .out(aluOut),
        .flags(aluFlags), .flagsMask(aluFlagsMask)
    );

    logic[31:0] hi, lo;

    MultiplierDivider multDiv(
        .clk, .rst,
        .multA(readADataExec), .multB(readBDataExec),
        .divA(readADataExec), .divB(readBDataExec),
        .enableMult(signalsExec.isMult),
        .isSignedMult(signalsExec.isMultSigned),
        .enableDiv(signalsExec.isDiv && !isDivisionBy0),
        .isSignedDiv(signalsExec.isDivSigned),
        .hi, .lo
    );

    logic[31:0] maskedMemoryData;
    logic[7:0] selectedByte;
    logic[15:0] selectedHalfWord;

    assign isDivisionBy0 = signalsExec.isDiv & (readBDataExec == 32'b0);
    assign isInterrupt = isDivisionBy0 || irIrq;

    logic[31:0] regWriteCandidate;
    always_comb begin
        if (signalsExec.isLoad)
            regWriteCandidate = maskedMemoryData;
        else if (signalsExec.isMVHI)
            regWriteCandidate = hi;
        else if (signalsExec.isMVLO)
            regWriteCandidate = lo;
        else
            regWriteCandidate = aluOut;
    end
    // Bypasses
    assign readBypassFromExec = regWriteCandidate;
    assign readBypassFromWrite = regWriteData;

    always_comb begin
        selectedByte = 8'b0;
        selectedHalfWord = 8'b0;
        if (signalsExec.isLoadStore8Bit) begin
            case(addressExec[1:0])
                2'b00: selectedByte = dataD[7:0];
                2'b01: selectedByte = dataD[15:8];
                2'b10: selectedByte = dataD[23:16];
                2'b11: selectedByte = dataD[31:24];
            endcase
            maskedMemoryData = signalsExec.isLoadSigned? 
                {{24{selectedByte[7]}}, selectedByte} : 
                {24'b0, selectedByte};
        end else if (signalsExec.isLoadStore16Bit) begin
            selectedHalfWord = addressExec[1]? dataD[31:16] : dataD[15:0];
            maskedMemoryData = signalsExec.isLoadSigned? 
                {{16{selectedHalfWord[15]}}, selectedHalfWord} : 
                {16'b0, selectedHalfWord};
        end else
            maskedMemoryData = dataD;
    end

    always_comb begin
        // Bypass first operand if needed
        if (bypassFromExecANeeded)
            readADataBypassed = readBypassFromExec;
        else if (bypassFromWriteANeeded)
            readADataBypassed = readBypassFromWrite;
        else
            readADataBypassed = readAData;
        
        // Bypass second operand if needed
        if (bypassFromExecBNeeded)
            readBDataBypassed = readBypassFromExec;
        else if (bypassFromWriteBNeeded)
            readBDataBypassed = readBypassFromWrite;
        else
            readBDataBypassed = readBData;
    end

    always_ff @ (posedge clk) begin
        if (rst) begin // Reset every internal register
            signalsRead <= emptySignals;
            signalsExec <= emptySignals;
            signalsWrite <= emptySignals;
            immRead <= 20'b0;
            immExec <= 20'b0;
            instr <= 32'b0;

            readADataExec <= 32'b0;
            readBDataExec <= 32'b0;

            regWriteData <= 32'b0;

            inFlagsMask <= 4'b0;
            inFlags <= 4'b0;

            addressExec <= 32'b0;
            irResponse <= 1'b0;
        end else begin
            if (isPCModified) begin // Clear pipeline, but read instruction immediately
                signalsRead <= emptySignals;
                signalsExec <= emptySignals;
                signalsWrite <= emptySignals;
                instr <= dataI;
            end else if (modeSwitch || isInterrupt) begin // Also clear pipeline, but clear instruction too.
                signalsRead <= emptySignals;
                signalsExec <= emptySignals;
                signalsWrite <= emptySignals;
                instr <= 32'b0;
                if (irIrq) irResponse <= 1'b1;
            end else begin
                // Advance signal pipeline
                signalsRead <= signalsDecode;
                signalsExec <= signalsRead;
                signalsWrite <= signalsExec;
                // Get a condition (if any) from the queue (for short instructions)
                if (signalsDecode.isShort) begin
                    if ((signalsRead.nextConditions != 12'b0) && !signalsDecode.isCND) begin
                        signalsRead.condition <= signalsRead.nextConditions[11:8];
                        signalsRead.nextConditions <= {signalsRead.nextConditions[7:0], 4'b0};
                    end
                end
                
                // Store opcode
                instr <= dataI;
                // If flags shouldn't be updated, reset the mask to 0s
                inFlagsMask <= signalsExec.enableFlagsUpdate? aluFlagsMask : 4'b0;
                // Advance flags
                inFlags <= aluFlags;
            end
            // Advance PC and immediate value
            immRead <= instr[23:4];
            immExec <= immRead;
            addressExec <= readADataBypassed + {{17{immRead[14]}}, immRead[14:0]};
            // Advance ALU operands
            readADataExec <= readADataBypassed;
            readBDataExec <= readBDataBypassed;
            // Advance ALU result
            regWriteData <= regWriteCandidate;
        end
    end

endmodule