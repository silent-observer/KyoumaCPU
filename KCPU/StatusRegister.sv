module StatusRegister (
    input logic clk,
    input logic rst,
    input logic[3:0] inFlags,
    input logic[3:0] inFlagsMask,
    input logic[31:0] in,
    input logic writeEnable,
    input logic writeSelector,
    input logic setDivisionBy0,
    output logic[31:0] outS, outU,
    output logic[7:0] currentCond,
    output logic[7:0] nextCond,
    output logic cpuMode,
    output logic modeSwitch
);

logic isWrittenToActive;
assign isWrittenToActive = writeSelector == cpuMode;

logic[31:0] out;
logic[3:0] flags[0:1];
logic[3:0] flagsIn, flagsMasked;
logic divisionBy0Flag;
assign flagsMasked = (inFlags & inFlagsMask) | (out[3:0] & ~inFlagsMask);
assign flagsIn = (writeEnable && isWrittenToActive)? in[3:0] : flagsMasked;
assign modeSwitch = writeEnable && in[4] != cpuMode;

always_ff @ (posedge clk) begin
    if (rst) begin
        flags[0] <= 4'b0000;
        flags[1] <= 4'b0000;
        cpuMode <= 1'b0;
        divisionBy0Flag <= 1'b0;
    end else begin
        if (modeSwitch) begin
            cpuMode <= in[4];
        end else if (setDivisionBy0) begin
            cpuMode <= 1'b0;
            divisionBy0Flag <= 1'b1;
        end else begin
            if (writeEnable && isWrittenToActive) begin
                flags[cpuMode] <= in[3:0];
                divisionBy0Flag <= in[5];
            end else begin
                if (writeEnable) begin
                    flags[!cpuMode] <= in[3:0];
                    divisionBy0Flag <= in[5];
                end
                flags[cpuMode] <= flagsMasked;
            end
        end
    end
end

logic v0, n0, c0, z0, v1, n1, c1, z1;
assign {v0, n0, c0, z0} = flags[cpuMode];
assign {v1, n1, c1, z1} = flagsIn;
assign {currentCond[0], nextCond[0]} = 2'b11; // Always execute
assign {currentCond[1], nextCond[1]} = {v0, v1}; // ?V
assign {currentCond[2], nextCond[2]} = {z0, z1}; // ?Z
assign {currentCond[3], nextCond[3]} = ~{z0, z1}; // ?NZ
assign {currentCond[4], nextCond[4]} = {n0, n1}; // ?LT
assign {currentCond[5], nextCond[5]} = ~{n0, n1}; // ?GE
assign {currentCond[6], nextCond[6]} = {c0, c1}; // ?C
assign {currentCond[7], nextCond[7]} = ~{c0, c1}; // ?NC

assign outS[3:0] = flags[1'b0];
assign outS[4] = 1'b0; // Mode
assign outS[5] = divisionBy0Flag;
assign outS[6] = 1'b0; // Invalid opcode
assign outS[7] = 1'b0; // Wait for interrupt
assign outS[8] = 1'b0; // Hardware interrupt
assign outS[9] = 1'b0; // Null reference exception
assign outS[31:10] = 22'b0;

assign outU[3:0] = flags[1'b1];
assign outU[4] = 1'b1; // Mode
assign outU[5] = divisionBy0Flag;
assign outU[6] = 1'b0; // Invalid opcode
assign outU[7] = 1'b0; // Wait for interrupt
assign outU[8] = 1'b0; // Hardware interrupt
assign outU[9] = 1'b0; // Null reference exception
assign outU[31:10] = 22'b0;

assign out = cpuMode? outU : outS;

endmodule