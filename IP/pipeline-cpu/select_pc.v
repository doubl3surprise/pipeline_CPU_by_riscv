module select_pc(
    input  wire [31:0] fetch_i_pre_pc,
    input  wire [31:0] execute_i_valE,
    input  wire        execute_i_is_jalr,
    input  wire        execute_i_need_jump,
    output wire [31:0] select_pc_o_pc
);

assign select_pc_o_pc =   execute_i_is_jalr ?  (execute_i_valE & ~1) : 
                       (execute_i_need_jump) ? execute_i_valE : fetch_i_pre_pc;
endmodule