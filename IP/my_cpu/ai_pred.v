`include "define.v"

module ai_pred (
    input wire clk,
    input wire rst,
    
    input wire predict_en,
    input wire [7:0] features, 
    output wire prediction,
    output wire signed [10:0] confidence, 
    
    input wire train_en,
    input wire [7:0] train_features,
    input wire actual_taken
);
    
    reg signed [5:0] weights [0:8]; 
    
    wire signed [10:0] pred_sum;
    
    wire signed [10:0] weighted_feat0 = features[0] ? {{5{weights[0][5]}}, weights[0]} : 11'sd0;
    wire signed [10:0] weighted_feat1 = features[1] ? {{5{weights[1][5]}}, weights[1]} : 11'sd0;
    wire signed [10:0] weighted_feat2 = features[2] ? {{5{weights[2][5]}}, weights[2]} : 11'sd0;
    wire signed [10:0] weighted_feat3 = features[3] ? {{5{weights[3][5]}}, weights[3]} : 11'sd0;
    wire signed [10:0] weighted_feat4 = features[4] ? {{5{weights[4][5]}}, weights[4]} : 11'sd0;
    wire signed [10:0] weighted_feat5 = features[5] ? {{5{weights[5][5]}}, weights[5]} : 11'sd0;
    wire signed [10:0] weighted_feat6 = features[6] ? {{5{weights[6][5]}}, weights[6]} : 11'sd0;
    wire signed [10:0] weighted_feat7 = features[7] ? {{5{weights[7][5]}}, weights[7]} : 11'sd0;
    wire signed [10:0] weighted_bias  = {{5{weights[8][5]}}, weights[8]};
    
    assign pred_sum = weighted_feat0 + weighted_feat1 + weighted_feat2 + 
                     weighted_feat3 + weighted_feat4 + weighted_feat5 +
                     weighted_feat6 + weighted_feat7 + weighted_bias;
    
    assign prediction = (pred_sum > 0);
    assign confidence = pred_sum;
    
    reg signed [10:0] train_sum_reg;
    reg train_pred_reg;
    
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            weights[0] <= -1;   // PC对齐
            weights[1] <= 0;    // PC变化
            weights[2] <= +2;   // 最近跳转
            weights[3] <= -1;   // 跳转变化
            weights[4] <= -6;   // 是BEQ（重要！）
            weights[5] <= +7;   // 是BNE（重要！）
            weights[6] <= -2;   // 向前跳转
            weights[7] <= +3;   // 短距离跳转
            weights[8] <= -4;   // 偏置（总体上不跳转更多）
        end
        else if (train_en) begin
            train_sum_reg = 
                (train_features[0] ? {{5{weights[0][5]}}, weights[0]} : 11'sd0) +
                (train_features[1] ? {{5{weights[1][5]}}, weights[1]} : 11'sd0) +
                (train_features[2] ? {{5{weights[2][5]}}, weights[2]} : 11'sd0) +
                (train_features[3] ? {{5{weights[3][5]}}, weights[3]} : 11'sd0) +
                (train_features[4] ? {{5{weights[4][5]}}, weights[4]} : 11'sd0) +
                (train_features[5] ? {{5{weights[5][5]}}, weights[5]} : 11'sd0) +
                (train_features[6] ? {{5{weights[6][5]}}, weights[6]} : 11'sd0) +
                (train_features[7] ? {{5{weights[7][5]}}, weights[7]} : 11'sd0) +
                {{5{weights[8][5]}}, weights[8]};
            
            train_pred_reg = (train_sum_reg > 0);
            
            if (train_pred_reg != actual_taken) begin
                for (i = 0; i < 8; i = i+1) begin
                    if (train_features[i]) begin
                        if (actual_taken) begin
                            if (weights[i] < 6'sd26)
                                weights[i] <= weights[i] + 6'sd2;
                        end else begin
                            if (weights[i] > -6'sd26)
                                weights[i] <= weights[i] - 6'sd2;
                        end
                    end
                end
                
                if (actual_taken) begin
                    if (weights[8] < 6'sd26)
                        weights[8] <= weights[8] + 6'sd2;
                end else begin
                    if (weights[8] > -6'sd26)
                        weights[8] <= weights[8] - 6'sd2;
                end
            end
        end
    end
    
endmodule