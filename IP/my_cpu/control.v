`include "define.v"
module control(
	input wire [6:0] E_opcode_i,
	input wire e_Cnd_i,
	input wire [4:0] E_rd_i,
	input wire [4:0] D_rs1_i,
	input wire [4:0] D_rs2_i,
	
	output wire F_bubble_o,
	output wire D_bubble_o,
	output wire E_bubble_o,
	output wire M_bubble_o,
	output wire W_bubble_o,

	output reg F_stall_o,
	output reg D_stall_o,
	output reg E_stall_o,
	output reg M_stall_o,
	output reg W_stall_o
);
	
	wire load_use = (E_rd_i == D_rs1_i || E_rd_i == D_rs2_i) && (E_opcode_i == `OP_LOAD);
	
	wire branch_bubble = e_Cnd_i;

	assign D_bubble_o   = branch_bubble;
	assign E_bubble_o   = branch_bubble || load_use;
	assign F_bubble_o   = 1'b0;
	assign M_bubble_o   = 1'b0;
	assign W_bubble_o   = 1'b0;

	assign F_stall_o    = load_use;
	assign D_stall_o    = load_use;
	assign E_stall_o    = 1'b0;
	assign M_stall_o    = 1'b0;
	assign W_stall_o    = 1'b0;
endmodule