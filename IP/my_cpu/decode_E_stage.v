`include "define.v"
module decode_E_stage(
	input wire clk_i,
	input wire E_stall_i,
	input wire E_bubble_i,
	input wire [2:0] D_instr_type_i,
	input wire [6:0] D_opcode_i,
	input wire [9:0] D_funct_i,
	input wire [31:0] d_val1_i,
	input wire [31:0] d_val2_i,
	input wire [31:0] D_imm_i,
	input wire [4:0] D_rd_i,
	input wire [31:0] D_default_pc_i,

	input wire [31:0] D_instr_i,
	input wire D_commit_i,
	input wire [31:0] D_pc_i,
	input wire [31:0] D_pre_pc_i,
	
	output reg [2:0] E_instr_type_o,
	output reg [6:0] E_opcode_o,
	output reg [9:0] E_funct_o,
	output reg [31:0] E_val1_o,
	output reg [31:0] E_val2_o,
	output reg [31:0] E_imm_o,
	output reg [4:0] E_rd_o,
	output reg [31:0] E_default_pc_o,

	output reg [31:0] E_instr_o,
	output reg E_commit_o,
	output reg [31:0] E_pc_o,
	output reg [31:0] E_pre_pc_o
);
	always@ (posedge clk_i) begin
		if (E_bubble_i) begin
			E_instr_type_o <= 3'd0;
			E_opcode_o <= 7'd0;
			E_funct_o <= 10'd0;
			E_val1_o <= 32'd0;
			E_val2_o <= 32'd0;
			E_imm_o <= 32'd0;
			E_rd_o <= 5'd0;
			E_default_pc_o <= 32'd0;
			
			E_instr_o <= 32'd0;
			E_commit_o <= 1'd0;
			E_pc_o <= 32'd0;
			E_pre_pc_o <= 32'd0;
		end
		else if (~E_stall_i) begin
			E_instr_type_o <= D_instr_type_i;
			E_opcode_o <= D_opcode_i;
			E_funct_o <= D_funct_i;
			E_val1_o <= d_val1_i;
			E_val2_o <= d_val2_i;
			E_imm_o <= D_imm_i;
			E_rd_o <= D_rd_i;
			E_default_pc_o <= D_default_pc_i;

			E_instr_o <= D_instr_i;
			E_commit_o <= D_commit_i;
			E_pc_o <= D_pc_i;
			E_pre_pc_o <= D_pre_pc_i;
		end
	end
endmodule