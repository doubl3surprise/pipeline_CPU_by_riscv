`include "define.v"
module ram(
	input wire clk,
	input wire rst,
	input wire r_en,
	input wire w_en,
	input wire [9:0] funct,
	input wire [31:0] addr,
	input wire [31:0] wdata,
	output wire [31:0] rdata
);	
	import "DPI-C" function void dpi_mem_write(input int addr, input int data, int len);
	import "DPI-C" function int dpi_mem_read (input int addr, input int len);


	wire hit;
	wire [31:0] rdata_from_dcache;
	dcache u_dcache(
		.clk(clk),
		.rst(rst),
		.r_en(r_en),
		.r_addr(addr),
		.hit(hit),
		.r_data(rdata_from_dcache),
		.fill_en(r_en && !hit),
		.fill_addr(addr),
		.w_en(w_en),
		.w_addr(addr),
		.w_data(wdata)
	);

	wire [31:0] mem = (addr >= 32'h80000000 && addr <= 32'h87ffffff) 
		? (hit ? rdata_from_dcache : dpi_mem_read(addr, 4)) : 32'd0; 
    wire [31:0] load_word = mem;
    wire [15:0] load_half = mem[15:0];
    wire  [7:0] load_byte = mem[7:0];
	assign rdata = r_en ? 
        (funct == `FUNC_LW)  ? load_word :
        (funct == `FUNC_LH)  ? {{16{load_half[15]}}, load_half} :
        (funct == `FUNC_LB)  ? {{24{load_byte[7]}}, load_byte} :
        (funct == `FUNC_LHU) ? {16'd0, load_half} :
        (funct == `FUNC_LBU) ? {24'd0, load_byte} : 32'd0
        : 32'd0;

	always@ (posedge clk) begin
		if(w_en) begin
			if (funct == `FUNC_SB) begin
				dpi_mem_write(addr, wdata, 1);
			end
			else if (funct == `FUNC_SH) begin
				dpi_mem_write(addr, wdata, 2);
			end
			else begin
				dpi_mem_write(addr, wdata, 4);
			end
		end
    end
endmodule
