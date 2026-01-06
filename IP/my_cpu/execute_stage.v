`include "define.v"
module execute_stage #(
	parameter N = 12,
	parameter integer RAS_W = 4,
    parameter integer RAS_DEPTH = 16
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
	input wire [RAS_W - 1:0] D_ras_sp,
    input wire [RAS_DEPTH * 32 - 1:0] D_ras_snapshot,
    input wire [N - 1:0] D_lht_hist,
    input wire D_gpred_taken,
    input wire D_lpred_taken,
	
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
	output reg [RAS_W - 1:0] E_ras_sp,
    output reg [RAS_DEPTH * 32 - 1:0] E_ras_snapshot,
    output reg [N - 1:0] E_lht_hist,
    output reg E_gpred_taken,
    output reg E_lpred_taken,

	output wire [2:0] e_func3_out,

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
    // ==================== CSR / SYSTEM ====================
    wire is_system = (E_opcode == `OP_SYSTEM);
    wire [2:0] sys_funct3 = E_instr[14:12];
    wire [11:0] sys_imm12 = E_instr[31:20];
    wire [4:0]  sys_rs1   = E_instr[19:15];

    wire csr_inst  = is_system && (sys_funct3 != 3'b000);
    wire is_ecall  = is_system && (sys_funct3 == 3'b000) && (sys_imm12 == 12'h000);
    wire is_mret   = is_system && (sys_funct3 == 3'b000) && (sys_imm12 == 12'h302);
    // ebreak is handled by write_back_stage (dpi_ebreak)
    wire is_ebreak = is_system && (sys_funct3 == 3'b000) && (sys_imm12 == 12'h001);

    wire csr_is_imm = sys_funct3[2];
    wire [31:0] csr_src = csr_is_imm ? {27'd0, sys_rs1} : E_val1;

    wire [31:0] csr_rdata;
    wire [31:0] csr_mtvec;
    wire [31:0] csr_mepc;

    // retire count: approximate with writeback commit (wired in from CPU top later if needed)
    wire instret_inc = E_commit && e_valid;

    csr_file u_csr (
        .clk        (clk),
        .rst        (rst),
        .csr_access (csr_inst && e_valid),
        .csr_funct3 (sys_funct3),
        .csr_addr   (sys_imm12),
        .csr_src    (csr_src),
        .csr_rdata  (csr_rdata),
        .do_ecall   (is_ecall && e_valid),
        .do_mret    (is_mret && e_valid),
        .cur_pc     (E_pc),
        .mtvec_out  (csr_mtvec),
        .mepc_out   (csr_mepc),
        .instret_inc(instret_inc)
    );

    wire sys_redirect = (is_ecall || is_mret) && e_valid;
    wire [31:0] sys_target = is_mret ? csr_mepc : csr_mtvec;

	assign e_func3_out = E_funct[2:0];

    // ==================== End CSR / SYSTEM ====================

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

	// mul (Radix-4 Booth + Wallace tree)
	wire [63:0] mul_prod;
	wire mul_a_signed;
	wire mul_b_signed;
	assign mul_a_signed = (alu_fun == `ALUMUL) || (alu_fun == `ALUMULH) || (alu_fun == `ALUMULHSU);
	assign mul_b_signed = (alu_fun == `ALUMUL) || (alu_fun == `ALUMULH);

	booth_wallace_mul u_booth_mul (
		.a(alu1),
		.b(alu2),
		.is_a_sign(mul_a_signed),
		.is_b_sign(mul_b_signed),
		.product(mul_prod)
	);

	// div/rem (combinational long division)
	wire [31:0] div_quot;
	wire [31:0] div_rem;
	div_long u_div (
		.dividend(alu1),
		.divisor(alu2),
		.is_signed((alu_fun == `ALUDIV) || (alu_fun == `ALUREM)),
		.quot(div_quot),
		.rem(div_rem)
	);

	// ALU operation
    always @(*) begin
        if (csr_inst) begin
            // CSR instructions write old CSR value to rd
            e_valE = csr_rdata;
        end else begin
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
			    `ALUMUL  : e_valE = mul_prod[31:0];
			    `ALUMULH : e_valE = mul_prod[63:32];
			    `ALUMULHSU: e_valE = mul_prod[63:32];
			    `ALUMULHU: e_valE = mul_prod[63:32];
			    `ALUDIV  : e_valE = div_quot;
			    `ALUDIVU : e_valE = div_quot;
			    `ALUREM  : e_valE = div_rem;
			    `ALUREMU : e_valE = div_rem;
			    default  : e_valE = 0;
		    endcase
        end
	end

    assign can_jump = sys_redirect ||
        (((E_instr_type == `TYPEB && E_funct == `FUNC_BEQ && E_val1 == E_val2) ||
		(E_instr_type == `TYPEB && E_funct == `FUNC_BNE && E_val1 != E_val2) ||
		(E_instr_type == `TYPEB && E_funct == `FUNC_BLT && $signed(E_val1) < $signed(E_val2)) ||
		(E_instr_type == `TYPEB && E_funct == `FUNC_BGE && $signed(E_val1) >= $signed(E_val2)) ||
		(E_instr_type == `TYPEB && E_funct == `FUNC_BLTU && E_val1 < E_val2) ||
		(E_instr_type == `TYPEB && E_funct == `FUNC_BGEU && E_val1 >= E_val2) ||
		(E_instr_type == `TYPEJ) || 
		(E_opcode == `OP_JALR)) & e_valid);

	assign jump_target = sys_redirect ? sys_target :
        (can_jump ? ((E_opcode == `OP_JAL) ? (e_valE & -1) : e_valE) : E_default_pc);

	// prediction success: predicted next pc equals the resolved next pc
	assign fact_success = E_is_jump_instr && (jump_target == E_pred_pc) & e_valid;

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
			E_ras_sp <= D_ras_sp;
            E_ras_snapshot <= D_ras_snapshot;
            E_lht_hist <= D_lht_hist;
            E_gpred_taken <= D_gpred_taken;
            E_lpred_taken <= D_lpred_taken;
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
			E_ras_sp <= {RAS_W{1'b0}};
            E_ras_snapshot <= {RAS_DEPTH * 32{1'b0}};
            E_lht_hist <= {N{1'b0}};
            E_gpred_taken <= 1'b0;
            E_lpred_taken <= 1'b0;
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
        
