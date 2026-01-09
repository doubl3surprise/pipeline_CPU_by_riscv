module path_history_track_pred_pc #(
    parameter PATH_LEN = 4,
    parameter TABLE_SIZE = 512,
    parameter INDEX_BITS = 9,
    parameter TAG_BITS = 12,
    parameter PRED_BITS = 2
)(
    input wire clk,
    input wire rst,
    
    // predict interface
    input wire predict_en,
    input wire [31:0] pc,
    input wire [PATH_LEN - 1:0][31:0] path_history,
    
    // train interface
    input wire train_en,
    input wire [31:0] train_pc,
    input wire [PATH_LEN - 1:0][31:0] train_path,
    input wire actual_taken,
    
    // prediction output
    output wire prediction,
    output wire [1:0] confidence
);
    
    // hash path function
    function [INDEX_BITS - 1:0] path_hash;
        input [PATH_LEN - 1:0][31:0] path;
        reg [INDEX_BITS - 1:0] hash;
        integer i;
    begin
        hash = {INDEX_BITS{1'b0}};
        for (i = 0; i < PATH_LEN; i = i + 1) begin
            case (i)
                0: hash = hash ^ path[i][INDEX_BITS - 1:0];
                1: hash = hash ^ {path[i][INDEX_BITS - 2:0], path[i][INDEX_BITS - 1]};
                2: hash = hash ^ {path[i][INDEX_BITS - 3:0], path[i][INDEX_BITS - 1:INDEX_BITS - 2]};
                3: hash = hash ^ {path[i][INDEX_BITS - 4:0], path[i][INDEX_BITS - 1:INDEX_BITS - 3]};
                
                default: hash = hash ^ path[i][INDEX_BITS - 1:0];
            endcase
        end
        path_hash = hash;
    end
    endfunction
    
    // compute tag function
    function [TAG_BITS - 1:0] tage_hash;
        input [31:0] pc;
        input [PATH_LEN - 1:0][31:0] path;
        reg [TAG_BITS - 1:0] tag;
    begin
        tag = pc[15:4];
        tag = tag ^
            {{(TAG_BITS - 8){1'b0}}, path[0][7:0]} ^
            {{(TAG_BITS - 8){1'b0}}, path[1][15:8]} ^
            {{(TAG_BITS - 8){1'b0}}, path[2][23:16]};
        tage_hash = tag;
    end
    endfunction
    
    // array for prediction table
    reg [PRED_BITS - 1:0] pred_table [0:TABLE_SIZE - 1];
    reg [TAG_BITS - 1:0] tag_table [0:TABLE_SIZE - 1];
    reg valid_table[0:TABLE_SIZE - 1];
    
    // prediction logic
    wire [INDEX_BITS - 1:0] pred_index;
    wire [TAG_BITS - 1:0]   pred_tag;
    wire pred_hit;
    wire [PRED_BITS - 1:0]  pred_counter;
    
    // pred idx and tag
    assign pred_index = path_hash(path_history);
    assign pred_tag = tage_hash(pc, path_history);
    
    // check hit
    assign pred_hit = valid_table[pred_index] && (tag_table[pred_index] == pred_tag);
    assign pred_counter = pred_table[pred_index];
    
    // prediction output
    assign prediction = pred_hit ? pred_counter[PRED_BITS - 1] : 1'b0;
    
    // compute confidence
    assign confidence = 
        !pred_hit ? 2'b00 : 
        (pred_counter == 2'b11) ? 2'b11 :
        (pred_counter == 2'b00) ? 2'b11 :
        (pred_counter == 2'b10) ? 2'b10 :
        (pred_counter == 2'b01) ? 2'b10 :
        2'b01; 

    // train idx and tag
    wire [INDEX_BITS - 1:0] train_index_w = path_hash(train_path);
    wire [TAG_BITS - 1:0] train_tag_w = tage_hash(train_pc, train_path);
    
    // training logic
    always @(posedge clk) begin
        if (rst) begin
            for (integer i = 0; i < TABLE_SIZE; i = i + 1) begin
                valid_table[i] <= 1'b0;
                tag_table[i] <= {TAG_BITS{1'b0}};
                pred_table[i] <= 2'b01;
            end
        end
        else if (train_en) begin
            if (valid_table[train_index_w] && tag_table[train_index_w] == train_tag_w) begin
                if (actual_taken) begin
                    if (pred_table[train_index_w] != 2'b11) begin
                        pred_table[train_index_w] <= pred_table[train_index_w] + 1'b1;
                    end
                end 
                else begin
                    if (pred_table[train_index_w] != 2'b00) begin
                        pred_table[train_index_w] <= pred_table[train_index_w] - 1'b1;
                    end
                end
            end
            else begin
                valid_table[train_index_w] <= 1'b1;
                tag_table[train_index_w] <= train_tag_w;
                if (actual_taken) begin
                    pred_table[train_index_w] <= 2'b10;
                end 
                else begin
                    pred_table[train_index_w] <= 2'b01;
                end
            end
        end
    end
endmodule