module MultiplierDivider (
    input logic clk,
    input logic rst,
    input logic[31:0] multA, multB,
    input logic enableMult,
    input logic[31:0] divA, divB,
    input logic enableDiv,
    input logic isSignedMult,
    input logic isSignedDiv,
    output logic[31:0] hi, lo
);

logic[31:0] multIn1, multIn2;
logic[63:0] multOut;
assign multOut = {32'b0, multIn1} * {32'b0, multIn2};
logic signMultA, signMultB;

always_comb begin
    if (isSignedMult) begin
        signMultA = multA[31];
        signMultB = multB[31];
        multIn1 = signMultA? -multA : multA;
        multIn2 = signMultB? -multB : multB;
    end else begin
        signMultA = 0;
        signMultB = 0;
        multIn1 = multA;
        multIn2 = multB;
    end
end

logic[31:0] divisor;
logic[63:0] divAQ, divAQ0, divAQ1, divAQ2;
logic divASign0, divASign1, divASign2;
logic[31:0] negatedDivisor0, negatedDivisor1, negatedDivisor2;
logic[3:0] divCounter;
logic divisorSign, dividendSign;
logic[31:0] absDivA, absDivB;
assign absDivA = divA[31]? -divA: divA;
assign absDivB = divB[31]? -divB: divB;

always_comb begin
    divASign0 = divAQ[63];
    negatedDivisor0 = divASign0? divisor: -divisor;
    divAQ0 = {divAQ[62:0], 1'b0} + {negatedDivisor0, 32'b0};
    divASign1 = divAQ0[63];
    negatedDivisor1 = divASign1? divisor: -divisor;
    divAQ1 = {divAQ0[62:1], !divASign1, 1'b0} + {negatedDivisor1, 32'b0};
    divASign2 = divAQ1[63];
    negatedDivisor2 = divASign2? divisor: -divisor;
    divAQ2 = {divAQ1[62:1], !divASign2, 1'b0} + {negatedDivisor2, 32'b0};
end

logic[31:0] divHiCandidate, divLoCandidate;
assign divHiCandidate = divAQ1[63:32] + (divAQ1[63]? divisor: 32'b0);
assign divLoCandidate = {divAQ1[31:1], !divAQ1[63]};

always_ff @ (posedge clk) begin
    if (rst) begin
        hi <= 32'b0;
        lo <= 32'b0;
    end else if (divCounter == 4'd1) begin
        hi <= dividendSign? -divHiCandidate: divHiCandidate;
        lo <= (dividendSign ^ divisorSign)? -divLoCandidate: divLoCandidate;
        divCounter <= 0;
    end else begin
        if (divCounter != 4'd0) begin
            divCounter <= divCounter - 4'd1;
            divAQ <= {divAQ2[63:1], !divAQ2[63]};
        end
        if (enableMult) begin
            if (isSignedMult) begin
                hi <= signMultA ^ signMultB? -multOut[63:32] : multOut[63:32];
                lo <= signMultA ^ signMultB? -multOut[31:0] : multOut[31:0];
            end else begin
                hi <= multOut[63:32];
                lo <= multOut[31:0];
            end
        end if (enableDiv) begin
            dividendSign <= isSignedDiv? divA[31]: 1'b0;
            divisorSign <= isSignedDiv? divB[31]: 1'b0;
            divCounter <= 4'd11;
            divAQ <= isSignedDiv? {32'b0, absDivA}: {32'b0, divA};
            divisor <= isSignedDiv? absDivB: divB;
        end
    end
end

endmodule