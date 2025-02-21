`include "define.v"
module decode(
	input wire clk_i,
	input wire rst_i,
	input wire [2:0] D_instr_type_i,
	input wire [9:0] D_funct_i,
    input wire [4:0] D_rs1_i,
    input wire [4:0] D_rs2_i,
	
	input wire [6:0] W_opcode_i,
	input wire [4:0] W_rd_i,
	input wire [31:0] W_valE_i,
	input wire [31:0] W_valM_i,
	input wire [31:0] W_default_pc_i,

	input wire [6:0] M_opcode_i,
	input wire [4:0] M_rd_i,
	input wire [31:0] M_valE_i,
	input wire [31:0] m_valM_i,
	input wire [31:0] M_default_pc_i,
	
	input wire [6:0] E_opcode_i,
	input wire [4:0] E_rd_i,
	input wire [31:0] e_valE_i,
	input wire [31:0] E_default_pc_i,

    output wire [31:0] d_val1_o,
    output wire [31:0] d_val2_o
);
	wire [31:0] rval1;
	wire [31:0] rval2;
	wire valid_src1 = (
		(D_instr_type_i == `TYPER) |  
		(D_instr_type_i == `TYPEI) |  
		(D_instr_type_i == `TYPES) |  
		(D_instr_type_i == `TYPEB)    
	);

	wire valid_src2 = (
		(D_instr_type_i == `TYPER) |  
		(D_instr_type_i == `TYPES) |  
		(D_instr_type_i == `TYPEB)    
	);
	
	wire w_en = (W_opcode_i == `OP_LOAD) | (W_opcode_i == `OP_JAL)
		| (W_opcode_i == `OP_JALR) | (W_opcode_i == `OP_R)
		| (W_opcode_i == `OP_IMM) | (W_opcode_i == `OP_LUI)
		| (W_opcode_i == `OP_AUIPC);
	
	wire [31:0] wdata;
	assign wdata = (W_opcode_i == `OP_LOAD) ? W_valM_i
		: (W_opcode_i == `OP_JAL || W_opcode_i == `OP_JALR) ? W_default_pc_i
		: W_valE_i;

    access_register_file reg_file (
		.clk_i(clk_i),
		.rst_i(rst_i),
        .rs1_i(D_rs1_i),
        .rs2_i(D_rs2_i),
        .valid_src1_i(valid_src1),
        .valid_src2_i(valid_src2),
		
		.w_en_i(w_en),
		.rd_i(W_rd_i),
		.wdata_i(wdata),

        .val1_o(rval1),
        .val2_o(rval2)
    );

	sel_fwd sf1 (
		.E_opcode_i(E_opcode_i),
		.E_rd_i(E_rd_i),
		.e_valE_i(e_valE_i),
		.E_default_pc_i(E_default_pc_i),
		
		.M_opcode_i(M_opcode_i),
		.M_rd_i(M_rd_i),
		.M_valE_i(M_valE_i),
		.m_valM_i(m_valM_i),
		.M_default_pc_i(M_default_pc_i),

		.W_opcode_i(W_opcode_i),
		.W_rd_i(W_rd_i),
		.W_valE_i(W_valE_i),
		.W_valM_i(W_valM_i),
		.W_default_pc_i(W_default_pc_i),
		
		.rs_i(D_rs1_i),
		.rval_i(rval1),

		.fwd_val_o(d_val1_o)
	);

	sel_fwd sf2(
		.E_opcode_i(E_opcode_i),
		.E_rd_i(E_rd_i),
		.e_valE_i(e_valE_i),
		.E_default_pc_i(E_default_pc_i),
		
		.M_opcode_i(M_opcode_i),
		.M_rd_i(M_rd_i),
		.M_valE_i(M_valE_i),
		.m_valM_i(m_valM_i),
		.M_default_pc_i(M_default_pc_i),

		.W_opcode_i(W_opcode_i),
		.W_rd_i(W_rd_i),
		.W_valE_i(W_valE_i),
		.W_valM_i(W_valM_i),
		.W_default_pc_i(W_default_pc_i),
		
		.rs_i(D_rs2_i),
		.rval_i(rval2),

		.fwd_val_o(d_val2_o)
	);
endmodule