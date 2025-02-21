`include "define.v"
module sel_pc(
    input clk_i,
    input rst_i,
	input F_stall_i,
	input F_bubble_i,

	input wire [31:0] F_pc_i,
    input wire [6:0] E_opcode_i,
    input wire e_Cnd_i,
    input wire [31:0] e_valE_i,
	input wire [31:0] f_default_pc_i,

    output reg [31:0] F_pc_o
);
    always@ (posedge clk_i) begin
		if(rst_i || F_bubble_i) begin
			F_pc_o <= 32'h80000000;
		end
		else if (F_stall_i) begin
			F_pc_o <= F_pc_i;
		end
        else if (E_opcode_i == `OP_JAL) begin
            F_pc_o <= e_valE_i & ~1;
        end
		else if (e_Cnd_i) begin
			F_pc_o <= e_valE_i;
		end
		else begin
			F_pc_o <= f_default_pc_i;
		end
	end
endmodule