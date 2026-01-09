`include "define.v"
module fetch_stage # (
    parameter N = 12,
    parameter integer RAS_DEPTH = 16,
    parameter integer RAS_W = 4,
    parameter integer PATH_LEN = 4
) (
    input wire clk,
    input wire rst,
    
    // touch signal
    output f_allow_in,
    input d_allow_in,
    output f_to_d_valid,
    
    // pc signal
    input wire [31:0] F_pc,

    // fetch siganl
    output wire [6:0] f_opcode,
    output wire [4:0] f_rd,
    output wire [4:0] f_rs1,
    output wire [4:0] f_rs2,
    output wire [9:0] f_funct,
    output wire [31:0] f_imm,
    output wire [2:0] f_instr_type,
    output wire [31:0] f_default_pc,

    // PC prediction
    output wire f_spec_is_jump_instr,
    output wire f_spec_pred_taken,
    output wire [N - 1:0] f_spec_ghr_snapshot,
    output wire [31:0] f_spec_pred_pc,
    output wire [RAS_W - 1:0] f_spec_ras_sp_next,
    output wire [RAS_DEPTH * 32 - 1:0] f_spec_ras_snapshot,
    output wire [N - 1:0] f_spec_lht_snapshot,
    output wire f_spec_gshare_taken,
    output wire f_spec_local_taken,
    output wire [(PATH_LEN - 1) * 32 - 1:0] f_spec_path_snapshot,
    output wire [31:0] f_spec_hybrid_feature_snapshot,

    input wire e_stage_valid,
    input wire e_stage_is_jump_instr,

    input wire e_actual_taken,
    input wire e_pred_correct,
    input wire [N - 1:0] e_train_ghr_snapshot,
    input wire [31:0] e_redirect_pc,
    input wire [31:0] e_pc,
    input wire e_is_cond_br,
    input wire e_is_jalr,
    input wire [RAS_W - 1:0] e_train_ras_sp,
    input wire [RAS_DEPTH * 32 - 1:0] e_train_ras_snapshot,
    input wire [N - 1:0] e_train_lht_snapshot,
    input wire e_train_gshare_taken,
    input wire e_train_local_taken,
    input wire [(PATH_LEN - 1) * 32 - 1:0] e_train_path_snapshot,
    input wire [31:0] e_train_hybrid_feature_snapshot,

    input wire [2:0] e_func3,
    input wire [31:0] e_imm,

    // update pc value
    output reg [31:0] nw_pc,

    // signal for cpu interface
    output wire [31:0] f_instr
);
    // DPI import for I-Cache memory interface
    import "DPI-C" function int dpi_mem_read (input int addr, input int len);

    // get instr from cache or mem
    wire hit;
    wire [31:0] r_data;

    icache u_icache(
        .clk(clk),
        .rst(rst),
        .r_en(f_to_d_valid),
        .r_addr(F_pc),
        .hit(hit),
        .r_data(r_data),
        .fill_en(!hit && f_to_d_valid),
        .fill_addr(F_pc),
        .w_en(!hit && f_to_d_valid),
        .w_addr(F_pc),
        .w_data(f_instr)
    );

    assign f_instr = hit ? r_data : dpi_mem_read(F_pc, 4);

    // fetch function
    wire [2:0] func3;
    wire [6:0] func7;
    wire [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
    wire is_imm_i, is_imm_s, is_imm_b, is_imm_u, is_imm_j;
    wire is_funct_r, is_funct_i, is_funct_s, is_funct_b;
    assign func3 = f_instr[14:12];
    assign func7 = f_instr[31:25];
    assign f_opcode = f_instr[6:0];
    assign f_rd = f_instr[11:7];
    assign f_rs1 = f_instr[19:15];
    assign f_rs2 = f_instr[24:20];

    assign imm_i = {{20{f_instr[31]}}, f_instr[31:20]};
    assign imm_s = {{20{f_instr[31]}}, f_instr[31:25], f_instr[11:7]};
    assign imm_b = {{19{f_instr[31]}}, f_instr[31], f_instr[7], f_instr[30:25], f_instr[11:8], 1'b0};
    assign imm_u = {f_instr[31:12], 12'b0};
    assign imm_j = {{12{f_instr[31]}}, f_instr[19:12], f_instr[20], f_instr[30:21], 1'b0};

	assign f_instr_type = 
		(f_opcode == `OP_B)    ? `TYPEB :
		(f_opcode == `OP_S)    ? `TYPES :
		(f_opcode == `OP_JAL)  ? `TYPEJ :
		(f_opcode == `OP_JALR) ? `TYPEI :
		(f_opcode == `OP_R)    ? `TYPER :
		(f_opcode == `OP_IMM)  ? `TYPEI :
		(f_opcode == `OP_LOAD) ? `TYPEI :
		(f_opcode == `OP_SYSTEM) ? `TYPEI :
		((f_opcode == `OP_LUI) || (f_opcode == `OP_AUIPC)) ? `TYPEU :
		3'd0;

    assign is_funct_r = (f_instr_type == `TYPER);
    assign is_funct_i = (f_instr_type == `TYPEI);
    assign is_funct_s = (f_instr_type == `TYPES);
    assign is_funct_b = (f_instr_type == `TYPEB);

	assign f_funct = is_funct_r ? {func7, func3} :
        (is_funct_i || is_funct_s || is_funct_b) ?
            (f_opcode == `OP_IMM) && (func3 == 3'b001 || func3 == 3'b101) ? {func7, func3} :
            {7'b0, func3} :
            10'd0;

    assign is_imm_i = (f_instr_type == `TYPEI);
	assign is_imm_s = (f_instr_type == `TYPES);
	assign is_imm_b = (f_instr_type == `TYPEB);
	assign is_imm_u = (f_instr_type == `TYPEU);
	assign is_imm_j = (f_instr_type == `TYPEJ);
	assign f_imm = ({32{is_imm_i}} & imm_i) |
		({32{is_imm_s}} & imm_s) |
		({32{is_imm_b}} & imm_b) |
		({32{is_imm_u}} & imm_u) |
		({32{is_imm_j}} & imm_j);

    // pipeline control
    reg f_valid;
    wire f_ready_go = 1;
    always@ (posedge clk) begin
        if (rst) begin
            f_valid <= 1'b1;
        end
        else if (f_allow_in) begin
            f_valid <= 1'b1;
        end
    end
    assign f_to_d_valid = f_valid && f_ready_go;
    assign f_allow_in = ~f_valid || (f_ready_go && d_allow_in);

    assign f_default_pc = F_pc + 4;

    // PC prediction
    pc_pred #(
        .N(N),
        .RAS_DEPTH(RAS_DEPTH),
        .RAS_W(RAS_W),
        .PRED_MODE(2),
        .PATH_LEN(PATH_LEN)
    ) u_pc_pred (
        .clk(clk),
        .rst(rst),
        .f_allow_in(f_allow_in),
        .F_pc(F_pc),
        .f_default_pc(f_default_pc),
        .f_opcode(f_opcode),
        .f_rd(f_rd),
        .f_rs1(f_rs1),
        .f_instr_type(f_instr_type),
        .f_func3(func3),
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
        .f_spec_path_snapshot(f_spec_path_snapshot),
        .f_spec_hybrid_feature_snapshot(f_spec_hybrid_feature_snapshot),
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
        .e_train_path_snapshot(e_train_path_snapshot),
        .e_train_hybrid_feature_snapshot(e_train_hybrid_feature_snapshot)
    );

    // wire old1_is_jump, old1_taken;
    // wire [N - 1:0] old1_ghr, old1_lht;
    // wire [31:0] old1_pred_pc;
    // wire [RAS_W - 1:0] old1_ras_sp_next;
    // wire [RAS_DEPTH * 32 - 1:0] old1_ras_snap;
    // wire old1_g_taken, old1_l_taken;
    // pred_pc_old1 #(.N(N), .RAS_DEPTH(RAS_DEPTH), .RAS_W(RAS_W)) u_pred_pc_old1 (
    //     .clk(clk), .rst(rst),
    //     .f_allow_in(f_allow_in),
    //     .F_pc(F_pc),
    //     .f_default_pc(f_default_pc),
    //     .f_opcode(f_opcode),
    //     .f_rd(f_rd),
    //     .f_rs1(f_rs1),
    //     .f_instr_type(f_instr_type),
    //     .f_func3(func3),
    //     .f_imm(f_imm),
    //     .f_spec_is_jump_instr(old1_is_jump),
    //     .f_spec_pred_taken(old1_taken),
    //     .f_spec_ghr_snapshot(old1_ghr),
    //     .f_spec_pred_pc(old1_pred_pc),
    //     .f_spec_ras_sp_next(old1_ras_sp_next),
    //     .f_spec_ras_snapshot(old1_ras_snap),
    //     .f_spec_lht_snapshot(old1_lht),
    //     .f_spec_gshare_taken(old1_g_taken),
    //     .f_spec_local_taken(old1_l_taken),
    //     .e_stage_valid(e_stage_valid),
    //     .e_stage_is_jump_instr(e_stage_is_jump_instr),
    //     .e_actual_taken(e_actual_taken),
    //     .e_pred_correct(e_pred_correct),
    //     .e_train_ghr_snapshot(e_train_ghr_snapshot),
    //     .e_redirect_pc(e_redirect_pc),
    //     .e_pc(e_pc),
    //     .e_is_cond_br(e_is_cond_br),
    //     .e_is_jalr(e_is_jalr),
    //     .e_train_ras_sp(e_train_ras_sp),
    //     .e_train_ras_snapshot(e_train_ras_snapshot),
    //     .e_train_lht_snapshot(e_train_lht_snapshot),
    //     .e_train_gshare_taken(e_train_gshare_taken),
    //     .e_train_local_taken(e_train_local_taken),
    //     .e_func3(e_func3),
    //     .e_imm(e_imm)
    // );
    //
    // wire old2_is_jump, old2_taken;
    // wire [N - 1:0] old2_ghr, old2_lht;
    // wire [31:0] old2_pred_pc;
    // wire [RAS_W - 1:0] old2_ras_sp_next;
    // wire [RAS_DEPTH * 32 - 1:0] old2_ras_snap;
    // wire old2_g_taken, old2_l_taken;
    // pred_pc_old2 #(.N(N), .RAS_DEPTH(RAS_DEPTH), .RAS_W(RAS_W)) u_pred_pc_old2 (
    //     .clk(clk), .rst(rst),
    //     .f_allow_in(f_allow_in),
    //     .F_pc(F_pc),
    //     .f_default_pc(f_default_pc),
    //     .f_opcode(f_opcode),
    //     .f_rd(f_rd),
    //     .f_rs1(f_rs1),
    //     .f_instr_type(f_instr_type),
    //     .f_func3(func3),
    //     .f_imm(f_imm),
    //     .f_spec_is_jump_instr(old2_is_jump),
    //     .f_spec_pred_taken(old2_taken),
    //     .f_spec_ghr_snapshot(old2_ghr),
    //     .f_spec_pred_pc(old2_pred_pc),
    //     .f_spec_ras_sp_next(old2_ras_sp_next),
    //     .f_spec_ras_snapshot(old2_ras_snap),
    //     .f_spec_lht_snapshot(old2_lht),
    //     .f_spec_gshare_taken(old2_g_taken),
    //     .f_spec_local_taken(old2_l_taken),
    //     .e_stage_valid(e_stage_valid),
    //     .e_stage_is_jump_instr(e_stage_is_jump_instr),
    //     .e_actual_taken(e_actual_taken),
    //     .e_pred_correct(e_pred_correct),
    //     .e_train_ghr_snapshot(e_train_ghr_snapshot),
    //     .e_redirect_pc(e_redirect_pc),
    //     .e_pc(e_pc),
    //     .e_is_cond_br(e_is_cond_br),
    //     .e_is_jalr(e_is_jalr),
    //     .e_train_ras_sp(e_train_ras_sp),
    //     .e_train_ras_snapshot(e_train_ras_snapshot),
    //     .e_train_lht_snapshot(e_train_lht_snapshot),
    //     .e_train_gshare_taken(e_train_gshare_taken),
    //     .e_train_local_taken(e_train_local_taken),
    //     .e_func3(e_func3),
    //     .e_imm(e_imm)
    // );
    //
    // assign f_spec_is_jump_instr = old1_is_jump;
    // assign f_spec_pred_taken    = old1_taken;
    // assign f_spec_ghr_snapshot  = old1_ghr;
    // assign f_spec_pred_pc       = old1_pred_pc;
    // assign f_spec_ras_sp_next   = old1_ras_sp_next;
    // assign f_spec_ras_snapshot  = old1_ras_snap;
    // assign f_spec_lht_snapshot  = old1_lht;
    // assign f_spec_gshare_taken  = old1_g_taken;
    // assign f_spec_local_taken   = old1_l_taken;

    // update PC
    wire e_train_valid_jump = e_stage_is_jump_instr && e_stage_valid;
    wire e_train_redirect   = e_train_valid_jump && !e_pred_correct;
    always@ (posedge clk) begin
        if (rst) begin
            nw_pc <= 32'h80000000;
        end
        else if (e_train_redirect) begin
            nw_pc <= e_redirect_pc;
        end
        else if (f_allow_in) begin
            nw_pc <= f_spec_pred_pc;
        end
    end
endmodule
