module perceptron_pred_pc #(
    parameter integer NUM_SETS = 64,
    parameter integer WAYS = 2,
    parameter integer FEATURES = 32,
    parameter integer WEIGHT_BITS = 8,
    parameter integer TAG_BITS = 16
)(
    input  wire clk,
    input  wire rst,

    input  wire        predict_en,
    input  wire [31 : 0] pc,
    input  wire [FEATURES - 1 : 0] predict_features,

    input  wire        train_en,
    input  wire [31 : 0] train_pc,
    input  wire [FEATURES - 1 : 0] train_features,
    input  wire        actual_taken,

    output wire        prediction,
    output wire signed [15 : 0] confidence
);
    localparam integer ENTRIES = NUM_SETS * WAYS;
    localparam integer ENTRY_W = $clog2(ENTRIES);
    localparam integer SET_W   = $clog2(NUM_SETS);
    localparam integer WAYS_W  = $clog2(WAYS);

    function automatic signed [WEIGHT_BITS - 1 : 0] rand_small;
        integer r;
    begin
        r = $urandom_range(6) - 3;
        rand_small = $signed(r[WEIGHT_BITS - 1 : 0]);
    end
    endfunction

    reg signed [WEIGHT_BITS - 1 : 0] weights [0 : ENTRIES - 1][0 : FEATURES - 1];
    reg signed [WEIGHT_BITS - 1 : 0] biases [0 : ENTRIES - 1];
    reg [TAG_BITS - 1 : 0] tags [0 : ENTRIES - 1];
    reg valid [0 : ENTRIES - 1];
    reg lru_way [0 : NUM_SETS - 1];

    wire [SET_W - 1 : 0] set_idx;
    wire [TAG_BITS - 1 : 0] tag;
    assign set_idx = pc[2 + SET_W - 1 : 2];
    assign tag = pc[2 + SET_W + TAG_BITS - 1 : 2 + SET_W];

    wire [ENTRY_W - 1 : 0] set_base = {set_idx, {WAYS_W{1'b0}}};

    wire [ENTRY_W - 1 : 0] idx0 = {set_idx, 1'b0};
    wire [ENTRY_W - 1 : 0] idx1 = {set_idx, 1'b1};

    wire hit0 = valid[idx0] && (tags[idx0] == tag);
    wire hit1 = valid[idx1] && (tags[idx1] == tag);
    wire cache_hit = hit0 || hit1;

    wire [ENTRY_W - 1 : 0] hit_entry = hit0 ? idx0 : idx1;

    wire inv0 = ~valid[idx0];
    wire inv1 = ~valid[idx1];
    wire [ENTRY_W - 1 : 0] alloc_entry =
        inv0 ? idx0 :
        inv1 ? idx1 :
        (lru_way[set_idx] ? idx1 : idx0);

    wire [ENTRY_W - 1 : 0] current_entry = cache_hit ? hit_entry : alloc_entry;
    reg signed [15 : 0] current_out;
    integer fi;
    always @(*) begin
        reg signed [23 : 0] sum;
        sum = {{(16 - WEIGHT_BITS){biases[current_entry][WEIGHT_BITS - 1]}}, biases[current_entry], 8'b0};
        for (fi = 0; fi < FEATURES; fi = fi + 1) begin
            if (predict_features[fi]) begin
                sum = sum + {{8{weights[current_entry][fi][WEIGHT_BITS - 1]}},
                             weights[current_entry][fi], 8'b0};
            end
        end
        current_out = sum[23 : 8];
    end

    assign prediction = (current_out > 0);
    assign confidence = current_out;


    integer e;
    integer f;
    reg [ENTRY_W - 1 : 0] train_entry;

    wire [SET_W - 1 : 0] t_set = train_pc[2 + SET_W - 1 : 2];
    wire [TAG_BITS - 1 : 0] t_tag = train_pc[2 + SET_W + TAG_BITS - 1 : 2 + SET_W];
    wire [ENTRY_W - 1 : 0] t_idx0 = {t_set, 1'b0};
    wire [ENTRY_W - 1 : 0] t_idx1 = {t_set, 1'b1};
    wire t_hit0 = valid[t_idx0] && (tags[t_idx0] == t_tag);
    wire t_hit1 = valid[t_idx1] && (tags[t_idx1] == t_tag);
    wire t_inv0 = ~valid[t_idx0];
    wire t_inv1 = ~valid[t_idx1];
    wire [ENTRY_W - 1 : 0] t_alloc_entry =
        t_hit0 ? t_idx0 :
        t_hit1 ? t_idx1 :
        t_inv0 ? t_idx0 :
        t_inv1 ? t_idx1 :
        (lru_way[t_set] ? t_idx1 : t_idx0);

    always @(posedge clk) begin
        if (rst) begin
            for (e = 0; e < ENTRIES; e = e + 1) begin
                valid[e] <= 1'b0;
                tags[e] <= {TAG_BITS{1'b0}};
                biases[e] <= '0;
                for (f = 0; f < FEATURES; f = f + 1) begin
                    weights[e][f] <= rand_small();
                end
            end
            for (e = 0; e < NUM_SETS; e = e + 1) begin
                lru_way[e] <= 1'b0;
            end
        end
        else begin
            if (predict_en && cache_hit) begin
                lru_way[set_idx] <= hit0 ? 1'b1 : 1'b0;
            end

            if (train_en) begin
                train_entry = t_alloc_entry;

                if (!(t_hit0 || t_hit1)) begin
                    valid[train_entry] <= 1'b1;
                    tags[train_entry]  <= t_tag;
                end
                lru_way[t_set] <= (train_entry[0] == 1'b0) ? 1'b1 : 1'b0;

                begin : train_forward
                    reg signed [23 : 0] train_sum;
                    reg signed [15 : 0] train_out;
                    reg signed [15 : 0] target;
                    reg signed [15 : 0] error;
                    reg [2 : 0] lr;
                    reg signed [WEIGHT_BITS + 2 : 0] delta;

                    train_sum = {{(16 - WEIGHT_BITS){biases[train_entry][WEIGHT_BITS - 1]}}, biases[train_entry], 8'b0};
                    for (f = 0; f < FEATURES; f = f + 1) begin
                        if (train_features[f]) begin
                            train_sum = train_sum +
                                {{8{weights[train_entry][f][WEIGHT_BITS - 1]}},
                                 weights[train_entry][f], 8'b0};
                        end
                    end
                    train_out = train_sum[23 : 8];

                    target = actual_taken ? 16'sd128 : -16'sd128;
                    error  = target - train_out;

                    if (error > 16'sd64 || error < -16'sd64) begin
                        lr = 3'd4;
                    end
                    else if (error > 16'sd16 || error < -16'sd16) begin
                        lr = 3'd2;
                    end
                    else begin
                        lr = 3'd1;
                    end

                    for (f = 0; f < FEATURES; f = f + 1) begin
                        if (train_features[f]) begin
                            reg signed [WEIGHT_BITS + 2 : 0] new_w;
                            delta = ($signed(error[15 : 8]) * $signed({1'b0, lr})) >>> 5;
                            new_w = $signed({{3{weights[train_entry][f][WEIGHT_BITS - 1]}}, weights[train_entry][f]}) + delta;
                            if (new_w > 2**(WEIGHT_BITS - 1) - 1) begin
                                weights[train_entry][f] <= 2**(WEIGHT_BITS - 1) - 1;
                            end
                            else if (new_w < -2**(WEIGHT_BITS - 1)) begin
                                weights[train_entry][f] <= -2**(WEIGHT_BITS - 1);
                            end
                            else begin
                                weights[train_entry][f] <= new_w[WEIGHT_BITS - 1 : 0];
                            end
                        end
                    end

                    begin
                        reg signed [WEIGHT_BITS + 2 : 0] new_b;
                        delta = ($signed(error[15 : 8]) * $signed({1'b0, lr})) >>> 5;
                        new_b = $signed({{3{biases[train_entry][WEIGHT_BITS - 1]}}, biases[train_entry]}) + delta;
                        if (new_b > 2**(WEIGHT_BITS - 1) - 1) begin
                            biases[train_entry] <= 2**(WEIGHT_BITS - 1) - 1;
                        end
                        else if (new_b < -2**(WEIGHT_BITS - 1)) begin
                            biases[train_entry] <= -2**(WEIGHT_BITS - 1);
                        end
                        else begin
                            biases[train_entry] <= new_b[WEIGHT_BITS - 1 : 0];
                        end
                    end
                end
            end
        end
    end
endmodule