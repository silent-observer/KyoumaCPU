module SevenSegment (
    input logic displayClk,
    input logic rst,
    input logic[31:0] in,
    input logic[3:0] dot,
    input logic hi,
    output logic[3:0] dig,
    output logic[7:0] seg
);

always_ff @(posedge displayClk) begin
    if (rst) begin
        dig <= 4'b0001;
    end else begin
        dig <= {dig[2:0], dig[3]};
    end
end

logic[15:0] data;
logic[3:0] segData;
assign data = hi? in[31:16]: in[15:0];
always_comb begin
    if (dig[0]) begin
        segData = data[3:0];
        seg[7] = dot[0];
    end else if (dig[1]) begin
        segData = data[7:4];
        seg[7] = dot[1];
    end else if (dig[2]) begin
        segData = data[11:8];
        seg[7] = dot[2];
    end else begin
        segData = data[15:12];
        seg[7] = dot[3];
    end
end

always_comb begin
    case(segData)
        4'h0: seg[6:0] = 7'h3F;
        4'h1: seg[6:0] = 7'h06;
        4'h2: seg[6:0] = 7'h5B;
        4'h3: seg[6:0] = 7'h4F;
        4'h4: seg[6:0] = 7'h66;
        4'h5: seg[6:0] = 7'h6D;
        4'h6: seg[6:0] = 7'h7D;
        4'h7: seg[6:0] = 7'h07;
        4'h8: seg[6:0] = 7'h7F;
        4'h9: seg[6:0] = 7'h6F;
        4'hA: seg[6:0] = 7'h77;
        4'hB: seg[6:0] = 7'h7C;
        4'hC: seg[6:0] = 7'h39;
        4'hD: seg[6:0] = 7'h5E;
        4'hE: seg[6:0] = 7'h79;
        4'hF: seg[6:0] = 7'h71;
    endcase
end

endmodule