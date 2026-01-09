module mlp_pred_pc #(
    parameter integer FEATURES = 32,
    parameter integer HIDDEN   = 8,
    parameter integer W_BITS   = 8,
    parameter integer THRESH   = 32 
)(
    input wire clk,
    input wire rst,

    input wire predict_en,
    input wire [31:0] pc,
    input wire [FEATURES - 1:0] predict_features,

    input wire train_en,
    input wire [31:0] train_pc,
    input wire [FEATURES - 1:0] train_features,
    input wire actual_taken,

    output wire prediction,
    output wire signed [15:0] confidence
);

    integer i, j;
    localparam signed [15:0] THRESH_S = THRESH[15:0];

    reg signed [W_BITS - 1:0] w1 [0:HIDDEN - 1][0:FEATURES - 1];
    reg signed [W_BITS - 1:0] b1 [0:HIDDEN - 1];
    reg signed [W_BITS - 1:0] w2 [0:HIDDEN - 1];
    reg signed [W_BITS - 1:0] b2;

    function automatic signed [W_BITS - 1:0] rand_small;
        integer r;
    begin
        r = $urandom_range(6) - 3;
        rand_small = $signed(r[W_BITS - 1:0]);
    end
    endfunction

    reg signed [15:0] h_sum [0:HIDDEN - 1];
    reg        h_act [0:HIDDEN - 1];
    always @(*) begin
        reg signed [23:0] acc;
        for (i = 0; i < HIDDEN; i = i + 1) begin
            acc = {{(16 - W_BITS){b1[i][W_BITS - 1]}}, b1[i], 8'b0};
            for (j = 0; j < FEATURES; j = j + 1) begin
                if (predict_features[j]) begin
                    acc = acc + {{8{w1[i][j][W_BITS - 1]}}, w1[i][j], 8'b0};
                end
            end
            h_sum[i] = acc[23:8];
            h_act[i] = (h_sum[i] > 0);
        end
    end

    reg signed [15:0] out_sum;
    always @(*) begin
        reg signed [23:0] acc;
        acc = {{(16 - W_BITS){b2[W_BITS - 1]}}, b2, 8'b0};
        for (i = 0; i < HIDDEN; i = i + 1) begin
            if (h_act[i]) begin
                acc = acc + {{8{w2[i][W_BITS - 1]}}, w2[i], 8'b0};
            end 
            else begin
                acc = acc - {{8{w2[i][W_BITS - 1]}}, w2[i], 8'b0};
            end
        end
        out_sum = acc[23:8];
    end

    assign prediction = (out_sum > 0);
    assign confidence = out_sum;

    reg signed [15:0] t_h_sum [0:HIDDEN - 1];
    reg t_h_act [0:HIDDEN - 1];
    reg signed [15:0] t_out;
    reg signed [23:0] acc;
    wire signed [W_BITS - 1:0] y_w =
        actual_taken ? {{(W_BITS - 1){1'b0}}, 1'b1} :
        -{{(W_BITS - 1){1'b0}}, 1'b1};

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < HIDDEN; i = i + 1) begin
                b1[i] <= '0;
                w2[i] <= rand_small();
                for (j = 0; j < FEATURES; j = j + 1) begin
                    w1[i][j] <= rand_small();
                end
            end
            b2 <= '0;
        end 
        else if (train_en) begin
            for (i = 0; i < HIDDEN; i = i + 1) begin
                acc = {{(16 - W_BITS){b1[i][W_BITS - 1]}}, b1[i], 8'b0};
                for (j = 0; j < FEATURES; j = j + 1) begin
                    if (train_features[j]) begin
                        acc = acc + {{8{w1[i][j][W_BITS - 1]}}, w1[i][j], 8'b0};
                    end
                end
                t_h_sum[i] = acc[23:8];
                t_h_act[i] = (t_h_sum[i] > 0);
            end

            acc = {{(16-W_BITS){b2[W_BITS - 1]}}, b2, 8'b0};
            for (i = 0; i < HIDDEN; i = i + 1) begin
                if (t_h_act[i]) begin
                    acc = acc + {{8{w2[i][W_BITS - 1]}}, w2[i], 8'b0};
                end
                else begin
                    acc = acc - {{8{w2[i][W_BITS - 1]}}, w2[i], 8'b0};
                end
            end
            t_out = acc[23:8];

            if (((t_out > 0) != actual_taken) || ($signed(t_out) < THRESH_S && $signed(t_out) > -THRESH_S)) begin
                for (i = 0; i < HIDDEN; i = i + 1) begin
                    if (t_h_act[i]) begin
                        w2[i] <= w2[i] + y_w;
                    end
                    else begin
                        w2[i] <= w2[i] - y_w;
                    end
                end
                b2 <= b2 + y_w;

                for (i = 0; i < HIDDEN; i = i + 1) begin
                    b1[i] <= b1[i] + y_w;
                    for (j = 0; j < FEATURES; j = j + 1) begin
                        if (train_features[j]) begin
                            w1[i][j] <= w1[i][j] + y_w;
                        end
                    end
                end
            end
        end
    end
endmodule


