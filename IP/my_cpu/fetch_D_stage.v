`include "define.v"
module fetch_D_stage(
	input wire clk_i,
	input wire D_stall_i,
	input wire D_bubble_i,
	input wire [31:0] F_pc_i,
	input wire [6:0] f_opcode_i,
	input wire [4:0] f_rd_i,
	input wire [9:0] f_funct_i,
	input wire [4:0] f_rs1_i,
	input wire [4:0] f_rs2_i,
	input wire [31:0] f_imm_i,
	input wire [2:0] f_instr_type_i,
	input wire [31:0] f_default_pc_i,

	input wire [31:0] f_instr_i,
	input wire f_commit_i,

	output reg [31:0] D_pc_o,
	output reg [6:0] D_opcode_o,
	output reg [4:0] D_rd_o,
	output reg [9:0] D_funct_o,
	output reg [4:0] D_rs1_o,
	output reg [4:0] D_rs2_o,
	output reg [31:0] D_imm_o,
	output reg [2:0] D_instr_type_o,
	output reg [31:0] D_default_pc_o,
	
	output reg [31:0] D_instr_o,
	output reg D_commit_o,
	output reg [31:0] D_pre_pc_o
);
	always@ (posedge clk_i) begin
		if (D_bubble_i) begin
			D_pc_o <= 32'd0;
			D_opcode_o <= 7'd0;
			D_rd_o <= 5'd0;
			D_funct_o <= 10'd0;
			D_rs1_o <= 5'd0;
			D_rs2_o <= 5'd0;
			D_imm_o <= 32'd0;
			D_instr_type_o <= 3'd0;
			D_default_pc_o <= 32'd0;

			D_instr_o <= 32'd0;
			D_commit_o <= 1'd0;
		end
		else if (~D_stall_i) begin
			D_pc_o <= F_pc_i;
			D_opcode_o <= f_opcode_i;
			D_rd_o <= f_rd_i;
			D_funct_o <= f_funct_i;
			D_rs1_o <= f_rs1_i;
			D_rs2_o <= f_rs2_i;
			D_imm_o <= f_imm_i;
			D_instr_type_o <= f_instr_type_i;
			D_default_pc_o <= f_default_pc_i;

			D_instr_o <= f_instr_i;
			D_commit_o <= f_commit_i;
			D_pre_pc_o <= f_default_pc_i;
		end
	end
endmodule