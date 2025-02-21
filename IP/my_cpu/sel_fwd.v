`include "define.v"
module sel_fwd(
	input wire [6:0] E_opcode_i,
	input wire [4:0] E_rd_i,
	input wire [31:0] e_valE_i,
	input wire [31:0] E_default_pc_i,
	
	input wire [6:0] M_opcode_i,
	input wire [4:0] M_rd_i,
	input wire [31:0] M_valE_i,
	input wire [31:0] m_valM_i,
	input wire [31:0] M_default_pc_i,

	input wire [6:0] W_opcode_i,
	input wire [4:0] W_rd_i,
	input wire [31:0] W_valE_i,
	input wire [31:0] W_valM_i,
	input wire [31:0] W_default_pc_i,

	input wire [4:0] rs_i,
	input wire [31:0] rval_i,

	output wire [31:0] fwd_val_o
);
	wire E_w_en = (E_opcode_i == `OP_LOAD) | (E_opcode_i == `OP_JAL)
		| (E_opcode_i == `OP_JALR) | (E_opcode_i == `OP_R)
		| (E_opcode_i == `OP_IMM) | (E_opcode_i == `OP_LUI)
		| (E_opcode_i == `OP_AUIPC);
	wire M_w_en = (M_opcode_i == `OP_LOAD) | (M_opcode_i == `OP_JAL)
		| (M_opcode_i == `OP_JALR) | (M_opcode_i == `OP_R)
		| (M_opcode_i == `OP_IMM) | (M_opcode_i == `OP_LUI)
		| (M_opcode_i == `OP_AUIPC);
	wire W_w_en = (W_opcode_i == `OP_LOAD) | (W_opcode_i == `OP_JAL)
		| (W_opcode_i == `OP_JALR) | (W_opcode_i == `OP_R)
		| (W_opcode_i == `OP_IMM) | (W_opcode_i == `OP_LUI)
		| (W_opcode_i == `OP_AUIPC);

	assign fwd_val_o = (E_rd_i == rs_i && E_w_en && E_rd_i != 5'd0) ? 
		((E_opcode_i == `OP_JAL || E_opcode_i == `OP_JALR) ? E_default_pc_i
		: e_valE_i)
		: (M_rd_i == rs_i && M_w_en && M_rd_i != 5'd0) ?
		((M_opcode_i == `OP_LOAD) ? m_valM_i
		: (M_opcode_i == `OP_JAL || M_opcode_i == `OP_JALR) ? M_default_pc_i
		: M_valE_i)
		: (W_rd_i == rs_i && W_w_en && W_rd_i != 5'd0) ? 
		((W_opcode_i == `OP_LOAD) ? W_valM_i
		: (W_opcode_i == `OP_JAL || W_opcode_i == `OP_JALR) ? W_default_pc_i
		: W_valE_i)
		: rval_i;
endmodule
	