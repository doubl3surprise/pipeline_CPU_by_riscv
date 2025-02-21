`include "define.v"
module memory_access(
    	input wire clk_i,
    	input wire [6:0] M_opcode_i,
    	input wire [9:0] M_funct_i,
    	input wire [31:0] M_valE_i,
		input wire [31:0] M_val2_i,
    	output wire [31:0] m_valM_o
);
	wire is_load = (M_opcode_i == `OP_LOAD);
	wire is_s = (M_opcode_i == `OP_S);
    wire r_en = is_load;
    wire w_en = is_s;
    wire [31:0] mem_addr = (is_load | is_s) ? M_valE_i : 32'd0;
	wire [31:0] wdata = is_s ? M_val2_i : 32'd0;

   	ram ram_stage(
        	.clk_i(clk_i),
        	.r_en_i(r_en),
        	.w_en_i(w_en),
        	.funct_i(M_funct_i),
        	.addr_i(mem_addr),
        	.wdata_i(wdata),
        	.rdata_o(m_valM_o)
    	);
endmodule