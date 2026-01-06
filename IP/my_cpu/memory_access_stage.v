`include "define.v"
module memory_access_stage(
    input wire clk,
    input wire rst,

    // touch signal
    output wire m_allow_in,
    input wire e_to_m_valid,
    input wire w_allow_in,
    output wire m_to_w_valid,

    // stage valid
    output reg m_valid,

    // memory access signal
    output wire [31:0] m_valM,

    // execute to memory_access register
    input wire [6:0] E_opcode,
	input wire [9:0] E_funct,
	input wire [31:0] e_valE,
	input wire [31:0] E_val2,
	input wire [4:0] E_rd,
	input wire [31:0] E_default_pc,

    // signal for memory access to write_back
    output reg [6:0] M_opcode,
	output reg [9:0] M_funct,
	output reg [31:0] M_valE,
	output reg [31:0] M_val2,
	output reg [4:0] M_rd,
	output reg [31:0] M_default_pc,
	
    // branch signal
	input can_jump,
	input [31:0] jump_target,

    // signal for cpu interface
    input wire [31:0] E_cur_pc,
    input wire [31:0] E_instr,
    input wire E_commit,
    input wire [31:0] E_pred_pc,

    output reg [31:0] M_cur_pc,
    output reg [31:0] M_instr,
    output reg M_commit,
    output reg [31:0] M_pred_pc,
    output reg [31:0] M_predicted_pc
);

    // memory access function
    wire is_load = (M_opcode == `OP_LOAD);
	wire is_s = (M_opcode == `OP_S);
    wire mem_access = is_load || is_s;
    wire [31:0] mem_addr = mem_access ? M_valE : 32'd0;
	wire [31:0] wdata = is_s ? M_val2 : 32'd0;

    ram u_ram(
        .clk(clk),
        .rst(rst),
        .r_en(is_load),
        .w_en(is_s),
        .funct(M_funct),
        .addr(mem_addr),
        .wdata(wdata),
        .rdata(m_valM)
    );

    // pipeline control
    // m_ready_go: ready when no memory access, or D-Cache responds
    wire m_ready_go = 1;
    assign m_allow_in = ~m_valid || (m_ready_go && w_allow_in);
    always@ (posedge clk) begin
        if (rst) m_valid <= 1'b0;
        else if (m_allow_in) m_valid <= e_to_m_valid;
    end
    assign m_to_w_valid = m_valid && m_ready_go;
    
    // execute to memory_access update
    always@ (posedge clk) begin
        if (m_allow_in && e_to_m_valid) begin
            M_opcode <= E_opcode;
            M_funct <= E_funct;
            M_valE <= e_valE;
            M_val2 <= E_val2;
            M_rd <= E_rd;
            M_default_pc <= E_default_pc;
        end
    end

    // signal for cpu interface
    always@ (posedge clk) begin
        if (m_allow_in && e_to_m_valid) begin
            M_cur_pc <= E_cur_pc;
            M_instr <= E_instr;
			M_commit <= E_commit;
			// M_pred_pc: actual next pc (for difftest)
			M_pred_pc <= can_jump ? jump_target : E_default_pc;
            // M_predicted_pc: predicted next pc (for prediction statistics)
            M_predicted_pc <= E_pred_pc;
        end
    end
endmodule
