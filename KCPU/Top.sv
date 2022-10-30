module Top (
    input logic clk,
    input logic rst,
    input logic[3:0] buttons,
    input logic ir,
    output logic[31:0] dr,
    output logic[3:0] ssDig,
    output logic[7:0] ssSeg,
    output logic[3:0] leds,
    output logic[2:0] lcdCtrl,
    inout logic[7:0] lcdDataInout
);
    logic[31:0] addrI, addrD, writeData, dataI, dataD;
    logic[3:0] writeMask;
    logic writeEnable;
    logic trueRst, trueIr;
    logic[3:0] trueLeds;
    assign trueRst = ~rst;
    assign trueIr = ~ir;
    assign leds = ~{trueLeds[0], trueLeds[1], trueLeds[2], trueLeds[3]};

    logic[3:0] trueButtons, trueButtonsUp;
    Debouncer d0(.clk, .rst(trueRst), .PB(buttons[0]), .PB_state(trueButtons[0]), .PB_up(trueButtonsUp[0]));
    Debouncer d1(.clk, .rst(trueRst), .PB(buttons[1]), .PB_state(trueButtons[1]), .PB_up(trueButtonsUp[1]));
    Debouncer d2(.clk, .rst(trueRst), .PB(buttons[2]), .PB_state(trueButtons[2]), .PB_up(trueButtonsUp[2]));
    Debouncer d3(.clk, .rst(trueRst), .PB(buttons[3]), .PB_state(trueButtons[3]), .PB_up(trueButtonsUp[3]));

    logic numberPressed;
    logic[3:0] numberPressedData;
    IR irCtrl(
        .clk, .rst, .ir,
        .numberPressedData, .numberPressed
    );

    logic irResponse, irIrq
    logic[3:0] irData;
    assign irData = numberPressedData;

    always_ff @ (posedge clk) begin
        if (rst) begin
            irIrq <= 1'b0;
        end else if (numberPressed) begin
            irIrq <= 1'b1;
        end else if (irResponse) begin
            irIrq <= 1'b0;
        end
    end

    logic[3:0] notSsDig;
    logic[7:0] notSsSeg;
    //assign trueButtons = ~notTrueButtons;
    assign ssDig = ~notSsDig;
    assign ssSeg = ~notSsSeg;

    logic lcdRS, lcdRW, lcdE;
    logic[7:0] lcdDataIn, lcdDataOut;
    assign lcdCtrl = {lcdE, lcdRW, lcdRS};
    assign lcdDataIn = lcdDataInout;
    assign lcdDataInout = lcdRW? 8'hzz: lcdDataOut;

    logic[19:0] clkCounter;
    always_ff @(posedge clk) begin
        clkCounter <= clkCounter + 20'b1;
    end

    logic cpuClk;
    logic[1:0] cpuSpeed;
    always_comb begin
        if (trueButtons == 4'b1111) begin
            cpuClk = clk;
            cpuSpeed = 2'd2;
        end else if (trueButtons[1:0] == 4'b11) begin
            cpuClk = clkCounter[19];
            cpuSpeed = 2'd1;
        end else begin
            cpuClk = trueButtons[0];
            cpuSpeed = 2'd0;
        end
    end

    logic[4:0] drSelect;
    assign trueLeds = {drSelect[4], cpuSpeed, 1'b0};
    always_ff @(posedge clk) begin
        if (trueRst)
            drSelect <= 5'd0;
        else if (trueButtonsUp[3]) begin
            if (drSelect == 5'd18)
                drSelect <= 5'd0;
            else
                drSelect <= drSelect + 5'd1;
        end else if (trueButtonsUp[2]) begin
            if (drSelect == 5'd0)
                drSelect <= 5'd18;
            else
                drSelect <= drSelect - 5'd1;
        end
    end

    logic[31:0] ssIn;
    assign ssIn = drSelect == 5'd17 ? writeData: 
                  drSelect == 5'd18 ? addrD: dr;

    SevenSegment ss(
        .displayClk(clkCounter[17]), .rst(trueRst),
        .in(ssIn),
        .dot(drSelect[3:0]), .hi(trueButtons[1] && !trueButtons[0]),
        .dig(notSsDig), .seg(notSsSeg)
    );

    MemoryController mem(
        .addrI, .addrD,
        .writeEnable,
        .clk(!cpuClk), .rst(trueRst),
        .writeData, .writeMask,
        .dataI, .dataD,
        .lcdRS, .lcdRW, .lcdE, .lcdDataIn, .lcdDataOut,
        .cpuSpeed
    );
    KCPU cpu(
        .clk(cpuClk), .rst(trueRst),
        .addrI, .addrD,
        .writeEnable,
        .writeData, .writeMask,
        .dataI, .dataD,
        .irIrq, .irResponse, .irData,
        .dr, .drSelect
    );
endmodule