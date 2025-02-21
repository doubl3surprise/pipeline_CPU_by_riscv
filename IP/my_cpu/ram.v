`include "define.v"
module ram(input wire clk_i,
	input wire r_en_i,
	input wire w_en_i,
	input wire [9:0] funct_i,
	input wire [31:0] addr_i,
	input wire [31:0] wdata_i,
	output wire [31:0] rdata_o
);	
	
	import "DPI-C" function void dpi_mem_write(input int addr, input int data, int len);
	import "DPI-C" function int dpi_mem_read (input int addr, input int len);
	wire [31:0] mem;
	assign mem = (addr_i >= 32'h80000000 && addr_i <= 32'h87ffffff)
		? dpi_mem_read(addr_i, 4) : 32'd0;
    wire [31:0] load_word = mem;
    wire [15:0] load_half = mem[15:0];
    wire  [7:0] load_byte = mem[7:0];
	assign rdata_o = r_en_i ? 
        (funct_i == `FUNC_LW)  ? load_word :
        (funct_i == `FUNC_LH)  ? {{16{load_half[15]}}, load_half} :
        (funct_i == `FUNC_LB)  ? {{24{load_byte[7]}}, load_byte} :
        (funct_i == `FUNC_LHU) ? {16'd0, load_half} :
        (funct_i == `FUNC_LBU) ? {24'd0, load_byte} : 32'd0
        : 32'd0;

	always@ (posedge clk_i) begin
		if(w_en_i) begin
			if(funct_i == `FUNC_SB) dpi_mem_write(addr_i, wdata_i, 1);
			else if(funct_i == `FUNC_SH) dpi_mem_write(addr_i, wdata_i, 2);
			else dpi_mem_write(addr_i, wdata_i, 4);
		end
    end
endmodule