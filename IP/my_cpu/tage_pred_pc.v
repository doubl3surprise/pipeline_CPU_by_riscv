module tage_pred_pc #(
    parameter integer N = 10,
    parameter integer TAG_BITS = 10
)(
    input  wire clk,
    input  wire rst,

    input  wire        predict_en,
    input  wire [31 : 0] pc,
    input  wire [31 : 0] ghr,

    input  wire        train_en,
    input  wire [31 : 0] train_pc,
    input  wire [31 : 0] train_ghr,
    input  wire        actual_taken,

    output wire        prediction,
    output wire signed [15 : 0] confidence,
    output wire [2 : 0] provider_id
);
    localparam integer SZ = (1 << N);

    reg [1:0] base_ctr [0:SZ - 1];

    // 使用标准 2-bit 饱和计数器：00 强不跳，01 弱不跳，10 弱跳，11 强跳
    reg [1 : 0] t1_ctr [0 : SZ - 1];
    reg [TAG_BITS - 1 : 0] t1_tag [0 : SZ - 1];
    reg t1_v [0 : SZ - 1];
    reg [1 : 0] t2_ctr [0 : SZ - 1];
    reg [TAG_BITS - 1 : 0] t2_tag [0 : SZ - 1];
    reg t2_v [0 : SZ - 1];
    reg [1 : 0] t3_ctr [0 : SZ - 1];
    reg [TAG_BITS - 1 : 0] t3_tag [0 : SZ - 1];
    reg t3_v [0 : SZ - 1];
    reg [1 : 0] t4_ctr [0 : SZ - 1];
    reg [TAG_BITS - 1 : 0] t4_tag [0 : SZ - 1];
    reg t4_v [0 : SZ - 1];
    
    function [N - 1 : 0] idx_hash;
        input [31 : 0] pc_i;
        input [31 : 0] h;
        input integer hl;
        reg [31 : 0] x;
    begin
        x = pc_i ^ (h ^ (h >> hl) ^ (h << (hl / 2)));
        idx_hash = x[N + 1 : 2] ^ x[N - 1 : 0];
    end
    endfunction

    function [TAG_BITS - 1 : 0] tag_hash;
        input [31 : 0] pc_i;
        input [31 : 0] h;
        input integer hl;
        reg [31 : 0] x;
    begin
        x = (pc_i >> 2) ^ (h ^ (h >> (hl / 2)));
        tag_hash = x[TAG_BITS - 1 : 0];
    end
    endfunction

    localparam integer H1 = 2;
    localparam integer H2 = 4;
    localparam integer H3 = 8;
    localparam integer H4 = 16;

    wire [N - 1 : 0] base_idx = pc[N + 1 : 2];
    wire [N - 1 : 0] t1_idx = idx_hash(pc, ghr, H1);
    wire [N - 1 : 0] t2_idx = idx_hash(pc, ghr, H2);
    wire [N - 1 : 0] t3_idx = idx_hash(pc, ghr, H3);
    wire [N - 1 : 0] t4_idx = idx_hash(pc, ghr, H4);
    wire [TAG_BITS - 1 : 0] t1_t = tag_hash(pc, ghr, H1);
    wire [TAG_BITS - 1 : 0] t2_t = tag_hash(pc, ghr, H2);
    wire [TAG_BITS - 1 : 0] t3_t = tag_hash(pc, ghr, H3);
    wire [TAG_BITS - 1 : 0] t4_t = tag_hash(pc, ghr, H4);

    wire t1_hit = t1_v[t1_idx] && (t1_tag[t1_idx] == t1_t);
    wire t2_hit = t2_v[t2_idx] && (t2_tag[t2_idx] == t2_t);
    wire t3_hit = t3_v[t3_idx] && (t3_tag[t3_idx] == t3_t);
    wire t4_hit = t4_v[t4_idx] && (t4_tag[t4_idx] == t4_t);

    reg [2 : 0] prov;
    reg pred;
    reg signed [15 : 0] conf;
    always @(*) begin
        prov = 3'd0;
        pred = base_ctr[base_idx][1];
        conf = pred ? 16'sd16 : -16'sd16;
        if (t1_hit) begin
            prov = 3'd1; pred = t1_ctr[t1_idx][1];
            conf = (t1_ctr[t1_idx] == 2'b11) ? 16'sd48 :
                   (t1_ctr[t1_idx] == 2'b00) ? -16'sd48 :
                   pred ? 16'sd24 : -16'sd24;
        end
        if (t2_hit) begin
            prov = 3'd2; pred = t2_ctr[t2_idx][1];
            conf = (t2_ctr[t2_idx] == 2'b11) ? 16'sd64 :
                   (t2_ctr[t2_idx] == 2'b00) ? -16'sd64 :
                   pred ? 16'sd32 : -16'sd32;
        end
        if (t3_hit) begin
            prov = 3'd3; pred = t3_ctr[t3_idx][1];
            conf = (t3_ctr[t3_idx] == 2'b11) ? 16'sd80 :
                   (t3_ctr[t3_idx] == 2'b00) ? -16'sd80 :
                   pred ? 16'sd40 : -16'sd40;
        end
        if (t4_hit) begin
            prov = 3'd4; pred = t4_ctr[t4_idx][1];
            conf = (t4_ctr[t4_idx] == 2'b11) ? 16'sd96 :
                   (t4_ctr[t4_idx] == 2'b00) ? -16'sd96 :
                   pred ? 16'sd48 : -16'sd48;
        end
    end

    assign prediction  = pred;
    assign confidence  = conf;
    assign provider_id = prov;


    wire [N - 1 : 0] train_bidx = train_pc[N + 1 : 2];
    wire [N - 1 : 0] train_i1 = idx_hash(train_pc, train_ghr, H1);
    wire [N - 1 : 0] train_i2 = idx_hash(train_pc, train_ghr, H2);
    wire [N - 1 : 0] train_i3 = idx_hash(train_pc, train_ghr, H3);
    wire [N - 1 : 0] train_i4 = idx_hash(train_pc, train_ghr, H4);
    wire [TAG_BITS - 1 : 0] train_tg1 = tag_hash(train_pc, train_ghr, H1);
    wire [TAG_BITS - 1 : 0] train_tg2 = tag_hash(train_pc, train_ghr, H2);
    wire [TAG_BITS - 1 : 0] train_tg3 = tag_hash(train_pc, train_ghr, H3);
    wire [TAG_BITS - 1 : 0] train_tg4 = tag_hash(train_pc, train_ghr, H4);
    wire train_h1 = t1_v[train_i1] && (t1_tag[train_i1] == train_tg1);
    wire train_h2 = t2_v[train_i2] && (t2_tag[train_i2] == train_tg2);
    wire train_h3 = t3_v[train_i3] && (t3_tag[train_i3] == train_tg3);
    wire train_h4 = t4_v[train_i4] && (t4_tag[train_i4] == train_tg4);

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < SZ; i = i + 1) begin
                base_ctr[i] <= 2'b01;
                t1_ctr[i] <= 2'b01;
                t1_tag[i] <= '0;
                t1_v[i] <= 1'b0;
                t2_ctr[i] <= 2'b01;
                t2_tag[i] <= '0;
                t2_v[i] <= 1'b0;
                t3_ctr[i] <= 2'b01;
                t3_tag[i] <= '0;
                t3_v[i] <= 1'b0;
                t4_ctr[i] <= 2'b01;
                t4_tag[i] <= '0;
                t4_v[i] <= 1'b0;
            end
        end
        else if (train_en) begin
            if (actual_taken) begin
                if (base_ctr[train_bidx] != 2'b11) begin 
                    base_ctr[train_bidx] <= base_ctr[train_bidx] + 1'b1;
                end
            end 
            else begin
                if (base_ctr[train_bidx] != 2'b00) begin
                    base_ctr[train_bidx] <= base_ctr[train_bidx] - 1'b1;
                end
            end

            // provider update priority: T4 > T3 > T2 > T1 > base
            if (train_h4) begin
                if (actual_taken) begin
                    if (t4_ctr[train_i4] != 2'b11) begin
                        t4_ctr[train_i4] <= t4_ctr[train_i4] + 1'b1;
                    end
                end
                else begin
                    if (t4_ctr[train_i4] != 2'b00) begin
                        t4_ctr[train_i4] <= t4_ctr[train_i4] - 1'b1;
                    end
                end
            end
            else if (train_h3) begin
                if (actual_taken) begin
                    if (t3_ctr[train_i3] != 2'b11) begin
                        t3_ctr[train_i3] <= t3_ctr[train_i3] + 1'b1;
                    end
                end
                else begin
                    if (t3_ctr[train_i3] != 2'b00) begin
                        t3_ctr[train_i3] <= t3_ctr[train_i3] - 1'b1;
                    end
                end
                // allocate longer table if empty and mispred
                if ((t3_ctr[train_i3][1] != actual_taken) && !t4_v[train_i4]) begin
                    t4_v[train_i4]   <= 1'b1;
                    t4_tag[train_i4] <= train_tg4;
                    t4_ctr[train_i4] <= actual_taken ? 2'b10 : 2'b01;
                end
            end
            else if (train_h2) begin
                if (actual_taken) begin
                    if (t2_ctr[train_i2] != 2'b11) begin
                        t2_ctr[train_i2] <= t2_ctr[train_i2] + 1'b1;
                    end
                end
                else begin
                    if (t2_ctr[train_i2] != 2'b00) begin
                        t2_ctr[train_i2] <= t2_ctr[train_i2] - 1'b1;
                    end
                end
                if ((t2_ctr[train_i2][1] != actual_taken) && !t3_v[train_i3]) begin
                    t3_v[train_i3]   <= 1'b1;
                    t3_tag[train_i3] <= train_tg3;
                    t3_ctr[train_i3] <= actual_taken ? 2'b10 : 2'b01;
                end
            end 
            else if (train_h1) begin
                if (actual_taken) begin
                    if (t1_ctr[train_i1] != 2'b11) begin
                        t1_ctr[train_i1] <= t1_ctr[train_i1] + 1'b1;
                    end
                end
                else begin
                    if (t1_ctr[train_i1] != 2'b00) begin
                        t1_ctr[train_i1] <= t1_ctr[train_i1] - 1'b1;
                    end
                end
                if ((t1_ctr[train_i1][1] != actual_taken) && !t2_v[train_i2]) begin
                    t2_v[train_i2]   <= 1'b1;
                    t2_tag[train_i2] <= train_tg2;
                    t2_ctr[train_i2] <= actual_taken ? 2'b10 : 2'b01;
                end
            end 
            else begin
                if ((base_ctr[train_bidx][1] != actual_taken) && !t1_v[train_i1]) begin
                    t1_v[train_i1]   <= 1'b1;
                    t1_tag[train_i1] <= train_tg1;
                    t1_ctr[train_i1] <= actual_taken ? 2'b10 : 2'b01;
                end
            end
        end
    end
endmodule


