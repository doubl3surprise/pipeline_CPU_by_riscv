`include "define.v"
module memory_access_W_stage(
	input wire clk_i,
	input wire W_stall_i,
	input wire W_bubble_i,
	input wire [6:0] M_opcode_i,
	input wire [4:0] M_rd_i,
	input wire [31:0] M_valE_i,
	input wire [31:0] m_valM_i,
	input wire [31:0] M_default_pc_i,

	input wire [31:0] M_instr_i,
	input wire M_commit_i,
	input wire [31:0] M_pc_i,
	input wire [31:0] M_pre_pc_i,

	output reg [6:0] W_opcode_o,
	output reg [4:0] W_rd_o,
	output reg [31:0] W_valE_o,
	output reg [31:0] W_valM_o,
	output reg [31:0] W_default_pc_o,

	output reg [31:0] W_instr_o,
	output reg W_commit_o,
	output reg [31:0] W_pc_o,
	output reg [31:0] W_pre_pc_o
);
	always@ (posedge clk_i) begin
		if (W_bubble_i) begin
			W_opcode_o <= 7'd0;
			W_rd_o <= 5'd0;
			W_valE_o <= 32'd0;
			W_valM_o <= 32'd0;
			W_default_pc_o <= 32'd0;

			W_instr_o <= 32'd0;
			W_commit_o <= 1'd0;
			W_pc_o <= 32'd0;
			W_pre_pc_o <= 32'd0;
		end
		else if (~W_stall_i) begin
			W_opcode_o <= M_opcode_i;
			W_rd_o <= M_rd_i;
			W_valE_o <= M_valE_i;
			W_valM_o <= m_valM_i;
			W_default_pc_o <= M_default_pc_i;

			W_instr_o <= M_instr_i;
			W_commit_o <= M_commit_i;
			W_pc_o <= M_pc_i;
			W_pre_pc_o <= M_pre_pc_i;
		end
	end
endmodule