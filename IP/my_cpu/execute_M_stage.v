`include "define.v"
module execute_M_stage(
	input wire clk_i,
	input wire M_stall_i,
	input wire M_bubble_i,
	input wire [6:0] E_opcode_i,
	input wire [9:0] E_funct_i,
	input wire [31:0] e_valE_i,
	input wire [31:0] E_val2_i,
	input wire [4:0] E_rd_i,
	input wire [31:0] E_default_pc_i,

	input wire [31:0] E_instr_i,
	input wire E_commit_i,
	input wire [31:0] E_pc_i,
	input wire [31:0] E_pre_pc_i,

	input wire e_Cnd_i,
	
	output reg [6:0] M_opcode_o,
	output reg [9:0] M_funct_o,
	output reg [31:0] M_valE_o,
	output reg [31:0] M_val2_o,
	output reg [4:0] M_rd_o,
	output reg [31:0] M_default_pc_o,

	output reg [31:0] M_instr_o,
	output reg M_commit_o,
	output reg [31:0] M_pc_o,
	output reg [31:0] M_pre_pc_o
);
	always@ (posedge clk_i) begin
		if (M_bubble_i) begin
			M_opcode_o <= 7'd0;
			M_funct_o <= 10'd0;
			M_valE_o <= 32'd0;
			M_val2_o <= 32'd0;
			M_rd_o <= 5'd0;
			M_default_pc_o <= 32'd0;
			
			M_instr_o <= 32'd0;
			M_commit_o <= 1'd0;
			M_pc_o <= 32'd0;
			M_pre_pc_o <= 32'd0;
		end
		else if (~M_stall_i) begin
			M_opcode_o <= E_opcode_i;
			M_funct_o <= E_funct_i;
			M_valE_o <= e_valE_i;
			M_val2_o <= E_val2_i;
			M_rd_o <= E_rd_i;
			M_default_pc_o <= E_default_pc_i;

			M_instr_o <= E_instr_i;
			M_commit_o <= E_commit_i;
			M_pc_o <= E_pc_i;
			M_pre_pc_o <= e_Cnd_i ? e_valE_i : E_pre_pc_i;
		end
	end
endmodule