`include "define.v"
module test_ram;
    // 这里应该能识别宏定义
    parameter TEST_LW = `FUNC_LW;
    parameter TEST_LH = `FUNC_LH;
    
    initial begin
        $display("FUNC_LW = %d", `FUNC_LW);
    end
endmodule
