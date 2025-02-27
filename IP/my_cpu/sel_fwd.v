`include "define.v"
module sel_fwd(
	input wire e_valid,
	input wire [6:0] E_opcode,
	input wire [4:0] E_rd,
	input wire [31:0] e_valE,
	input wire [31:0] E_default_pc,
	
	input wire m_valid,
	input wire [6:0] M_opcode,
	input wire [4:0] M_rd,
	input wire [31:0] M_valE,
	input wire [31:0] m_valM,
	input wire [31:0] M_default_pc,

	input wire w_valid,
	input wire [6:0] W_opcode,
	input wire [4:0] W_rd,
	input wire [31:0] W_valE,
	input wire [31:0] W_valM,
	input wire [31:0] W_default_pc,

	input wire [4:0] rs,
	input wire [31:0] rval,

	output wire [31:0] fwd_val
);
	wire E_w_en = (E_opcode == `OP_LOAD) | (E_opcode == `OP_JAL)
		| (E_opcode == `OP_JALR) | (E_opcode == `OP_R)
		| (E_opcode == `OP_IMM) | (E_opcode == `OP_LUI)
		| (E_opcode == `OP_AUIPC);
	wire M_w_en = (M_opcode == `OP_LOAD) | (M_opcode == `OP_JAL)
		| (M_opcode == `OP_JALR) | (M_opcode == `OP_R)
		| (M_opcode == `OP_IMM) | (M_opcode == `OP_LUI)
		| (M_opcode == `OP_AUIPC);
	wire W_w_en = (W_opcode == `OP_LOAD) | (W_opcode == `OP_JAL)
		| (W_opcode == `OP_JALR) | (W_opcode == `OP_R)
		| (W_opcode == `OP_IMM) | (W_opcode == `OP_LUI)
		| (W_opcode == `OP_AUIPC);

	assign fwd_val = (E_rd == rs && E_w_en && E_rd != 5'd0 && e_valid) ? 
		((E_opcode == `OP_JAL || E_opcode == `OP_JALR) ? E_default_pc
		: e_valE)
		: (M_rd == rs && M_w_en && M_rd != 5'd0 && m_valid) ?
		((M_opcode == `OP_LOAD) ? m_valM
		: (M_opcode == `OP_JAL || M_opcode == `OP_JALR) ? M_default_pc
		: M_valE)
		: (W_rd == rs && W_w_en && W_rd != 5'd0 && w_valid) ? 
		((W_opcode == `OP_LOAD) ? W_valM
		: (W_opcode == `OP_JAL || W_opcode == `OP_JALR) ? W_default_pc
		: W_valE)
		: rval;
endmodule
	