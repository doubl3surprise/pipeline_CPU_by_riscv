module access_register_file(
	input wire clk_i,
	input wire rst_i,
    input wire [4:0] rs1_i,
    input wire [4:0] rs2_i,
    input wire valid_src1_i,
    input wire valid_src2_i,

	input wire w_en_i,
	input wire [4:0] rd_i,
	input wire [31:0] wdata_i,

    output wire [31:0] val1_o,
    output wire [31:0] val2_o
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

    assign val1_o = (valid_src1_i && rs1_i != 5'd0) ? reg_file[rs1_i] : 32'd0;
    assign val2_o = (valid_src2_i && rs2_i != 5'd0) ? reg_file[rs2_i] : 32'd0;
	
	always@ (posedge clk_i) begin
		if(w_en_i && rd_i != 5'd0) begin
			reg_file[rd_i] <= wdata_i;
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