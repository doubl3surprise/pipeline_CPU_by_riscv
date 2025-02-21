`include "define.v"
module execute(
	input wire clk_i,
	input wire [2:0] E_instr_type_i,
	input wire [6:0] E_opcode_i,
	input wire [31:0] E_val1_i, 
	input wire [31:0] E_val2_i, 
	input wire [31:0] E_imm_i,
	input wire [9:0] E_funct_i,
	input wire [31:0] E_pc_i,
	output reg [31:0] e_valE_o,
	output wire e_Cnd_o
);
	wire is_b_type = (E_instr_type_i == `TYPEB);
	wire is_jal = (E_opcode_i == `OP_JAL);
	wire is_auipc = (E_opcode_i == `OP_AUIPC);
	wire is_r_type = (E_opcode_i == `OP_R);
	wire is_i_type = (E_opcode_i == `OP_IMM);
	wire is_lui_type = (E_opcode_i == `OP_LUI);

	wire [31:0] alu1 = (is_auipc | is_jal | is_b_type) 
		? E_pc_i : (is_lui_type ? 32'd0 : E_val1_i);
	wire [31:0] alu2 = (is_auipc | is_jal | is_b_type | 
		(E_instr_type_i == `TYPEU) | 
		(E_instr_type_i == `TYPEI) | 
		(E_instr_type_i == `TYPES)) ? 
			E_imm_i : E_val2_i;

	wire [9:0] alu_fun;
	assign alu_fun = (is_r_type | is_i_type) ? E_funct_i : `ALUADD;

	always @(*) begin
		case (alu_fun)
			`ALUADD  : e_valE_o = alu1 + alu2;
			`ALUSUB  : e_valE_o = alu1 - alu2;
			`ALUSLL  : e_valE_o = alu1 << alu2[4:0];
			`ALUSLT  : e_valE_o = ($signed(alu1) < $signed(alu2)) ? 1 : 0;
			`ALUSLTU : e_valE_o = (alu1 < alu2) ? 1 : 0;
			`ALUXOR  : e_valE_o = alu1 ^ alu2;
			`ALUSRL  : e_valE_o = alu1 >> alu2[4:0];
			`ALUSRA  : e_valE_o = $signed(alu1) >>> alu2[4:0];
			`ALUOR   : e_valE_o = alu1 | alu2;
			`ALUAND  : e_valE_o = alu1 & alu2;
			default  : e_valE_o = 0;
		endcase
	end
	/*
	always@ (*) begin
		if(E_instr_type_i == `TYPEB) begin
			e_Cnd_o = 
				(E_funct_i == `FUNC_BEQ && E_val1_i == E_val2_i) ||
				(E_funct_i == `FUNC_BNE && E_val1_i != E_val2_i) ||
				(E_funct_i == `FUNC_BLT && $signed(E_val1_i) < $signed(E_val2_i)) ||
				(E_funct_i == `FUNC_BGE && $signed(E_val1_i) >= $signed(E_val2_i)) ||
				(E_funct_i == `FUNC_BLTU && E_val1_i < E_val2_i) ||
				(E_funct_i == `FUNC_BGEU && E_val1_i >= E_val2_i);
		end
		else if(E_instr_type_i == `TYPEJ) begin
			e_Cnd_o = 1;
		end
		else begin
			e_Cnd_o = 0;
		end
		
	end
	*/

	assign e_Cnd_o = 
		(E_instr_type_i == `TYPEB && E_funct_i == `FUNC_BEQ && E_val1_i == E_val2_i) ||
		(E_instr_type_i == `TYPEB && E_funct_i == `FUNC_BNE && E_val1_i != E_val2_i) ||
		(E_instr_type_i == `TYPEB && E_funct_i == `FUNC_BLT && $signed(E_val1_i) < $signed(E_val2_i)) ||
		(E_instr_type_i == `TYPEB && E_funct_i == `FUNC_BGE && $signed(E_val1_i) >= $signed(E_val2_i)) ||
		(E_instr_type_i == `TYPEB && E_funct_i == `FUNC_BLTU && E_val1_i < E_val2_i) ||
		(E_instr_type_i == `TYPEB && E_funct_i == `FUNC_BGEU && E_val1_i >= E_val2_i) ||
		(E_instr_type_i == `TYPEJ) || 
		(E_opcode_i == `OP_JALR);
	
endmodule