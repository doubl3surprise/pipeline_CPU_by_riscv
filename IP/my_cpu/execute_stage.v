`include "define.v"
module execute_stage #(
	parameter N = 12
) (
	input wire clk,
	input wire rst,
	
	// touch signal
	output wire e_allow_in,
	input wire d_to_e_valid,
	input wire m_allow_in,
	output wire e_to_m_valid,

	// stage valid
    output reg e_valid,
	
	// exceute signal
    output reg [31:0] e_valE,

	// branch signal
	output wire can_jump,
    output wire [31:0] jump_target,
	output wire fact_success,

	// decode and exceute register
	input wire [31:0] D_pc,
    input wire [2:0] D_instr_type,
	input wire [6:0] D_opcode,
	input wire [9:0] D_funct,
	input wire [31:0] d_val1,
	input wire [31:0] d_val2,
	input wire [31:0] D_imm,
	input wire [4:0] D_rd,
	input wire [31:0] D_default_pc,
	input wire D_is_jump_instr,
	input wire D_pred_taken,
	input wire [N - 1:0] D_pred_history,
	
	output reg [31:0] E_pc,
	output reg [2:0] E_instr_type,
	output reg [6:0] E_opcode,
	output reg [9:0] E_funct,
	output reg [31:0] E_val1,
	output reg [31:0] E_val2,
	output reg [31:0] E_imm,
	output reg [4:0] E_rd,
	output reg [31:0] E_default_pc,
	output reg E_is_jump_instr,
	output reg E_pred_taken,
	output reg [N - 1:0] E_pred_history,

	// signal for cpu interface
	input wire [31:0] D_cur_pc,
    input wire [31:0] D_instr,
    input wire D_commit,
    input wire [31:0] D_pred_pc,

    output reg [31:0] E_cur_pc,
    output reg [31:0] E_instr,
    output reg E_commit,
    output reg [31:0] E_pred_pc
);
	// execute function
    wire is_b = (E_instr_type == `TYPEB);
    wire is_r = (E_instr_type == `TYPER);
    wire is_u = (E_instr_type == `TYPEU);
    wire is_i = (E_instr_type == `TYPEI);
    wire is_s = (E_instr_type == `TYPES);

	wire is_jal = (E_opcode == `OP_JAL);
	wire is_auipc = (E_opcode == `OP_AUIPC);
	wire is_imm = (E_opcode == `OP_IMM);
	wire is_lui = (E_opcode == `OP_LUI);

	wire [31:0] alu1 = (is_auipc | is_jal | is_b) 
		? E_pc : (is_lui ? 32'd0 : E_val1);
	wire [31:0] alu2 = (is_auipc | is_jal | is_b | 
		is_u | is_i | is_s) ? E_imm : E_val2;

    wire [9:0] alu_fun;
	assign alu_fun = (is_r | is_imm) ? E_funct : `ALUADD;

    always @(*) begin
		case (alu_fun)
			`ALUADD  : e_valE = alu1 + alu2;
			`ALUSUB  : e_valE = alu1 - alu2;
			`ALUSLL  : e_valE = alu1 << alu2[4:0];
			`ALUSLT  : e_valE = ($signed(alu1) < $signed(alu2)) ? 1 : 0;
			`ALUSLTU : e_valE = (alu1 < alu2) ? 1 : 0;
			`ALUXOR  : e_valE = alu1 ^ alu2;
			`ALUSRL  : e_valE = alu1 >> alu2[4:0];
			`ALUSRA  : e_valE = $signed(alu1) >>> alu2[4:0];
			`ALUOR   : e_valE = alu1 | alu2;
			`ALUAND  : e_valE = alu1 & alu2;
			default  : e_valE = 0;
		endcase
	end

    assign can_jump =((E_instr_type == `TYPEB && E_funct == `FUNC_BEQ && E_val1 == E_val2) ||
		(E_instr_type == `TYPEB && E_funct == `FUNC_BNE && E_val1 != E_val2) ||
		(E_instr_type == `TYPEB && E_funct == `FUNC_BLT && $signed(E_val1) < $signed(E_val2)) ||
		(E_instr_type == `TYPEB && E_funct == `FUNC_BGE && $signed(E_val1) >= $signed(E_val2)) ||
		(E_instr_type == `TYPEB && E_funct == `FUNC_BLTU && E_val1 < E_val2) ||
		(E_instr_type == `TYPEB && E_funct == `FUNC_BGEU && E_val1 >= E_val2) ||
		(E_instr_type == `TYPEJ) || 
		(E_opcode == `OP_JALR)) & e_valid;

	assign jump_target = can_jump ? ((E_opcode == `OP_JAL) ? (e_valE & -1) : e_valE) : E_default_pc;

	assign fact_success = E_is_jump_instr && (jump_target == E_pc) & e_valid;

	// pipeline control
    wire e_ready_go = 1;
    assign e_allow_in = ~e_valid || (e_ready_go && m_allow_in);
    always@ (posedge clk) begin
        if (rst) e_valid <= 1'd0;
		else if (!fact_success && E_is_jump_instr && e_valid) e_valid <= 1'b0;
        else if (e_allow_in) e_valid <= d_to_e_valid;
    end
    assign e_to_m_valid = e_valid && e_ready_go;

    // decode to execute register update
    always@ (posedge clk) begin
        if (e_allow_in && d_to_e_valid) begin
			E_pc <= D_pc;
            E_instr_type <= D_instr_type;
			E_opcode <= D_opcode;
			E_funct <= D_funct;
			E_val1 <= d_val1;
			E_val2 <= d_val2;
			E_imm <= D_imm;
			E_rd <= D_rd;
			E_default_pc <= D_default_pc;
			E_is_jump_instr <= D_is_jump_instr;
			E_pred_taken <= D_pred_taken;
			E_pred_history <= D_pred_history;
        end
		else begin
			E_pc <= 32'd0;
            E_instr_type <= 3'd0;
			E_opcode <= 7'd0;
			E_funct <= 10'd0;
			E_val1 <= 32'd0;
			E_val2 <= 32'd0;
			E_imm <= 32'd0;
			E_rd <= 5'd0;
			E_default_pc <= 32'd0;
			E_is_jump_instr <= 1'd0;
			E_pred_taken <= 1'd0;
			E_pred_history <= 12'd0;
		end
    end

	// cpu interface update
	always@ (posedge clk) begin
		if (e_allow_in && d_to_e_valid) begin
            E_cur_pc <= D_cur_pc;
			E_instr <= D_instr;
			E_commit <= D_commit;
			E_pred_pc <= D_pred_pc;
        end
	end
endmodule
    