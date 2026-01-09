`include "define.v"
module pc_pred #(
    parameter integer N = 12,
    parameter integer RAS_DEPTH = 16,
    parameter integer RAS_W = 4,
    // 0 = old1(gshare + lht), 1 = old2(gshare + lht + ai), 2 = hybrid(perceptron + path + tage + mlp)
    parameter integer PRED_MODE = 2, 
    parameter integer PATH_LEN = 4
)(
    input  wire clk,
    input  wire rst,

    // fetch-side inputs
    input  wire        f_allow_in,
    input  wire [31:0] F_pc,
    input  wire [31:0] f_default_pc,
    input  wire [6:0]  f_opcode,
    input  wire [4:0]  f_rd,
    input  wire [4:0]  f_rs1,
    input  wire [2:0]  f_instr_type,
    input  wire [2:0]  f_func3,
    input  wire [31:0] f_imm,

    // outputs to pipeline
    output wire        f_spec_is_jump_instr,
    output wire        f_spec_pred_taken,
    output wire [N - 1:0] f_spec_ghr_snapshot,
    output wire [31:0] f_spec_pred_pc,
    output wire [RAS_W - 1:0] f_spec_ras_sp_next,
    output wire [RAS_DEPTH * 32 - 1:0] f_spec_ras_snapshot,
    output wire [N - 1:0] f_spec_lht_snapshot,
    output wire        f_spec_gshare_taken,
    output wire        f_spec_local_taken,
    // path history snapshot (PATH_LEN-1 entries, packed as ((PATH_LEN-1)*32) bits)
    output wire [(PATH_LEN - 1) * 32 - 1:0] f_spec_path_snapshot,
    // hybrid feature snapshot (32 bits) captured at fetch for training
    output wire [31:0] f_spec_hybrid_feature_snapshot,

    // execute-stage training inputs
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
    input  wire        e_train_gshare_taken,
    input  wire        e_train_local_taken,
    input  wire [2:0]  e_func3,
    input  wire [31:0] e_imm,
    // path history snapshot carried with the training instruction (PATH_LEN-1 entries)
    input  wire [(PATH_LEN - 1) * 32 - 1:0] e_train_path_snapshot,
    // hybrid feature snapshot carried with the training instruction
    input  wire [31:0] e_train_hybrid_feature_snapshot
);
    // execute-stage redirect info (used by multiple predictors, including path history rollback)
    wire e_train_valid_jump = e_stage_is_jump_instr && e_stage_valid;
    wire e_train_redirect   = e_train_valid_jump && !e_pred_correct;

    // state for gshare + local + chooser + BTB + RAS
    reg [N - 1:0] ghr_state;
    reg [1:0]   pht_state     [(1 << N) - 1:0];
    reg [N - 1:0] lht_state     [(1 << N) - 1:0];
    reg [1:0]   lpht_state    [(1 << N) - 1:0];
    reg [1:0]   chooser_state [(1 << N) - 1:0];

    // BTB (for JALR)
    reg [31:0] btb_target_state [(1 << N) - 1:0];
    reg [31:0] btb_tag_state    [(1 << N) - 1:0];

    // RAS (for returns)
    reg [31:0] ras_state [RAS_DEPTH - 1:0];
    reg [RAS_W - 1:0] ras_sp_state;

    // judge if the instruction is a jump/branch/system instruction for prediction
    wire f_spec_is_cond_br = (f_instr_type == `TYPEB);
    wire f_spec_is_jal     = (f_instr_type == `TYPEJ);
    wire f_spec_is_jalr    = (f_opcode == `OP_JALR);
    wire f_spec_is_system  = (f_opcode == `OP_SYSTEM);
    assign f_spec_is_jump_instr = f_spec_is_cond_br || f_spec_is_jal || f_spec_is_jalr || f_spec_is_system;

    // RAS: call/ret detection
    wire f_spec_is_call = (f_spec_is_jal || f_spec_is_jalr) && ((f_rd == 5'd1) || (f_rd == 5'd5));
    wire f_spec_is_ret  = f_spec_is_jalr && (f_rd == 5'd0) && ((f_rs1 == 5'd1) || (f_rs1 == 5'd5)) && (f_imm == 32'd0);

    // RAS snapshot
    reg [RAS_DEPTH * 32 - 1:0] f_spec_ras_snapshot_r;
    integer ras_i;
    always @* begin
        for (ras_i = 0; ras_i < RAS_DEPTH; ras_i = ras_i + 1) begin
            f_spec_ras_snapshot_r[ras_i * 32 +: 32] = ras_state[ras_i];
        end
        if (f_spec_is_call && f_allow_in) begin
            f_spec_ras_snapshot_r[ras_sp_state * 32 +: 32] = f_default_pc;
        end
    end
    assign f_spec_ras_snapshot = f_spec_ras_snapshot_r;

    wire f_spec_ras_empty = (ras_sp_state == {RAS_W{1'b0}});
    wire [31:0] f_spec_ras_top = f_spec_ras_empty ? 32'd0 : ras_state[ras_sp_state - 1'b1];
    assign f_spec_ras_sp_next = f_spec_is_call ? (ras_sp_state + 1'b1) :
        (f_spec_is_ret && !f_spec_ras_empty) ? (ras_sp_state - 1'b1) :
        ras_sp_state;

    // index for BTB/LHT/PHT/chooser
    wire [N - 1:0] f_spec_pc_idx  = F_pc[N + 1:2];
    wire [N - 1:0] e_train_pc_idx = e_pc[N + 1:2];

    wire f_spec_btb_hit = (btb_tag_state[f_spec_pc_idx] == F_pc);

    wire [N - 1:0] f_spec_lht_snap = lht_state[f_spec_pc_idx];
    wire [N - 1:0] f_spec_gidx = f_spec_pc_idx ^ ghr_state;
    wire [N - 1:0] f_spec_lidx = f_spec_pc_idx ^ f_spec_lht_snap;
    wire f_spec_g_taken = pht_state[f_spec_gidx][1];
    wire f_spec_l_taken = lpht_state[f_spec_lidx][1];
    wire f_spec_use_local = chooser_state[f_spec_pc_idx][1];

    assign f_spec_lht_snapshot = f_spec_lht_snap;
    assign f_spec_gshare_taken = f_spec_g_taken;
    assign f_spec_local_taken  = f_spec_l_taken;

    // ------------- old1 --------------------
    wire base_br_taken = f_spec_use_local ? f_spec_l_taken : f_spec_g_taken;

    // ------------- old2 --------------------
    wire [7:0] ai_features = {
        F_pc[2],
        F_pc[3] ^ F_pc[2],
        ghr_state[0],
        ghr_state[0] ^ ghr_state[1],
        (f_func3 == 3'b000),
        (f_func3 == 3'b001),
        !f_imm[31],
        (f_imm[11:0] < 12'd16)
    };

    wire [7:0] ai_train_features = {
        e_pc[2],
        e_pc[3] ^ e_pc[2],
        e_train_ghr_snapshot[0],
        e_train_ghr_snapshot[0] ^ e_train_ghr_snapshot[1],
        (e_func3 == 3'b000),
        (e_func3 == 3'b001),
        !e_imm[31],
        (e_imm[11:0] < 12'd16)
    };

    wire ai_prediction;
    wire signed [10:0] ai_confidence;
    ai_pred u_ai_pred (
        .clk(clk),
        .rst(rst),
        .predict_en(f_spec_is_cond_br && f_allow_in),
        .features(ai_features),
        .prediction(ai_prediction),
        .confidence(ai_confidence),
        .train_en(e_stage_valid && e_stage_is_jump_instr && e_is_cond_br),
        .train_features(ai_train_features),
        .actual_taken(e_actual_taken)
    );

    wire signed [10:0] traditional_confidence =
        f_spec_use_local ?
            (lpht_state[f_spec_lidx] == 2'b11) ? 11'sd30 :
            (lpht_state[f_spec_lidx] == 2'b00) ? -11'sd30 :
            (lpht_state[f_spec_lidx] == 2'b10) ? 11'sd15 : -11'sd15 :
            (pht_state[f_spec_gidx] == 2'b11) ? 11'sd30 :
            (pht_state[f_spec_gidx] == 2'b00) ? -11'sd30 :
            (pht_state[f_spec_gidx] == 2'b10) ? 11'sd15 : -11'sd15;

    wire ai_more_confident =
        (ai_confidence > 20 && ai_confidence > traditional_confidence) ||
        (ai_confidence < -20 && ai_confidence < traditional_confidence);

    wire ai_br_taken = (ai_more_confident && f_spec_is_cond_br) ? ai_prediction : base_br_taken;

    // ---------------- perceptron + path + tage + mlp --------------------
    wire [1:0] branch_hist_pat = {ghr_state[1], ghr_state[0]};
    wire ras_full = 1'b0;

    wire [31:0] hybrid_features = {
        ghr_state[7:0],
        F_pc[2], F_pc[3], F_pc[4], F_pc[5],
        ghr_state[0] ^ ghr_state[1],
        ghr_state[1] ^ ghr_state[2],
        ghr_state[2] ^ ghr_state[3],
        ghr_state[3] ^ ghr_state[4],
        (f_func3 == 3'b000),
        (f_func3 == 3'b001),
        (f_func3 == 3'b100),
        (f_func3 == 3'b101),
        !f_imm[31],
        f_imm[31],
        (f_imm[11:0] < 12'd16),
        (f_imm[11:0] > 12'd1024),
        f_spec_is_call,
        f_spec_is_ret,
        (F_pc[1:0] == 2'b00),
        branch_hist_pat[0],
        f_spec_ras_empty,
        ras_full,
        (|ghr_state[3:0]),
        branch_hist_pat[1]
    };

    assign f_spec_hybrid_feature_snapshot = hybrid_features;
    wire [31:0] train_features = e_train_hybrid_feature_snapshot;

    // perceptron
    wire perc_pred;
    wire signed [15:0] perc_conf;
    perceptron_pred_pc #(
        .NUM_SETS(64),
        .WAYS(2),
        .FEATURES(32),
        .WEIGHT_BITS(8),
        .TAG_BITS(16)
    ) u_perc (
        .clk(clk),
        .rst(rst),
        .predict_en(f_spec_is_cond_br && f_allow_in),
        .pc(F_pc),
        .predict_features(hybrid_features),
        .train_en(e_stage_valid && e_stage_is_jump_instr && e_is_cond_br),
        .train_pc(e_pc),
        .train_features(train_features),
        .actual_taken(e_actual_taken),
        .prediction(perc_pred),
        .confidence(perc_conf)
    );

    // mlp
    wire mlp_pred;
    wire signed [15:0] mlp_conf;
    mlp_pred_pc u_mlp (
        .clk(clk),
        .rst(rst),
        .predict_en(f_spec_is_cond_br && f_allow_in),
        .pc(F_pc),
        .predict_features(hybrid_features),
        .train_en(e_stage_valid && e_stage_is_jump_instr && e_is_cond_br),
        .train_pc(e_pc),
        .train_features(train_features),
        .actual_taken(e_actual_taken),
        .prediction(mlp_pred),
        .confidence(mlp_conf)
    );

    // tage
    wire tage_pred;
    wire signed [15:0] tage_conf;
    wire [2:0] tage_provider;
    tage_pred_pc #(.N(10), .TAG_BITS(10)) u_tage (
        .clk(clk),
        .rst(rst),
        .predict_en(f_spec_is_cond_br && f_allow_in),
        .pc(F_pc),
        .ghr({{(32-N){1'b0}}, ghr_state}),
        .train_en(e_stage_valid && e_stage_is_jump_instr && e_is_cond_br),
        .train_pc(e_pc),
        .train_ghr({{(32-N){1'b0}}, e_train_ghr_snapshot}),
        .actual_taken(e_actual_taken),
        .prediction(tage_pred),
        .confidence(tage_conf),
        .provider_id(tage_provider)
    );


    localparam integer PATH_HIST_W = (PATH_LEN - 1) * 32;
    reg [PATH_HIST_W - 1:0] path_hist_state;

    assign f_spec_path_snapshot = path_hist_state;

    integer ph_i;
    always @(posedge clk) begin
        if (rst) begin
            path_hist_state <= {PATH_HIST_W{1'b0}};
        end 
        else if (e_train_redirect) begin
            // rollback: snapshot + insert e_pc
            path_hist_state[0 +: 32] <= e_pc;
            for (ph_i = 1; ph_i < PATH_LEN - 1; ph_i = ph_i + 1) begin
                path_hist_state[ph_i * 32 +: 32] <= e_train_path_snapshot[(ph_i - 1) * 32 +: 32];
            end
        end 
        else if (f_allow_in) begin
            // speculative advance: insert F_pc
            path_hist_state[0 +: 32] <= F_pc;
            for (ph_i = 1; ph_i < PATH_LEN - 1; ph_i = ph_i + 1) begin
                path_hist_state[ph_i * 32 +: 32] <= path_hist_state[(ph_i - 1) * 32 +: 32];
            end
        end
    end

    wire [PATH_LEN * 32 - 1:0] f_path_full;
    wire [PATH_LEN * 32 - 1:0] e_path_full;
    assign f_path_full[0 +: 32] = F_pc;
    assign e_path_full[0 +: 32] = e_pc;
    genvar pi;
    generate
        for (pi = 1; pi < PATH_LEN; pi = pi + 1) begin : pack_path
            assign f_path_full[pi * 32 +: 32] = path_hist_state[(pi - 1) * 32 +: 32];
            assign e_path_full[pi * 32 +: 32] = e_train_path_snapshot[(pi - 1) * 32 +: 32];
        end
    endgenerate

    wire path_pred;
    wire [1:0] path_conf2;
    path_history_track_pred_pc #(.PATH_LEN(PATH_LEN)) u_path (
        .clk(clk),
        .rst(rst),
        .predict_en(f_spec_is_cond_br && f_allow_in),
        .pc(F_pc),
        .path_history(f_path_full),
        .train_en(e_stage_valid && e_stage_is_jump_instr && e_is_cond_br),
        .train_pc(e_pc),
        .train_path(e_path_full),
        .actual_taken(e_actual_taken),
        .prediction(path_pred),
        .confidence(path_conf2)
    );

    wire signed [15:0] path_conf =
        (path_conf2 == 2'b00) ? 16'sd0 :
        (path_conf2 == 2'b01) ? (path_pred ? 16'sd8  : -16'sd8)  :
        (path_conf2 == 2'b10) ? (path_pred ? 16'sd16 : -16'sd16) :
                                (path_pred ? 16'sd24 : -16'sd24);

    // hybrid voting（显式扩展到18位，避免verilator位宽告警）
    wire signed [17:0] perc_conf_18 = {{2{perc_conf[15]}}, perc_conf};
    wire signed [17:0] mlp_conf_18  = {{2{mlp_conf[15]}},  mlp_conf};
    wire signed [17:0] tage_conf_18 = {{2{tage_conf[15]}}, tage_conf};
    wire signed [17:0] path_conf_18 = {{2{path_conf[15]}}, path_conf};

    wire signed [17:0] vote =
        (perc_conf_18 >>> 1) +
        (mlp_conf_18  >>> 2) +
        (tage_conf_18 >>> 2) +
        (path_conf_18 >>> 1);

    wire hybrid_br_taken = (vote == 0) ? base_br_taken : (vote > 0);

    wire sel_br_taken =
        (PRED_MODE == 0) ? base_br_taken :
        (PRED_MODE == 1) ? ai_br_taken :
                           hybrid_br_taken;

    assign f_spec_pred_taken =
        f_spec_is_cond_br ? sel_br_taken :
        (f_spec_is_jump_instr ? 1'b1 : 1'b0);

    assign f_spec_ghr_snapshot = ghr_state;

    wire [31:0] f_spec_pred_target_pc =
        (f_spec_is_cond_br || f_spec_is_jal) ? ((F_pc + f_imm) & -1) :
        (f_spec_is_ret && !f_spec_ras_empty) ? f_spec_ras_top :
        (f_spec_is_jalr && f_spec_btb_hit) ? btb_target_state[f_spec_pc_idx] :
        f_default_pc;

    assign f_spec_pred_pc = (f_spec_is_jump_instr && f_spec_pred_taken) ? f_spec_pred_target_pc : f_default_pc;

    integer init_i;
    always @(posedge clk) begin
        if (rst) begin
            ghr_state <= '0;
            ras_sp_state <= '0;
            for (ras_i = 0; ras_i < RAS_DEPTH; ras_i = ras_i + 1) begin
                ras_state[ras_i] <= 32'd0;
            end
            for (init_i = 0; init_i < (1 << N); init_i = init_i + 1) begin
                pht_state[init_i]     <= 2'b01;
                lpht_state[init_i]    <= 2'b01;
                chooser_state[init_i] <= 2'b10;
                lht_state[init_i]     <= {N{1'b0}};
                btb_target_state[init_i] <= 32'd0;
                btb_tag_state[init_i]    <= 32'd0;
            end
        end
        else begin
            // GHR update / rollback
            if (e_train_valid_jump && e_is_cond_br && !e_pred_correct) begin
                ghr_state <= {e_train_ghr_snapshot[N - 2 : 0], e_actual_taken};
            end
            else if (f_allow_in && f_spec_is_cond_br) begin
                ghr_state <= {ghr_state[N - 2 : 0], f_spec_pred_taken};
            end

            // Local history update / rollback
            if (e_train_valid_jump && e_is_cond_br && !e_pred_correct) begin
                lht_state[e_train_pc_idx] <= {e_train_lht_snapshot[N - 2 : 0], e_actual_taken};
            end
            else if (f_allow_in && f_spec_is_cond_br) begin
                lht_state[f_spec_pc_idx] <= {lht_state[f_spec_pc_idx][N - 2 : 0], f_spec_pred_taken};
            end

            // pht/lpht/chooser train
            if (e_train_valid_jump && e_is_cond_br) begin
                // train pht
                if (e_actual_taken) begin
                    pht_state[e_train_ghr_snapshot ^ e_pc[N + 1 : 2]] <=
                        (pht_state[e_train_ghr_snapshot ^ e_pc[N + 1 : 2]] == 2'b11) ? 2'b11 :
                        (pht_state[e_train_ghr_snapshot ^ e_pc[N + 1 : 2]] + 1'b1);
                end
                else begin
                    pht_state[e_train_ghr_snapshot ^ e_pc[N + 1 : 2]] <=
                        (pht_state[e_train_ghr_snapshot ^ e_pc[N + 1 : 2]] == 2'b00) ? 2'b00 :
                        (pht_state[e_train_ghr_snapshot ^ e_pc[N + 1 : 2]] - 1'b1);
                end

                // train lpht
                if (e_actual_taken) begin
                    lpht_state[(e_pc[N + 1 : 2]) ^ e_train_lht_snapshot] <=
                        (lpht_state[(e_pc[N + 1 : 2]) ^ e_train_lht_snapshot] == 2'b11) ? 2'b11 :
                        (lpht_state[(e_pc[N + 1 : 2]) ^ e_train_lht_snapshot] + 1'b1);
                end
                else begin
                    lpht_state[(e_pc[N + 1 : 2]) ^ e_train_lht_snapshot] <=
                        (lpht_state[(e_pc[N + 1 : 2]) ^ e_train_lht_snapshot] == 2'b00) ? 2'b00 :
                        (lpht_state[(e_pc[N + 1 : 2]) ^ e_train_lht_snapshot] - 1'b1);
                end

                // train chooser
                if ((e_train_local_taken == e_actual_taken) && (e_train_gshare_taken != e_actual_taken)) begin
                    chooser_state[e_train_pc_idx] <=
                        (chooser_state[e_train_pc_idx] == 2'b11) ? 2'b11 :
                        (chooser_state[e_train_pc_idx] + 1'b1);
                end
                else if ((e_train_gshare_taken == e_actual_taken) && (e_train_local_taken != e_actual_taken)) begin
                    chooser_state[e_train_pc_idx] <=
                        (chooser_state[e_train_pc_idx] == 2'b00) ? 2'b00 :
                        (chooser_state[e_train_pc_idx] - 1'b1);
                end
            end

            // BTB update
            if (e_train_valid_jump && e_is_jalr) begin
                btb_target_state[e_train_pc_idx] <= e_redirect_pc;
                btb_tag_state[e_train_pc_idx]    <= e_pc;
            end

            // RAS rollback or speculative update
            if (e_train_redirect) begin
                ras_sp_state <= e_train_ras_sp;
                for (integer r = 0; r < RAS_DEPTH; r = r + 1) begin
                    ras_state[r] <= e_train_ras_snapshot[r * 32 +: 32];
                end
            end
            else if (f_allow_in) begin
                if (f_spec_is_call) begin
                    ras_state[ras_sp_state] <= f_default_pc;
                    ras_sp_state <= ras_sp_state + 1'b1;
                end
                else if (f_spec_is_ret) begin
                    if (!f_spec_ras_empty) begin
                        ras_sp_state <= ras_sp_state - 1'b1;
                    end
                end
            end
        end
    end
endmodule
