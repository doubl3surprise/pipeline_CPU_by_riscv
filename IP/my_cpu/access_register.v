module access_register_file(
	input wire clk,
	input wire rst,
    input wire [4:0] rs1,
    input wire [4:0] rs2,
    input wire valid_src1,
    input wire valid_src2,

	input wire w_en,
	input wire [4:0] rd,
	input wire [31:0] wdata,

    output wire [31:0] val1,
    output wire [31:0] val2
);
    reg [31:0] reg_file [31:0];
	
    import "DPI-C" function void dpi_read_regfile(input logic [31:0] a[]);
	initial begin
		dpi_read_regfile(reg_file);
	end

	initial begin
		integer i;
		for(i = 0; i < 32; i = i + 1) begin
			reg_file[i] = 32'h80000008 + i * 4;
		end
		reg_file[0] = 32'd0;
	end

    assign val1 = (valid_src1 && rs1 != 5'd0) ? reg_file[rs1] : 32'd0;
    assign val2 = (valid_src2 && rs2 != 5'd0) ? reg_file[rs2] : 32'd0;
	
	always@ (posedge clk) begin
		if(w_en && rd != 5'd0) begin
			reg_file[rd] <= wdata;
		end
	end

	/*
	always@ (posedge clk_i) begin
		if(rst_i) begin
			reg_file[0] = 32'h0;
		end
	end
	*/
	
endmodule
