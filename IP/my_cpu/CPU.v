`include "define.v"
module CPU #(
    parameter N = 12,
    parameter integer RAS_W = 4,
    parameter integer RAS_DEPTH = 16
) (
    // external information
    input wire clk,
    input wire rst,

    // cpu interface
    output wire [31:0] cur_pc,
    output wire [31:0] instr,
    output wire commit,
    output wire [31:0] commit_pc,
    output wire [31:0] commit_pre_pc,
    output wire [31:0] commit_pred_pc
);
    // touch signal
    wire f_allow_in;
    wire d_allow_in;
    wire f_to_d_valid;
    wire e_allow_in;
    wire d_to_e_valid;
    wire m_allow_in;
    wire e_to_m_valid;
    wire w_allow_in;
    wire m_to_w_valid;

    // stage valid
    wire e_valid;
    wire m_valid;
    wire w_valid;

    //branch signal
    wire can_jump;
    wire [31:0] jump_target;
    wire fact_success;
    wire [31:0] f_pred_pc;

    // final pc
    wire [31:0] nw_pc;
    
    // fetch signal
    wire [31:0] F_pc;
    wire [6:0] f_opcode;
    wire [4:0] f_rd;
    wire [4:0] f_rs1;
    wire [4:0] f_rs2;
    wire [9:0] f_funct;
    wire [31:0] f_imm;
    wire [2:0] f_instr_type;
    wire [31:0] f_default_pc;
    wire f_is_jump_instr;
    wire f_pred_taken;
    wire [N - 1:0] f_pred_history;
    wire [RAS_W - 1:0] f_ras_sp;
    wire [RAS_DEPTH * 32 - 1:0] f_ras_snapshot;
    wire [N - 1:0] f_lht_hist;
    wire f_gpred_taken;
    wire f_lpred_taken;

    // decode signal
    wire [31:0] D_pc;
    wire [6:0] D_opcode;
    wire [4:0] D_rd;
    wire [9:0] D_funct;
    wire [4:0] D_rs1;
    wire [4:0] D_rs2;
    wire [31:0] D_imm;
    wire [2:0] D_instr_type;
    wire [31:0] D_default_pc;
    wire [31:0] d_val1;
    wire [31:0] d_val2;
    wire D_is_jump_instr;
	wire D_pred_taken;
	wire [N - 1:0] D_pred_history;
    wire [RAS_W - 1:0] D_ras_sp;
    wire [RAS_DEPTH * 32 - 1:0] D_ras_snapshot;
    wire [N - 1:0] D_lht_hist;
    wire D_gpred_taken;
    wire D_lpred_taken;

    // execute signal
    wire [31:0] E_pc;
    wire [31:0] e_valE;
	wire [2:0] E_instr_type;
    wire [6:0] E_opcode;
	wire [9:0] E_funct;
    // predictor training helper
    wire fact_is_cond_br = (E_instr_type == `TYPEB);
    wire fact_is_jalr = (E_opcode == `OP_JALR);
	wire [31:0] E_val1;
	wire [31:0] E_val2;
	wire [31:0] E_imm;
	wire [4:0] E_rd;
	wire [31:0] E_default_pc;
	wire E_is_jump_instr;
	wire E_pred_taken;
	wire [N - 1:0] E_pred_history;
    wire [RAS_W - 1:0] E_ras_sp;
    wire [RAS_DEPTH * 32 - 1:0] E_ras_snapshot;
    wire [N - 1:0] E_lht_hist;
    wire E_gpred_taken;
    wire E_lpred_taken;
    wire [2:0] e_func3;
    wire [31:0] e_imm;

    // memory_access signal
    wire [31:0] m_valM;
    wire [6:0] M_opcode;
	wire [9:0] M_funct;
	wire [31:0] M_valE;
	wire [31:0] M_val2;
	wire [4:0] M_rd;
	wire [31:0] M_default_pc;

    // write_back signal
	wire [6:0] W_opcode;
	wire [4:0] W_rd;
	wire [31:0] W_valE;
	wire [31:0] W_valM;
	wire [31:0] W_default_pc;

    // fetch signal for cpu interface 
    wire [31:0] f_instr;

    // decode signal for cpu interface
    wire [31:0] D_cur_pc;
    wire [31:0] D_instr;
    wire D_commit;
    wire [31:0] D_pred_pc;

    // execute signal for cpu interface
    wire [31:0] E_cur_pc;
    wire [31:0] E_instr;
    wire E_commit;
    wire [31:0] E_pred_pc;

    // memory_access signal for cpu interface
    wire [31:0] M_cur_pc;
    wire [31:0] M_instr;
    wire M_commit;
    wire [31:0] M_pred_pc;
    wire [31:0] M_predicted_pc;

    // write_back signal for cpu interface
    wire [31:0] W_cur_pc;
    wire [31:0] W_instr;
    wire W_commit;
    wire [31:0] W_pred_pc;
    wire [31:0] W_predicted_pc;

    fetch_stage #(
        .N(N),
        .RAS_DEPTH(RAS_DEPTH),
        .RAS_W(RAS_W)
    ) fetch(
        .clk(clk),
        .rst(rst),
        
        .f_allow_in(f_allow_in),
        .d_allow_in(d_allow_in),
        .f_to_d_valid(f_to_d_valid),

        .F_pc(F_pc),

        .f_opcode(f_opcode),
        .f_rd(f_rd),
        .f_rs1(f_rs1),
        .f_rs2(f_rs2),
        .f_funct(f_funct),
        .f_imm(f_imm),
        .f_instr_type(f_instr_type),
        .f_default_pc(f_default_pc),

        .f_spec_is_jump_instr(f_is_jump_instr),
        .f_spec_pred_taken(f_pred_taken),
        .f_spec_ghr_snapshot(f_pred_history),
        .f_spec_pred_pc(f_pred_pc),
        .f_spec_ras_sp_next(f_ras_sp),
        .f_spec_ras_snapshot(f_ras_snapshot),
        .f_spec_lht_snapshot(f_lht_hist),
        .f_spec_gshare_taken(f_gpred_taken),
        .f_spec_local_taken(f_lpred_taken),

        .e_stage_valid(e_valid),
        .e_stage_is_jump_instr(E_is_jump_instr),
        .e_actual_taken(can_jump),
        .e_pred_correct(fact_success),
        .e_train_ghr_snapshot(E_pred_history),
        .e_redirect_pc(jump_target),
        .e_pc(E_pc),
        .e_is_cond_br(fact_is_cond_br),
        .e_is_jalr(fact_is_jalr),
        .e_train_ras_sp(E_ras_sp),
        .e_train_ras_snapshot(E_ras_snapshot),
        .e_train_lht_snapshot(E_lht_hist),
        .e_train_gshare_taken(E_gpred_taken),
        .e_train_local_taken(E_lpred_taken),

        .e_func3(e_func3),
        .e_imm(e_imm),

        .nw_pc(nw_pc),

        .f_instr(f_instr)
    );

    decode_stage #(
        .N(N),
        .RAS_W(RAS_W),
        .RAS_DEPTH(RAS_DEPTH)
    ) decode(
        .clk(clk),
        .rst(rst),

        .d_allow_in(d_allow_in),
        .f_to_d_valid(f_to_d_valid),
        .e_allow_in(e_allow_in),
        .d_to_e_valid(d_to_e_valid),

        .fact_success(fact_success),
        .e_is_jump_instr(E_is_jump_instr),
        
        .w_valid(w_valid),
        .W_opcode(W_opcode),
        .W_rd(W_rd),
        .W_valE(W_valE),
        .W_valM(W_valM),
        .W_default_pc(W_default_pc),

        .m_valid(m_valid),
        .M_opcode(M_opcode),
        .M_rd(M_rd),
        .M_valE(M_valE),
        .m_valM(m_valM),
        .M_default_pc(M_default_pc),
        
        .e_valid(e_valid),
        .E_opcode(E_opcode),
        .E_rd(E_rd),
        .e_valE(e_valE),
        .E_default_pc(E_default_pc),

        .d_val1(d_val1),
        .d_val2(d_val2),

        .F_pc(F_pc),
        .f_opcode(f_opcode),
        .f_rd(f_rd),
        .f_funct(f_funct),
        .f_rs1(f_rs1),
        .f_rs2(f_rs2),
        .f_imm(f_imm),
        .f_instr_type(f_instr_type),
        .f_default_pc(f_default_pc),
	    .f_is_jump_instr(f_is_jump_instr),

        .f_pred_taken(f_pred_taken),
        .f_pred_history(f_pred_history),
        .f_pred_pc(f_pred_pc),
        .f_ras_sp(f_ras_sp),
        .f_ras_snapshot(f_ras_snapshot),
        .f_lht_hist(f_lht_hist),
        .f_gpred_taken(f_gpred_taken),
        .f_lpred_taken(f_lpred_taken),

        .D_pc(D_pc),
        .D_opcode(D_opcode),
        .D_rd(D_rd),
        .D_funct(D_funct),
        .D_rs1(D_rs1),
        .D_rs2(D_rs2),
        .D_imm(D_imm),
        .D_instr_type(D_instr_type),
        .D_default_pc(D_default_pc),
        .D_is_jump_instr(D_is_jump_instr),
	    .D_pred_taken(D_pred_taken),
	    .D_pred_history(D_pred_history),
        .D_ras_sp(D_ras_sp),
        .D_ras_snapshot(D_ras_snapshot),
        .D_lht_hist(D_lht_hist),
        .D_gpred_taken(D_gpred_taken),
        .D_lpred_taken(D_lpred_taken),

        .f_instr(f_instr),

	    .D_cur_pc(D_cur_pc),
        .D_instr(D_instr),
        .D_commit(D_commit),
        .D_pred_pc(D_pred_pc)
    );

    execute_stage #(
        .N(N),
        .RAS_W(RAS_W),
        .RAS_DEPTH(RAS_DEPTH)
    ) execute(
        .clk(clk),
        .rst(rst),

        .e_allow_in(e_allow_in),
        .d_to_e_valid(d_to_e_valid),
        .m_allow_in(m_allow_in),
        .e_to_m_valid(e_to_m_valid),

        .e_valid(e_valid),
        
        .e_valE(e_valE),

        .can_jump(can_jump),
        .jump_target(jump_target),
        .fact_success(fact_success),

        .D_pc(D_pc),
        .D_instr_type(D_instr_type),
        .D_opcode(D_opcode),
        .D_funct(D_funct),
        .d_val1(d_val1),
        .d_val2(d_val2),
        .D_imm(D_imm),
        .D_rd(D_rd),
        .D_default_pc(D_default_pc),
        .D_is_jump_instr(D_is_jump_instr),
	    .D_pred_taken(D_pred_taken),
	    .D_pred_history(D_pred_history),
        .D_ras_sp(D_ras_sp),
        .D_ras_snapshot(D_ras_snapshot),
        .D_lht_hist(D_lht_hist),
        .D_gpred_taken(D_gpred_taken),
        .D_lpred_taken(D_lpred_taken),
        
        .E_pc(E_pc),
        .E_instr_type(E_instr_type),
        .E_opcode(E_opcode),
        .E_funct(E_funct),
        .E_val1(E_val1),
        .E_val2(E_val2),
        .E_imm(E_imm),
        .E_rd(E_rd),
        .E_default_pc(E_default_pc),
        .E_is_jump_instr(E_is_jump_instr),
	    .E_pred_taken(E_pred_taken),
	    .E_pred_history(E_pred_history),
        .E_ras_sp(E_ras_sp),
        .E_ras_snapshot(E_ras_snapshot),
        .E_lht_hist(E_lht_hist),
        .E_gpred_taken(E_gpred_taken),
        .E_lpred_taken(E_lpred_taken),

        .e_func3_out(e_func3),

        .D_cur_pc(D_cur_pc),
        .D_instr(D_instr),
        .D_commit(D_commit),
        .D_pred_pc(D_pred_pc),

        .E_cur_pc(E_cur_pc),
        .E_instr(E_instr),
        .E_commit(E_commit),
        .E_pred_pc(E_pred_pc)
    );

    memory_access_stage memory_access(
        .clk(clk),
        .rst(rst),

        .m_allow_in(m_allow_in),
        .e_to_m_valid(e_to_m_valid),
        .w_allow_in(w_allow_in),
        .m_to_w_valid(m_to_w_valid),

        .m_valid(m_valid),

        .m_valM(m_valM),

        .E_opcode(E_opcode),
        .E_funct(E_funct),
        .e_valE(e_valE),
        .E_val2(E_val2),
        .E_rd(E_rd),
        .E_default_pc(E_default_pc),
        
        .M_opcode(M_opcode),
        .M_funct(M_funct),
        .M_valE(M_valE),
        .M_val2(M_val2),
        .M_rd(M_rd),
        .M_default_pc(M_default_pc),

        .can_jump(can_jump),
        .jump_target(jump_target),

        .E_cur_pc(E_cur_pc),
        .E_instr(E_instr),
        .E_commit(E_commit),
        .E_pred_pc(E_pred_pc),

        .M_cur_pc(M_cur_pc),
        .M_instr(M_instr),
        .M_commit(M_commit),
        .M_pred_pc(M_pred_pc),
        .M_predicted_pc(M_predicted_pc)
    );

    write_back_stage write_back(
       . clk(clk),
        .rst(rst),

        .w_allow_in(w_allow_in),
        .m_to_w_valid(m_to_w_valid),

        .w_valid(w_valid),

        .M_opcode(M_opcode),
        .M_rd(M_rd),
        .M_valE(M_valE),
        .m_valM(m_valM),
        .M_default_pc(M_default_pc),

        .W_opcode(W_opcode),
        .W_rd(W_rd),
        .W_valE(W_valE),
        .W_valM(W_valM),
        .W_default_pc(W_default_pc),

        .M_cur_pc(M_cur_pc),
        .M_instr(M_instr),
        .M_commit(M_commit),
        .M_pred_pc(M_pred_pc),
        .M_predicted_pc(M_predicted_pc),

        .W_cur_pc(W_cur_pc),
        .W_instr(W_instr),
        .W_commit(W_commit),
        .W_pred_pc(W_pred_pc),
        .W_predicted_pc(W_predicted_pc)
    );

    assign F_pc = nw_pc;

    // write cpu interface
    assign cur_pc = F_pc;
	assign instr = W_instr;
	assign commit = W_commit;
	assign commit_pc = W_cur_pc;
	assign commit_pre_pc = W_pred_pc;
    assign commit_pred_pc = W_predicted_pc;
endmodule
