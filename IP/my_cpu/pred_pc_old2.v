// pred_pc_old2.v
// 保存旧版PC预测方法2：gshare + local(chooser) + AI(ai_pred)混合 + BTB + RAS
module pred_pc_old2 #(
    parameter integer N = 12,
    parameter integer RAS_DEPTH = 16,
    parameter integer RAS_W = 4,
    parameter integer PATH_LEN = 4
)(
    input  wire clk,
    input  wire rst,

    input  wire        f_allow_in,
    input  wire [31:0] F_pc,
    input  wire [31:0] f_default_pc,
    input  wire [6:0] f_opcode,
    input  wire [4:0] f_rd,
    input  wire [4:0] f_rs1,
    input  wire [2:0] f_instr_type,
    input  wire [2:0] f_func3,
    input  wire [31:0] f_imm,

    output wire        f_spec_is_jump_instr,
    output wire        f_spec_pred_taken,
    output wire [N - 1:0] f_spec_ghr_snapshot,
    output wire [31:0] f_spec_pred_pc,
    output wire [RAS_W - 1:0] f_spec_ras_sp_next,
    output wire [RAS_DEPTH * 32 - 1:0] f_spec_ras_snapshot,
    output wire [N - 1:0] f_spec_lht_snapshot,
    output wire        f_spec_gshare_taken,
    output wire        f_spec_local_taken,

    input  wire        e_stage_valid,
    input  wire        e_stage_is_jump_instr,
    input  wire        e_actual_taken,
    input  wire        e_pred_correct,
    input  wire [N - 1:0] e_train_ghr_snapshot,
    input  wire [31:0] e_redirect_pc,
    input  wire [31:0] e_pc,
    input  wire        e_is_cond_br,
    input  wire        e_is_jalr,
    input  wire [RAS_W - 1:0] e_train_ras_sp,
    input  wire [RAS_DEPTH * 32 - 1:0] e_train_ras_snapshot,
    input  wire [N - 1:0] e_train_lht_snapshot,
    input  wire e_train_gshare_taken,
    input  wire e_train_local_taken,
    input  wire [2:0] e_func3,
    input  wire [31:0] e_imm
);
    // pc_pred新增了path快照端口；old2封装不对外暴露，内部补齐连线以通过verilator编译
    wire [(PATH_LEN - 1) * 32 - 1:0] _unused_f_path_snapshot;
    wire [(PATH_LEN - 1) * 32 - 1:0] _zero_e_path_snapshot = {((PATH_LEN - 1) * 32){1'b0}};
    wire [31:0] _unused_f_hybrid_feature_snapshot;
    wire [31:0] _zero_e_hybrid_feature_snapshot = 32'd0;

    pc_pred #(
        .N(N),
        .RAS_DEPTH(RAS_DEPTH),
        .RAS_W(RAS_W),
        .PRED_MODE(1),
        .PATH_LEN(PATH_LEN)
    ) u_pc_pred_old2 (
        .clk(clk),
        .rst(rst),
        .f_allow_in(f_allow_in),
        .F_pc(F_pc),
        .f_default_pc(f_default_pc),
        .f_opcode(f_opcode),
        .f_rd(f_rd),
        .f_rs1(f_rs1),
        .f_instr_type(f_instr_type),
        .f_func3(f_func3),
        .f_imm(f_imm),
        .f_spec_is_jump_instr(f_spec_is_jump_instr),
        .f_spec_pred_taken(f_spec_pred_taken),
        .f_spec_ghr_snapshot(f_spec_ghr_snapshot),
        .f_spec_pred_pc(f_spec_pred_pc),
        .f_spec_ras_sp_next(f_spec_ras_sp_next),
        .f_spec_ras_snapshot(f_spec_ras_snapshot),
        .f_spec_lht_snapshot(f_spec_lht_snapshot),
        .f_spec_gshare_taken(f_spec_gshare_taken),
        .f_spec_local_taken(f_spec_local_taken),
        .f_spec_path_snapshot(_unused_f_path_snapshot),
        .f_spec_hybrid_feature_snapshot(_unused_f_hybrid_feature_snapshot),
        .e_stage_valid(e_stage_valid),
        .e_stage_is_jump_instr(e_stage_is_jump_instr),
        .e_actual_taken(e_actual_taken),
        .e_pred_correct(e_pred_correct),
        .e_train_ghr_snapshot(e_train_ghr_snapshot),
        .e_redirect_pc(e_redirect_pc),
        .e_pc(e_pc),
        .e_is_cond_br(e_is_cond_br),
        .e_is_jalr(e_is_jalr),
        .e_train_ras_sp(e_train_ras_sp),
        .e_train_ras_snapshot(e_train_ras_snapshot),
        .e_train_lht_snapshot(e_train_lht_snapshot),
        .e_train_gshare_taken(e_train_gshare_taken),
        .e_train_local_taken(e_train_local_taken),
        .e_func3(e_func3),
        .e_imm(e_imm),
        .e_train_path_snapshot(_zero_e_path_snapshot),
        .e_train_hybrid_feature_snapshot(_zero_e_hybrid_feature_snapshot)
    );
endmodule


