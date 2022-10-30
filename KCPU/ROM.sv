module ROM #(parameter ADDR_WIDTH = 10) (
    input logic [(ADDR_WIDTH-1):0] addrA, addrB,
    input logic clk,
    output logic [31:0] dataA, dataB
);

logic [31:0] rom [0:(2 ** ADDR_WIDTH - 1)];

int i;

initial begin
    for (i = 0; i < 2 ** ADDR_WIDTH; i++)
        rom[i] = 32'b0;
    $readmemh("D:\\Programming\\KyoumaCPU\\KCPU\\ROMContents.mem", rom);
end

always_ff @ (posedge clk) begin
    dataA <= rom[addrA];
    dataB <= rom[addrB];
end
endmodule