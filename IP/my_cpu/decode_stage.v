`include "define.v"
module decode_stage(
    input wire clk,
    input wire rst,

	// touch signal
    output wire d_allow_in,
    input wire f_to_d_valid,
    input wire e_allow_in,
    output wire d_to_e_valid,

	// control hazards judge
	input can_jump,
	
	// write_back stage for data harzards and write registers
	input wire w_valid,
	input wire [6:0] W_opcode,
	input wire [4:0] W_rd,
	input wire [31:0] W_valE,
	input wire [31:0] W_valM,
	input wire [31:0] W_default_pc,

	// memory_access stage for data harzards
	input wire m_valid,
	input wire [6:0] M_opcode,
	input wire [4:0] M_rd,
	input wire [31:0] M_valE,
	input wire [31:0] m_valM,
	input wire [31:0] M_default_pc,
	
	// execute stage for data harzards
	input wire e_valid,
	input wire [6:0] E_opcode,
	input wire [4:0] E_rd,
	input wire [31:0] e_valE,
	input wire [31:0] E_default_pc,

	// decode signal
    output wire [31:0] d_val1,
    output wire [31:0] d_val2,

	// fetch and decode register
    input wire [31:0] F_pc,
    input wire [6:0] f_opcode,
    input wire [4:0] f_rd,
    input wire [9:0] f_funct,
    input wire [4:0] f_rs1,
    input wire [4:0] f_rs2,
    input wire [31:0] f_imm,
    input wire [2:0] f_instr_type,
    input wire [31:0] f_default_pc,

    output reg [31:0] D_pc,
    output reg [6:0] D_opcode,
    output reg [4:0] D_rd,
    output reg [9:0] D_funct,
    output reg [4:0] D_rs1,
    output reg [4:0] D_rs2,
    output reg [31:0] D_imm,
    output reg [2:0] D_instr_type,
    output reg [31:0] D_default_pc,

	// signal for cpu interface
	input wire [31:0] f_instr,

	output reg [31:0] D_cur_pc,
    output reg [31:0] D_instr,
    output reg D_commit,
    output reg [31:0] D_pred_pc
);
	// decode function
    wire [31:0] rval1, rval2;
    wire valid_src1 = (
		(D_instr_type == `TYPER) |  
		(D_instr_type == `TYPEI) |  
		(D_instr_type == `TYPES) |  
		(D_instr_type == `TYPEB)    
	);

	wire valid_src2 = (
		(D_instr_type == `TYPER) |  
		(D_instr_type == `TYPES) |  
		(D_instr_type == `TYPEB)    
	);

    wire w_en = (W_opcode == `OP_LOAD) | (W_opcode == `OP_JAL)
		| (W_opcode == `OP_JALR) | (W_opcode == `OP_R)
		| (W_opcode == `OP_IMM) | (W_opcode == `OP_LUI)
		| (W_opcode == `OP_AUIPC);
	
	wire [31:0] wdata;
	assign wdata = (W_opcode == `OP_LOAD) ? W_valM
		: (W_opcode == `OP_JAL || W_opcode == `OP_JALR) ? W_default_pc
		: W_valE;

    access_register_file reg_file(
		.clk(clk),
		.rst(rst),
        .rs1(D_rs1),
        .rs2(D_rs2),
        .valid_src1(valid_src1),
        .valid_src2(valid_src2),
		
		.w_en(w_en),
		.rd(W_rd),
		.wdata(wdata),

        .val1(rval1),
        .val2(rval2)
    );

	sel_fwd sf1 (
		.e_valid(e_valid),
		.E_opcode(E_opcode),
		.E_rd(E_rd),
		.e_valE(e_valE),
		.E_default_pc(E_default_pc),
		
		.m_valid(m_valid),
		.M_opcode(M_opcode),
		.M_rd(M_rd),
		.M_valE(M_valE),
		.m_valM(m_valM),
		.M_default_pc(M_default_pc),

		.w_valid(w_valid),
		.W_opcode(W_opcode),
		.W_rd(W_rd),
		.W_valE(W_valE),
		.W_valM(W_valM),
		.W_default_pc(W_default_pc),
		
		.rs(D_rs1),
		.rval(rval1),

		.fwd_val(d_val1)
	);

	sel_fwd sf2(
		.e_valid(e_valid),
		.E_opcode(E_opcode),
		.E_rd(E_rd),
		.e_valE(e_valE),
		.E_default_pc(E_default_pc),
		
		.m_valid(m_valid),
		.M_opcode(M_opcode),
		.M_rd(M_rd),
		.M_valE(M_valE),
		.m_valM(m_valM),
		.M_default_pc(M_default_pc),

		.w_valid(w_valid),
		.W_opcode(W_opcode),
		.W_rd(W_rd),
		.W_valE(W_valE),
		.W_valM(W_valM),
		.W_default_pc(W_default_pc),
		
		.rs(D_rs2),
		.rval(rval2),

		.fwd_val(d_val2)
	);

	// pipeline control
    reg d_valid;
    wire d_ready_go = ~((E_rd == D_rs1 || E_rd == D_rs2) && (E_opcode == `OP_LOAD) && e_valid);
    assign d_allow_in = ~d_valid || (d_ready_go && e_allow_in);

    always@ (posedge clk) begin
        if(rst || can_jump) d_valid <= 1'd0;
        else if(d_allow_in) d_valid <= f_to_d_valid;
    end

    assign d_to_e_valid = d_valid && d_ready_go;

	// fetch to decode register update
    always@ (posedge clk) begin
        if(d_allow_in && f_to_d_valid) begin
            D_pc <= F_pc;
			D_opcode <= f_opcode;
			D_rd <= f_rd;
			D_funct <= f_funct;
			D_rs1 <= f_rs1;
			D_rs2 <= f_rs2;
			D_imm <= f_imm;
			D_instr_type <= f_instr_type;
			D_default_pc <= f_default_pc;
        end
    end

	// cpu interface update
	always@ (posedge clk) begin
        if(d_allow_in && f_to_d_valid) begin
            D_cur_pc <= F_pc;
    		D_instr <= f_instr;
   			D_commit <= (F_pc >= 32'h80000000 && F_pc <= 32'h87ffffff) ? 1'b1 : 1'b0;
    		D_pred_pc <= f_default_pc;
        end
    end
	
endmodule