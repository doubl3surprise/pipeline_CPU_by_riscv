`include "define.v"
module fetch_stage # (
    parameter N = 12,
    parameter integer RAS_DEPTH = 16,
    parameter integer RAS_W = 4
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

    input wire [2:0] e_func3,
    input wire [31:0] e_imm,

    // update pc value
    output reg [31:0] nw_pc,

    // signal for cpu interface
    output wire [31:0] f_instr
);
    // DPI import for I-Cache memory interface
    import "DPI-C" function int dpi_mem_read (input int addr, input int len);

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
        if(rst) f_valid <= 1'b1;
        else if(f_allow_in) f_valid <= 1'b1;
    end
    assign f_to_d_valid = f_valid && f_ready_go;
    assign f_allow_in = ~f_valid || (f_ready_go && d_allow_in);

    assign f_default_pc = F_pc + 4;

    // predict PC
    // gshare and lht is history record
    // pht and lpht is 2-bit counter for gshare and lht
    // chooser is 2-bit counter for pht and lpht
    // BTB is 32-bit target address and 32-bit tag for JALR
    // RAS is 32-bit stack for returns: ret = jalr x0, x1, 0

    // gshare and local predictor
    // reg [N - 1:0] ghr_state;
    // reg [1:0]     pht_state     [(1 << N) - 1:0];
    // reg [N - 1:0] lht_state     [(1 << N) - 1:0];
    // reg [1:0]     lpht_state    [(1 << N) - 1:0];
    // reg [1:0]     chooser_state [(1 << N) - 1:0];

    // // BTB (for JALR)
    // reg [31:0] btb_target_state [(1 << N) - 1:0];
    // reg [31:0] btb_tag_state    [(1 << N) - 1:0];

    // // RAS (for returns: ret = jalr x0, x1, 0)
    // reg [31:0] ras_state [RAS_DEPTH - 1:0];
    // reg [RAS_W - 1:0] ras_sp_state;

    // // Fetch-stage speculative instruction information
    // wire f_spec_is_cond_br = (f_instr_type == `TYPEB);
    // wire f_spec_is_jal     = (f_instr_type == `TYPEJ);
    // wire f_spec_is_jalr    = (f_opcode == `OP_JALR);
    // // Treat SYSTEM as control-like instruction, so redirect/flush path can be reused for ecall/mret
    // wire f_spec_is_system = (f_opcode == `OP_SYSTEM);
    // assign f_spec_is_jump_instr = f_spec_is_cond_br || f_spec_is_jal || f_spec_is_jalr || f_spec_is_system;

    // // Execute-stage training instruction information
    // wire e_train_valid_jump   = e_stage_is_jump_instr && e_stage_valid;
    // wire e_train_is_cond_br   = e_is_cond_br;
    // wire e_train_is_jalr      = e_is_jalr;
    // wire e_train_redirect     = e_train_valid_jump && !e_pred_correct; // mispredict/wrong-target redirect

    // // RAS: speculative call/ret detection
    // wire f_spec_is_call = (f_spec_is_jal || f_spec_is_jalr) && ((f_rd == 5'd1) || (f_rd == 5'd5));
    // wire f_spec_is_ret  = f_spec_is_jalr && (f_rd == 5'd0) && ((f_rs1 == 5'd1) || (f_rs1 == 5'd5)) && (f_imm == 32'd0);

    // // RAS create snapshot
    // reg [RAS_DEPTH * 32 - 1:0] f_spec_ras_snapshot_r;
    // integer ras_i;
    // always @* begin
    //     // default: snapshot current stack contents
    //     for (ras_i = 0; ras_i < RAS_DEPTH; ras_i = ras_i + 1) begin
    //         f_spec_ras_snapshot_r[ras_i * 32 +: 32] = ras_state[ras_i];
    //     end
    //     // CALL: snapshot should reflect the pushed return address at current sp
    //     if (f_spec_is_call && f_allow_in) begin
    //         f_spec_ras_snapshot_r[ras_sp_state * 32 +: 32] = f_default_pc;
    //     end
    // end
    // assign f_spec_ras_snapshot = f_spec_ras_snapshot_r;

    // // RAS top and next sp
    // wire f_spec_ras_empty = (ras_sp_state == {RAS_W{1'b0}});
    // wire [31:0] f_spec_ras_top = f_spec_ras_empty ? 32'd0 : ras_state[ras_sp_state - 1'b1];
    // assign f_spec_ras_sp_next = f_spec_is_call ? (ras_sp_state + 1'b1) :
    //     (f_spec_is_ret && !f_spec_ras_empty) ? (ras_sp_state - 1'b1) :
    //     ras_sp_state;

    // // Indix of speculate and train
    // wire [N - 1:0] f_spec_pc_idx  = F_pc[N + 1:2];
    // wire [N - 1:0] e_train_pc_idx = e_pc[N + 1:2];

    // // BTB hit or not
    // wire f_spec_btb_hit = (btb_tag_state[f_spec_pc_idx] == F_pc);

    // // gshare idx and local idx and choose gshare taken or local taken
    // wire [N - 1:0] f_spec_lht_snap = lht_state[f_spec_pc_idx];
    // wire [N - 1:0] f_spec_gidx = f_spec_pc_idx ^ ghr_state;
    // wire [N - 1:0] f_spec_lidx = f_spec_pc_idx ^ f_spec_lht_snap;
    // wire f_spec_g_taken = pht_state[f_spec_gidx][1];
    // wire f_spec_l_taken = lpht_state[f_spec_lidx][1];
    // wire f_spec_use_local = chooser_state[f_spec_pc_idx][1];

    // assign f_spec_lht_snapshot   = f_spec_lht_snap;
    // assign f_spec_gshare_taken   = f_spec_g_taken;
    // assign f_spec_local_taken    = f_spec_l_taken;

    // // Execute training / rollback updates 
    // always@ (posedge clk) begin
    //     if (rst) begin
    //         ghr_state <= 0;
    //         ras_sp_state <= 0;
    //         for(integer r = 0; r < RAS_DEPTH; r = r + 1) begin
    //             ras_state[r] <= 32'd0;
    //         end
    //         for(integer i = 0; i < (1 << N); i = i + 1) begin
    //             pht_state[i] = 2'b01;
    //             lpht_state[i] = 2'b01;
    //             chooser_state[i] = 2'b10;
    //             lht_state[i] = {N{1'b0}};
    //             btb_target_state[i] = 32'd0;
    //             btb_tag_state[i] = 32'd0;
    //         end
    //     end
    //     else begin
    //         // GShare update
    //         if (e_train_valid_jump && e_train_is_cond_br && !e_pred_correct) begin
    //             ghr_state <= {e_train_ghr_snapshot[N - 2:0], e_actual_taken};
    //         end
    //         else if (f_allow_in && f_spec_is_cond_br) begin
    //             ghr_state <= {ghr_state[N - 2:0], f_spec_pred_taken};
    //         end

    //         // Local history update
    //         if (e_train_valid_jump && e_train_is_cond_br && !e_pred_correct) begin
    //             lht_state[e_train_pc_idx] <= {e_train_lht_snapshot[N - 2:0], e_actual_taken};
    //         end
    //         else if (f_allow_in && f_spec_is_cond_br) begin
    //             lht_state[f_spec_pc_idx] <= {lht_state[f_spec_pc_idx][N - 2:0], f_spec_pred_taken};
    //         end

    //         // if B-instruction, update pht and lpht
    //         if (e_train_valid_jump && e_train_is_cond_br) begin
    //             // train pht
    //             if (e_actual_taken) begin
    //                 pht_state[e_train_ghr_snapshot ^ e_pc[N + 1:2]] <=
    //                     (pht_state[e_train_ghr_snapshot ^ e_pc[N + 1:2]] == 2'b11)
    //                     ? 2'b11 : pht_state[e_train_ghr_snapshot ^ e_pc[N + 1:2]] + 1'b1;
    //             end
    //             else begin
    //                 pht_state[e_train_ghr_snapshot ^ e_pc[N + 1:2]] <=
    //                     (pht_state[e_train_ghr_snapshot ^ e_pc[N + 1:2]] == 2'b00)
    //                     ? 2'b00 : pht_state[e_train_ghr_snapshot ^ e_pc[N + 1:2]] - 1'b1;
    //             end

    //             // train lpht
    //             if (e_actual_taken) begin
    //                 lpht_state[(e_pc[N + 1:2]) ^ e_train_lht_snapshot] <=
    //                     (lpht_state[(e_pc[N + 1:2]) ^ e_train_lht_snapshot] == 2'b11)
    //                     ? 2'b11 : lpht_state[(e_pc[N + 1:2]) ^ e_train_lht_snapshot] + 1'b1;
    //             end
    //             else begin
    //                 lpht_state[(e_pc[N + 1:2]) ^ e_train_lht_snapshot] <=
    //                     (lpht_state[(e_pc[N + 1:2]) ^ e_train_lht_snapshot] == 2'b00)
    //                     ? 2'b00 : lpht_state[(e_pc[N + 1:2]) ^ e_train_lht_snapshot] - 1'b1;
    //             end

    //             // train chooser
    //             if ((e_train_local_taken == e_actual_taken) && (e_train_gshare_taken != e_actual_taken)) begin
    //                 chooser_state[e_train_pc_idx] <= (chooser_state[e_train_pc_idx] == 2'b11) ? 2'b11 : chooser_state[e_train_pc_idx] + 1'b1;
    //             end
    //             else if ((e_train_gshare_taken == e_actual_taken) && (e_train_local_taken != e_actual_taken)) begin
    //                 chooser_state[e_train_pc_idx] <= (chooser_state[e_train_pc_idx] == 2'b00) ? 2'b00 : chooser_state[e_train_pc_idx] - 1'b1;
    //             end
    //         end

    //         // BTB update for JALR (including ret)
    //         if (e_train_valid_jump && e_train_is_jalr) begin
    //             btb_target_state[e_train_pc_idx] <= e_redirect_pc;
    //             btb_tag_state[e_train_pc_idx] <= e_pc;
    //         end

    //         // RAS update and rollback
    //         if (e_train_redirect) begin
    //             ras_sp_state <= e_train_ras_sp;
    //             for(integer r = 0; r < RAS_DEPTH; r = r + 1) begin
    //                 // recover each 32-bit entry from the packed snapshot
    //                 ras_state[r] <= e_train_ras_snapshot[r * 32 +: 32];
    //             end
    //         end
    //         else if (f_allow_in) begin
    //             if (f_spec_is_call) begin
    //                 ras_state[ras_sp_state] <= f_default_pc;
    //                 ras_sp_state <= ras_sp_state + 1'b1;
    //             end
    //             else if (f_spec_is_ret) begin
    //                 if (!f_spec_ras_empty) ras_sp_state <= ras_sp_state - 1'b1;
    //             end
    //         end
    //     end 
    // end

    // // conditional branch taken or not and jump instruction taken or not and gshare snapshot
    // wire f_spec_br_taken = f_spec_use_local ? f_spec_l_taken : f_spec_g_taken;
    // assign f_spec_pred_taken   = f_spec_is_cond_br ? f_spec_br_taken : (f_spec_is_jump_instr ? 1'b1 : 1'b0);
    // assign f_spec_ghr_snapshot = ghr_state;

    // // predicted next pc for this instruction
    // wire [31:0] f_spec_pred_target_pc;
    // assign f_spec_pred_pc = (f_spec_is_jump_instr && f_spec_pred_taken) ? f_spec_pred_target_pc : f_default_pc;

    // // Target prediction
    // assign f_spec_pred_target_pc =
    //     (f_spec_is_cond_br || f_spec_is_jal) ? ((F_pc + f_imm) & -1) :
    //     (f_spec_is_ret && !f_spec_ras_empty) ? f_spec_ras_top :
    //     (f_spec_is_jalr && f_spec_btb_hit) ? btb_target_state[f_spec_pc_idx] :
    //     f_default_pc;

    // always@ (posedge clk) begin
    //     if (rst) begin
    //         nw_pc <= 32'h80000000;
    //     end
    //     else if (e_train_redirect) begin
    //         nw_pc <= e_redirect_pc;
    //     end
    //     else if (f_allow_in) begin
    //         nw_pc <= f_spec_pred_pc;
    //     end
    // end

    
    reg [N - 1:0] ghr_state;
    reg [1:0]     pht_state     [(1 << N) - 1:0];
    reg [N - 1:0] lht_state     [(1 << N) - 1:0];
    reg [1:0]     lpht_state    [(1 << N) - 1:0];
    reg [1:0]     chooser_state [(1 << N) - 1:0];

    // BTB (for JALR)
    reg [31:0] btb_target_state [(1 << N) - 1:0];
    reg [31:0] btb_tag_state    [(1 << N) - 1:0];

    // RAS (for returns: ret = jalr x0, x1, 0)
    reg [31:0] ras_state [RAS_DEPTH - 1:0];
    reg [RAS_W - 1:0] ras_sp_state;

    // Fetch-stage speculative instruction information
    wire f_spec_is_cond_br = (f_instr_type == `TYPEB);
    wire f_spec_is_jal     = (f_instr_type == `TYPEJ);
    wire f_spec_is_jalr    = (f_opcode == `OP_JALR);
    // Treat SYSTEM as control-like instruction, so redirect/flush path can be reused for ecall/mret
    wire f_spec_is_system = (f_opcode == `OP_SYSTEM);
    assign f_spec_is_jump_instr = f_spec_is_cond_br || f_spec_is_jal || f_spec_is_jalr || f_spec_is_system;

    // Execute-stage training instruction information
    wire e_train_valid_jump   = e_stage_is_jump_instr && e_stage_valid;
    wire e_train_is_cond_br   = e_is_cond_br;
    wire e_train_is_jalr      = e_is_jalr;
    wire e_train_redirect     = e_train_valid_jump && !e_pred_correct; // mispredict/wrong-target redirect

    // RAS: speculative call/ret detection
    wire f_spec_is_call = (f_spec_is_jal || f_spec_is_jalr) && ((f_rd == 5'd1) || (f_rd == 5'd5));
    wire f_spec_is_ret  = f_spec_is_jalr && (f_rd == 5'd0) && ((f_rs1 == 5'd1) || (f_rs1 == 5'd5)) && (f_imm == 32'd0);

    // RAS create snapshot
    reg [RAS_DEPTH * 32 - 1:0] f_spec_ras_snapshot_r;
    integer ras_i;
    always @* begin
        // default: snapshot current stack contents
        for (ras_i = 0; ras_i < RAS_DEPTH; ras_i = ras_i + 1) begin
            f_spec_ras_snapshot_r[ras_i * 32 +: 32] = ras_state[ras_i];
        end
        // CALL: snapshot should reflect the pushed return address at current sp
        if (f_spec_is_call && f_allow_in) begin
            f_spec_ras_snapshot_r[ras_sp_state * 32 +: 32] = f_default_pc;
        end
    end
    assign f_spec_ras_snapshot = f_spec_ras_snapshot_r;

    // RAS top and next sp
    wire f_spec_ras_empty = (ras_sp_state == {RAS_W{1'b0}});
    wire [31:0] f_spec_ras_top = f_spec_ras_empty ? 32'd0 : ras_state[ras_sp_state - 1'b1];
    assign f_spec_ras_sp_next = f_spec_is_call ? (ras_sp_state + 1'b1) :
        (f_spec_is_ret && !f_spec_ras_empty) ? (ras_sp_state - 1'b1) :
        ras_sp_state;

    // Indix of speculate and train
    wire [N - 1:0] f_spec_pc_idx  = F_pc[N + 1:2];
    wire [N - 1:0] e_train_pc_idx = e_pc[N + 1:2];

    // BTB hit or not
    wire f_spec_btb_hit = (btb_tag_state[f_spec_pc_idx] == F_pc);

    // gshare idx and local idx and choose gshare taken or local taken
    wire [N - 1:0] f_spec_lht_snap = lht_state[f_spec_pc_idx];
    wire [N - 1:0] f_spec_gidx = f_spec_pc_idx ^ ghr_state;
    wire [N - 1:0] f_spec_lidx = f_spec_pc_idx ^ f_spec_lht_snap;
    wire f_spec_g_taken = pht_state[f_spec_gidx][1];
    wire f_spec_l_taken = lpht_state[f_spec_lidx][1];
    wire f_spec_use_local = chooser_state[f_spec_pc_idx][1];

    assign f_spec_lht_snapshot   = f_spec_lht_snap;
    assign f_spec_gshare_taken   = f_spec_g_taken;
    assign f_spec_local_taken    = f_spec_l_taken;

    // Execute training / rollback updates 
    always@ (posedge clk) begin
        if (rst) begin
            ghr_state <= 0;
            ras_sp_state <= 0;
            for(integer r = 0; r < RAS_DEPTH; r = r + 1) begin
                ras_state[r] <= 32'd0;
            end
            for(integer i = 0; i < (1 << N); i = i + 1) begin
                pht_state[i] = 2'b01;
                lpht_state[i] = 2'b01;
                chooser_state[i] = 2'b10;
                lht_state[i] = {N{1'b0}};
                btb_target_state[i] = 32'd0;
                btb_tag_state[i] = 32'd0;
            end
        end
        else begin
            // GShare update
            if (e_train_valid_jump && e_train_is_cond_br && !e_pred_correct) begin
                ghr_state <= {e_train_ghr_snapshot[N - 2:0], e_actual_taken};
            end
            else if (f_allow_in && f_spec_is_cond_br) begin
                ghr_state <= {ghr_state[N - 2:0], f_spec_pred_taken};
            end

            // Local history update
            if (e_train_valid_jump && e_train_is_cond_br && !e_pred_correct) begin
                lht_state[e_train_pc_idx] <= {e_train_lht_snapshot[N - 2:0], e_actual_taken};
            end
            else if (f_allow_in && f_spec_is_cond_br) begin
                lht_state[f_spec_pc_idx] <= {lht_state[f_spec_pc_idx][N - 2:0], f_spec_pred_taken};
            end

            // if B-instruction, update pht and lpht
            if (e_train_valid_jump && e_train_is_cond_br) begin
                // train pht
                if (e_actual_taken) begin
                    pht_state[e_train_ghr_snapshot ^ e_pc[N + 1:2]] <=
                        (pht_state[e_train_ghr_snapshot ^ e_pc[N + 1:2]] == 2'b11)
                        ? 2'b11 : pht_state[e_train_ghr_snapshot ^ e_pc[N + 1:2]] + 1'b1;
                end
                else begin
                    pht_state[e_train_ghr_snapshot ^ e_pc[N + 1:2]] <=
                        (pht_state[e_train_ghr_snapshot ^ e_pc[N + 1:2]] == 2'b00)
                        ? 2'b00 : pht_state[e_train_ghr_snapshot ^ e_pc[N + 1:2]] - 1'b1;
                end

                // train lpht
                if (e_actual_taken) begin
                    lpht_state[(e_pc[N + 1:2]) ^ e_train_lht_snapshot] <=
                        (lpht_state[(e_pc[N + 1:2]) ^ e_train_lht_snapshot] == 2'b11)
                        ? 2'b11 : lpht_state[(e_pc[N + 1:2]) ^ e_train_lht_snapshot] + 1'b1;
                end
                else begin
                    lpht_state[(e_pc[N + 1:2]) ^ e_train_lht_snapshot] <=
                        (lpht_state[(e_pc[N + 1:2]) ^ e_train_lht_snapshot] == 2'b00)
                        ? 2'b00 : lpht_state[(e_pc[N + 1:2]) ^ e_train_lht_snapshot] - 1'b1;
                end

                // train chooser
                if ((e_train_local_taken == e_actual_taken) && (e_train_gshare_taken != e_actual_taken)) begin
                    chooser_state[e_train_pc_idx] <= (chooser_state[e_train_pc_idx] == 2'b11) ? 2'b11 : chooser_state[e_train_pc_idx] + 1'b1;
                end
                else if ((e_train_gshare_taken == e_actual_taken) && (e_train_local_taken != e_actual_taken)) begin
                    chooser_state[e_train_pc_idx] <= (chooser_state[e_train_pc_idx] == 2'b00) ? 2'b00 : chooser_state[e_train_pc_idx] - 1'b1;
                end
            end

            // BTB update for JALR (including ret)
            if (e_train_valid_jump && e_train_is_jalr) begin
                btb_target_state[e_train_pc_idx] <= e_redirect_pc;
                btb_tag_state[e_train_pc_idx] <= e_pc;
            end

            // RAS update and rollback
            if (e_train_redirect) begin
                ras_sp_state <= e_train_ras_sp;
                for(integer r = 0; r < RAS_DEPTH; r = r + 1) begin
                    // recover each 32-bit entry from the packed snapshot
                    ras_state[r] <= e_train_ras_snapshot[r * 32 +: 32];
                end
            end
            else if (f_allow_in) begin
                if (f_spec_is_call) begin
                    ras_state[ras_sp_state] <= f_default_pc;
                    ras_sp_state <= ras_sp_state + 1'b1;
                end
                else if (f_spec_is_ret) begin
                    if (!f_spec_ras_empty) ras_sp_state <= ras_sp_state - 1'b1;
                end
            end
        end 
    end

    // 在fetch_stage模块内添加：

    // ==================== 真正AI预测器集成（简化版）====================

    // 1. 特征提取（预测时）- 使用现有func3字段
    wire [7:0] ai_features;
    assign ai_features = {
        // [7:6] PC模式
        F_pc[2],                    // PC地址对齐
        F_pc[3] ^ F_pc[2],          // PC地址变化
        
        // [5:4] 历史模式
        ghr_state[0],               // 最近跳转
        ghr_state[0] ^ ghr_state[1], // 跳转变化
        
        // [3:2] 指令类型 - 直接使用现有func3！
        (func3 == 3'b000),          // 是BEQ
        (func3 == 3'b001),          // 是BNE
        
        // [1:0] 跳转特征
        !f_imm[31],                 // 向前跳转
        (f_imm[11:0] < 12'd16)      // 短距离跳转
    };

    // 2. 训练时特征 - 只需要e_func3
    wire [7:0] ai_train_features;
    assign ai_train_features = {
        e_pc[2],
        e_pc[3] ^ e_pc[2],
        e_train_ghr_snapshot[0],
        e_train_ghr_snapshot[0] ^ e_train_ghr_snapshot[1],
        (e_func3 == 3'b000),        // 训练时的func3
        (e_func3 == 3'b001),
        !e_imm[31],                 // 还是需要e_imm，但只需要符号位和低12位
        (e_imm[11:0] < 12'd16)
    };

    // 3. AI预测器实例化（同前）
    wire ai_prediction;
    wire signed [10:0] ai_confidence;

    ai_pred u_ai_pred (
        .clk(clk),
        .rst(rst),
        .predict_en((f_instr_type == `TYPEB) && f_allow_in),
        .features(ai_features),
        .prediction(ai_prediction),
        .confidence(ai_confidence),
        .train_en(e_train_valid_jump && e_is_cond_br),
        .train_features(ai_train_features),
        .actual_taken(e_actual_taken)
    );

    // 4. 混合预测逻辑（同前）
    wire signed [10:0] traditional_confidence;
    assign traditional_confidence = 
        f_spec_use_local ? 
            (lpht_state[f_spec_lidx] == 2'b11) ? 11'sd30 :
            (lpht_state[f_spec_lidx] == 2'b00) ? -11'sd30 :
            (lpht_state[f_spec_lidx] == 2'b10) ? 11'sd15 :
            -11'sd15 :
            (pht_state[f_spec_gidx] == 2'b11) ? 11'sd30 :
            (pht_state[f_spec_gidx] == 2'b00) ? -11'sd30 :
            (pht_state[f_spec_gidx] == 2'b10) ? 11'sd15 :
            -11'sd15;

    wire ai_more_confident;
    assign ai_more_confident = 
        (ai_confidence > 20 && ai_confidence > traditional_confidence) ||
        (ai_confidence < -20 && ai_confidence < traditional_confidence);

    // 5. 修改最终的预测选择
    wire f_spec_br_taken;
    assign f_spec_br_taken = 
        (ai_more_confident && (f_instr_type == `TYPEB)) ? ai_prediction :
        (f_spec_use_local ? f_spec_l_taken : f_spec_g_taken);

    // conditional branch taken or not and jump instruction taken or not and gshare snapshot
    assign f_spec_pred_taken   = f_spec_is_cond_br ? f_spec_br_taken : (f_spec_is_jump_instr ? 1'b1 : 1'b0);
    assign f_spec_ghr_snapshot = ghr_state;

    // predicted next pc for this instruction
    wire [31:0] f_spec_pred_target_pc;
    assign f_spec_pred_pc = (f_spec_is_jump_instr && f_spec_pred_taken) ? f_spec_pred_target_pc : f_default_pc;

    // Target prediction
    assign f_spec_pred_target_pc =
        (f_spec_is_cond_br || f_spec_is_jal) ? ((F_pc + f_imm) & -1) :
        (f_spec_is_ret && !f_spec_ras_empty) ? f_spec_ras_top :
        (f_spec_is_jalr && f_spec_btb_hit) ? btb_target_state[f_spec_pc_idx] :
        f_default_pc;

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
