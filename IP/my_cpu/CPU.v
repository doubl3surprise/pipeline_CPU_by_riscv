`include "define.v"
module CPU(
	input wire clk,
	input wire rst,
	output wire [31:0] cur_pc,
	output wire [31:0] instr,
    output commit,
    output wire [31:0] commit_pc,
    output wire [31:0] commit_pre_pc
);
	reg F_stall;
	reg F_bubble;
	reg D_stall;
	reg D_bubble;
	reg E_stall;
	reg E_bubble;
	reg M_stall;
	reg M_bubble;
	reg W_stall;
	reg W_bubble;
	wire [31:0] F_pc;
	wire [6:0] f_opcode;
	wire [4:0] f_rd;
	wire [9:0] f_funct;
	wire [4:0] f_rs1;
	wire [4:0] f_rs2;
	wire [31:0] f_imm;
	wire [2:0] f_instr_type;
	wire f_imem_error;
	wire [31:0] f_default_pc;
	wire [31:0] f_instr;
	wire f_commit;
	wire [31:0] D_pc;
	wire [6:0] D_opcode;
	wire [4:0] D_rd;
	wire [9:0] D_funct;
	wire [4:0] D_rs1;
	wire [4:0] D_rs2;
	wire [31:0] D_imm;
	wire [2:0] D_instr_type;
	wire [31:0] D_default_pc;
	wire [31:0] D_instr;
	wire D_commit;
	wire [31:0] D_pre_pc;
	wire [31:0] d_val1;
    wire [31:0] d_val2;
	wire [2:0] E_instr_type;
	wire [6:0] E_opcode;
	wire [9:0] E_funct;
	wire [31:0] E_val1;
	wire [31:0] E_val2;
	wire [31:0] E_imm;
	wire [4:0] E_rd;
	wire [31:0] E_default_pc;
	wire [31:0] E_instr;
	wire E_commit;
	wire [31:0] E_pc;
	wire [31:0] E_pre_pc;
	wire [31:0] e_valE;
	wire e_Cnd;
	wire [6:0] M_opcode;
	wire [9:0] M_funct;
	wire [31:0] M_valE;
	wire [31:0] M_val2;
	wire [4:0] M_rd;
	wire [31:0] M_default_pc;
	wire [31:0] M_instr;
	wire M_commit;
	wire [31:0] M_pc;
	wire [31:0] M_pre_pc;
	wire [31:0] m_valM;

	wire [6:0] W_opcode;
	wire [4:0] W_rd;
	wire [31:0] W_valE;
	wire [31:0] W_valM;
	wire [31:0] W_default_pc;

	wire [31:0] W_instr;
	wire W_commit;
	wire [31:0] W_pc;
	wire [31:0] W_pre_pc;

	reg [31:0] nw_pc;

	fetch fet(
		.F_pc_i(F_pc),
		.f_opcode_o(f_opcode),
		.f_rd_o(f_rd),
		.f_funct_o(f_funct),
		.f_rs1_o(f_rs1),
		.f_rs2_o(f_rs2),
		.f_imm_o(f_imm),
		.f_instr_type_o(f_instr_type),
		.f_imem_error_o(f_imem_error),
		.f_default_pc_o(f_default_pc),
		.f_instr_o(f_instr),
		.f_commit_o(f_commit)
	);

	fetch_D_stage fD_stage(
		.clk_i(clk),
		.D_stall_i(D_stall),
		.D_bubble_i(D_bubble),
		.F_pc_i(F_pc),
		.f_opcode_i(f_opcode),
		.f_rd_i(f_rd),
		.f_funct_i(f_funct),
		.f_rs1_i(f_rs1),
		.f_rs2_i(f_rs2),
		.f_imm_i(f_imm),
		.f_instr_type_i(f_instr_type),
		.f_default_pc_i(f_default_pc),

		.f_instr_i(f_instr),
		.f_commit_i(f_commit),

		.D_pc_o(D_pc),
		.D_opcode_o(D_opcode),
		.D_rd_o(D_rd),
		.D_funct_o(D_funct),
		.D_rs1_o(D_rs1),
		.D_rs2_o(D_rs2),
		.D_imm_o(D_imm),
		.D_instr_type_o(D_instr_type),
		.D_default_pc_o(D_default_pc),
	
		.D_instr_o(D_instr),
		.D_commit_o(D_commit),
		.D_pre_pc_o(D_pre_pc)
	);

	decode dec(
		.clk_i(clk),
		.rst_i(rst),
		.D_instr_type_i(D_instr_type),
		.D_funct_i(D_funct),
		.D_rs1_i(D_rs1),
		.D_rs2_i(D_rs2),
		
		.W_opcode_i(W_opcode),
		.W_rd_i(W_rd),
		.W_valE_i(W_valE),
		.W_valM_i(W_valM),
		.W_default_pc_i(W_default_pc),
		
		.M_opcode_i(M_opcode),
		.M_rd_i(M_rd),
		.M_valE_i(M_valE),
		.m_valM_i(m_valM),
		.M_default_pc_i(M_default_pc),

		.E_opcode_i(E_opcode),
		.E_rd_i(E_rd),
		.e_valE_i(e_valE),
		.E_default_pc_i(E_default_pc),

		.d_val1_o(d_val1),
		.d_val2_o(d_val2)
	);
	
	decode_E_stage dE_stage(
		.clk_i(clk),
		.E_stall_i(E_stall),
		.E_bubble_i(E_bubble),
		.D_instr_type_i(D_instr_type),
		.D_opcode_i(D_opcode),
		.D_funct_i(D_funct),
		.d_val1_i(d_val1),
		.d_val2_i(d_val2),
		.D_imm_i(D_imm),
		.D_rd_i(D_rd),
		.D_default_pc_i(D_default_pc),

		.D_instr_i(D_instr),
		.D_commit_i(D_commit),
		.D_pc_i(D_pc),
		.D_pre_pc_i(D_pre_pc),

		.E_instr_type_o(E_instr_type),
		.E_opcode_o(E_opcode),
		.E_funct_o(E_funct),
		.E_val1_o(E_val1),
		.E_val2_o(E_val2),
		.E_imm_o(E_imm),
		.E_rd_o(E_rd),
		.E_default_pc_o(E_default_pc),

		.E_instr_o(E_instr),
		.E_commit_o(E_commit),
		.E_pc_o(E_pc),
		.E_pre_pc_o(E_pre_pc)
	);

	execute exc(
		.clk_i(clk),
		.E_instr_type_i(E_instr_type),
		.E_opcode_i(E_opcode),
		.E_val1_i(E_val1), 
		.E_val2_i(E_val2),
		.E_imm_i(E_imm),
		.E_funct_i(E_funct),
		.E_pc_i(E_pc),

		.e_valE_o(e_valE),
		.e_Cnd_o(e_Cnd)
	);

	execute_M_stage eM_stage(
		.clk_i(clk),
		.M_stall_i(M_stall),
		.M_bubble_i(M_bubble),
		.E_opcode_i(E_opcode),
		.E_funct_i(E_funct),
		.e_valE_i(e_valE),
		.E_val2_i(E_val2),
		.E_rd_i(E_rd),
		.E_default_pc_i(E_default_pc),

		.E_instr_i(E_instr),
		.E_commit_i(E_commit),
		.E_pc_i(E_pc),
		.E_pre_pc_i(E_pre_pc),

		.e_Cnd_i(e_Cnd),

		.M_opcode_o(M_opcode),
		.M_funct_o(M_funct),
		.M_valE_o(M_valE),
		.M_val2_o(M_val2),
		.M_rd_o(M_rd),
		.M_default_pc_o(M_default_pc),

		.M_instr_o(M_instr),
		.M_commit_o(M_commit),
		.M_pc_o(M_pc),
		.M_pre_pc_o(M_pre_pc)
	);
	
	memory_access mem_acc(
		.clk_i(clk),
		.M_opcode_i(M_opcode),
		.M_funct_i(M_funct),
		.M_valE_i(M_valE),
		.M_val2_i(M_val2),
		.m_valM_o(m_valM)
	);

	memory_access_W_stage mW_stage(
		.clk_i(clk),
		.W_stall_i(W_stall),
		.W_bubble_i(W_bubble),
		.M_opcode_i(M_opcode),
		.M_rd_i(M_rd),
		.M_valE_i(M_valE),
		.m_valM_i(m_valM),
		.M_default_pc_i(M_default_pc),
		
		.M_instr_i(M_instr),
		.M_commit_i(M_commit),
		.M_pc_i(M_pc),
		.M_pre_pc_i(M_pre_pc),

		.W_opcode_o(W_opcode),
		.W_rd_o(W_rd),
		.W_valE_o(W_valE),
		.W_valM_o(W_valM),
		.W_default_pc_o(W_default_pc),
	
		.W_instr_o(W_instr),
		.W_commit_o(W_commit),
		.W_pc_o(W_pc),
		.W_pre_pc_o(W_pre_pc)
	);

	write_back wb(
		.W_instr_i(W_instr)
	);
    	
	control con(
		.E_opcode_i(E_opcode),
		.e_Cnd_i(e_Cnd),
		.E_rd_i(E_rd),
		.D_rs1_i(D_rs1),
		.D_rs2_i(D_rs2),
		
		.F_bubble_o(F_bubble),
		.D_bubble_o(D_bubble),
		.E_bubble_o(E_bubble),
		.M_bubble_o(M_bubble),
		.W_bubble_o(W_bubble),
		.F_stall_o(F_stall),
		.D_stall_o(D_stall),
		.E_stall_o(E_stall),
		.M_stall_o(M_stall),
		.W_stall_o(W_stall)
	);

	sel_pc spc(
		.clk_i(clk),
    	.rst_i(rst),
		.F_stall_i(F_stall),
		.F_bubble_i(F_bubble),

		.F_pc_i(F_pc),
		.E_opcode_i(E_opcode),
		.e_Cnd_i(e_Cnd),
		.e_valE_i(e_valE),
		.f_default_pc_i(f_default_pc),

    	.F_pc_o(F_pc)
	);

	assign cur_pc = F_pc;
	assign instr = W_instr;
	assign commit = W_commit;
	assign commit_pc = W_pc;
	assign commit_pre_pc = W_pre_pc;
endmodule