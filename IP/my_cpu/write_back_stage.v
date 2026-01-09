`include "define.v"
module write_back_stage(
    input wire clk,
    input wire rst,

    output w_allow_in,
    input m_to_w_valid,

    output reg w_valid,

    input wire [6:0] M_opcode,
	input wire [4:0] M_rd,
	input wire [31:0] M_valE,
	input wire [31:0] m_valM,
	input wire [31:0] M_default_pc,

	output reg [6:0] W_opcode,
	output reg [4:0] W_rd,
	output reg [31:0] W_valE,
	output reg [31:0] W_valM,
	output reg [31:0] W_default_pc,

	input wire [31:0] M_cur_pc,
    input wire [31:0] M_instr,
    input wire M_commit,
    input wire [31:0] M_pred_pc,
    input wire [31:0] M_predicted_pc,

    output reg [31:0] W_cur_pc,
    output reg [31:0] W_instr,
    output reg W_commit,
    output reg [31:0] W_pred_pc,
    output reg [31:0] W_predicted_pc
);
	// DPI import
	import "DPI-C" function void dpi_ebreak	(input int pc);
	always@ (*) begin
        if (W_instr == 32'h00100073) begin
            dpi_ebreak(0);
        end
    end

	// write_back function
	wire w_ready_go;
	assign w_ready_go = 1;
	assign w_allow_in = ~w_valid || w_ready_go;
	always@ (posedge clk) begin
		if (rst) begin
			w_valid <= 1'b0;
		end
		else if (w_allow_in) begin
			w_valid <= m_to_w_valid;
		end
	end
	
	// memory_access to write_back register 
	always@ (posedge clk) begin
		if (w_allow_in && m_to_w_valid) begin
			W_opcode <= M_opcode;
			W_rd <= M_rd;
			W_valE <= M_valE;
			W_valM <= m_valM;
			W_default_pc <= M_default_pc;
		end
	end

	// signal for cpu interface
	always@ (posedge clk) begin
		if (w_allow_in && m_to_w_valid) begin
			W_cur_pc <= M_cur_pc;
            W_instr <= M_instr;
			W_commit <= M_commit;
			W_pred_pc <= M_pred_pc;
            W_predicted_pc <= M_predicted_pc;
		end
		else begin
			W_cur_pc <= 32'd0;
            W_instr <= 32'd0;
			W_commit <= 1'd0;
			W_pred_pc <= 32'd0;
            W_predicted_pc <= 32'd0;
		end
	end
endmodule
