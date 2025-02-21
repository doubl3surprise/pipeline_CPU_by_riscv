`include "define.v"
module F_stage(
	input wire clk_i,
	input wire F_stall_i,
	input wire F_bubble_i,
	input wire [31:0] nw_pc_i,

	output reg [31:0] F_pc_o	
);
	always@ (posedge clk_i) begin
		if(F_bubble_i) begin
			F_pc_o <= nw_pc_i;
		end
		else if(~F_stall_i) begin
			F_pc_o <= nw_pc_i;
		end
	end
endmodule
