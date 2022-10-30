/*
 * Arithmetic Logic Unit (yeah)
 * It is a part or KCPU doing actual calculations and computing flags.
 * Also it is purely combinatorial
 */

module ALU(
    input logic[31:0] a, // First input to ALU
    input logic[31:0] b, // Second input to ALU
    input logic[2:0] func, // Function which ALU going to perform
    output logic[31:0] out,
    output logic[3:0] flags, // New calculated flags to replace old flags
    output logic[3:0] flagsMask // Which flags should be changed
);

logic[4:0] bShiftNegated;
logic[31:0] lsh, ash, shiftedRightOneLess, shiftedLeftOneLess;
logic shiftCarryWithoutZero, shiftCarry;

assign bShiftNegated = ~b[4:0] + 5'b1; // Last 5 bits of b, negated. Used as operand for right shift.
assign lsh = b[31]? a >> bShiftNegated : a << b[4:0]; // Logical shift result
assign ash = b[31]? a >>> bShiftNegated : a <<< b[4:0]; // Arithmetic shift result
assign shiftedRightOneLess = a >> (bShiftNegated - 1); // Used for calculating carry
assign shiftedLeftOneLess = a << (b[4:0] - 1);
assign shiftCarryWithoutZero = b[31]? shiftedRightOneLess[0] : shiftedLeftOneLess[31]; // Without considering b = 0
assign shiftCarry = (b == 32'b0)? 1'b0 : shiftCarryWithoutZero; // Actual carry after LSH or ASH

logic v, n, c, z; // oVerflow, Negative, Carry, Zero
assign flags = {v, n, c, z};

always_comb begin
    c = 1'b0;
    v = 1'b0;
    flagsMask = 4'b0101; // For logical instructions only update zero and negative flags
    case(func)
        3'b000: begin // ADD
            {c, out} = {1'b0, a} + {1'b0, b};
            v = (!a[31] & !b[31] & out[31]) | (a[31] & b[31] & !out[31]);
            flagsMask = 4'b1111; // Update all flags
        end
        3'b001: begin // SUB
            out = a - b;
            c = a < b;
            v = (!a[31] & b[31] & out[31]) | (a[31] & !b[31] & !out[31]);
            flagsMask = 4'b1111; // Update all flags
        end
        3'b010: begin // LSH
            out = lsh;
            c = shiftCarry;
            flagsMask = 4'b0111; // Update all flags except overflow
        end
        3'b011: begin  // ASH
            out = ash;
            c = shiftCarry;
            flagsMask = 4'b0111; // Update all flags except overflow
        end
        3'b100: out = a & b; // AND
        3'b101: out = a | b; // OR
        3'b110: out = a ^ b; // XOR
        3'b111: out = {b[13:0], a[17:0]}; // LDH
    endcase
    z = out == 32'b0; // Zero flag
    n = out[31]; // Negative flag
end

endmodule