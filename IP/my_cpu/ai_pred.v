// ai_pred.v
// 兼容旧fetch_stage中使用的 ai_pred 接口：8-bit特征输入，输出prediction/confidence
// 这里实现为一个小型感知器（全局共享权重）
module ai_pred #(
    parameter integer FEAT = 8,
    parameter integer W_BITS = 8,
    parameter integer THRESH = 16
)(
    input  wire clk,
    input  wire rst,

    input  wire        predict_en,
    input  wire [FEAT - 1 : 0] features,
    output wire        prediction,
    output wire signed [10 : 0] confidence,

    input  wire        train_en,
    input  wire [FEAT - 1 : 0] train_features,
    input  wire        actual_taken
);
    reg signed [W_BITS - 1 : 0] w [0 : FEAT - 1];
    reg signed [W_BITS - 1 : 0] b;

    integer i;
    reg signed [15 : 0] sum;
    localparam signed [15 : 0] THRESH_S = THRESH[15 : 0];

    function automatic signed [W_BITS - 1 : 0] rand_small;
        integer r;
    begin
        r = $urandom_range(6) - 3;
        rand_small = $signed(r[W_BITS - 1 : 0]);
    end
    endfunction

    always @(*) begin
        reg signed [23 : 0] acc;
        // 24bit = (16-W_BITS) + W_BITS + 8
        acc = {{(16 - W_BITS){b[W_BITS - 1]}}, b, 8'b0};
        for (i = 0; i < FEAT; i = i + 1) begin
            if (features[i]) begin
                acc = acc + {{8{w[i][W_BITS - 1]}}, w[i], 8'b0};
            end
        end
        sum = acc[23 : 8];
    end

    assign prediction  = (sum > 0);
    assign confidence  = sum[10 : 0];

    always @(posedge clk) begin
        if (rst) begin
            b <= '0;
            for (i = 0; i < FEAT; i = i + 1) begin
                w[i] <= rand_small();
            end
        end
        else if (train_en) begin
            // 重算训练输出
            reg signed [23 : 0] acc;
            reg signed [15 : 0] out;
            reg signed [15 : 0] y;
            reg signed [W_BITS - 1 : 0] y_w;
            acc = {{(16 - W_BITS){b[W_BITS - 1]}}, b, 8'b0};
            for (i = 0; i < FEAT; i = i + 1) begin
                if (train_features[i]) begin
                    acc = acc + {{8{w[i][W_BITS - 1]}}, w[i], 8'b0};
                end
            end
            out = acc[23 : 8];
            y = actual_taken ? 16'sd1 : -16'sd1;
            y_w = actual_taken ? {{(W_BITS - 1){1'b0}}, 1'b1} : -{{(W_BITS - 1){1'b0}}, 1'b1};

            if (((out > 0) != actual_taken) || ($signed(out) < THRESH_S && $signed(out) > -THRESH_S)) begin
                b <= b + y_w;
                for (i = 0; i < FEAT; i = i + 1) begin
                    if (train_features[i]) begin
                        w[i] <= w[i] + y_w;
                    end
                end
            end
        end
    end
endmodule


