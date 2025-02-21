`include "define.v"
module fetch(
	input  [31:0] F_pc_i,
	output [6:0]  f_opcode_o,
	output [4:0]  f_rd_o,
	output [9:0]  f_funct_o,
	output [4:0]  f_rs1_o,
	output [4:0]  f_rs2_o,
	output [31:0] f_imm_o,
	output [2:0]  f_instr_type_o,
	output        f_imem_error_o,
	output [31:0] f_default_pc_o,
	
	output [31:0] f_instr_o,
	output f_commit_o
);
    import "DPI-C" function int dpi_mem_read (input int addr, input int len);

	wire [31:0]  instr;
	wire [14:12] func3_bits;
	wire [31:25] func7_bits;
	wire [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
	wire is_jalr;
	wire funct_r_type, funct_istb;
	wire is_imm_i, is_imm_s, is_imm_b, is_imm_u, is_imm_j;
	
	assign instr = dpi_mem_read(F_pc_i, 4);
	assign f_instr_o = instr;
	assign f_commit_o = (F_pc_i >= 32'h80000000 && F_pc_i <= 32'h87ffffff) ? 1'b1 : 1'b0;

    assign func3_bits = instr[14:12];
    assign func7_bits = instr[31:25];
    assign f_opcode_o    = instr[6:0];
    assign f_rd_o        = instr[11:7];
    assign f_rs1_o       = instr[19:15];
    assign f_rs2_o       = instr[24:20];
    assign f_default_pc_o  = (F_pc_i >= 32'h80000000 && F_pc_i <= 32'h87ffffff) ? F_pc_i + 32'd4 : 32'd0;

    assign imm_i = {{20{instr[31]}}, instr[31:20]};
    assign imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    assign imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    assign imm_u = {instr[31:12], 12'b0};
    assign imm_j = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};

	assign f_instr_type_o = 
		(f_opcode_o == `OP_B)    ? `TYPEB :
		(f_opcode_o == `OP_S)    ? `TYPES :
		(f_opcode_o == `OP_JAL)  ? `TYPEJ :
		(f_opcode_o == `OP_JALR) ? `TYPEI :
		(f_opcode_o == `OP_R)    ? `TYPER :
		(f_opcode_o == `OP_IMM)  ? `TYPEI :
		(f_opcode_o == `OP_LOAD) ? `TYPEI :
		((f_opcode_o == `OP_LUI) || (f_opcode_o == `OP_AUIPC)) ? `TYPEU :
		3'd0;

	assign funct_r_type = (f_instr_type_o == `TYPER);
	assign funct_istb   = (f_instr_type_o == `TYPEI) || 
		(f_instr_type_o == `TYPES) || 
		(f_instr_type_o == `TYPEB);
	wire is_shift_imm = (f_opcode_o == `OP_IMM) && (func3_bits == 3'b001 || func3_bits == 3'b101);
	assign f_funct_o = funct_r_type ? {func7_bits, func3_bits} :
		(funct_istb && is_shift_imm) ? {func7_bits, func3_bits} : 
		funct_istb ? {7'b0, func3_bits} :
		10'd0;

	assign is_imm_i = (f_instr_type_o == `TYPEI);
	assign is_imm_s = (f_instr_type_o == `TYPES);
	assign is_imm_b = (f_instr_type_o == `TYPEB);
	assign is_imm_u = (f_instr_type_o == `TYPEU);
	assign is_imm_j = (f_instr_type_o == `TYPEJ);
	assign f_imm_o = ({32{is_imm_i}} & imm_i) |
		({32{is_imm_s}} & imm_s) |
		({32{is_imm_b}} & imm_b) |
		({32{is_imm_u}} & imm_u) |
		({32{is_imm_j}} & imm_j);
	/*
	initial begin
		$monitor("F_pc = %x\n", F_pc_i);
	end
	*/
endmodule