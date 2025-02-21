`include "define.v"
module write_back(
    input [31:0] W_instr_i
);
    import "DPI-C" function void dpi_ebreak		(input int pc);
    always@ (*) begin
        if(W_instr_i == 32'h00100073) begin
            dpi_ebreak(0);
        end
    end
endmodule