`include "define.v"
module dcache (
    input wire clk,
    input wire rst,

    input wire r_en,
    input wire [31:0] r_addr,
    output wire hit,
    output wire [31:0] r_data,

    input wire fill_en,
    input wire [31:0] fill_addr,

    input wire w_en,
    input wire [31:0] w_addr,
    input wire [31:0] w_data
);
    parameter SETS_BITS = 6;
    parameter WAYS = 2;
    parameter OFFSET_BITS = 5;
    parameter TAG_BITS = 32 - SETS_BITS - OFFSET_BITS;

    reg [TAG_BITS - 1:0] tag_array [0:(1 << SETS_BITS) - 1][0:WAYS - 1];
    reg valid_array [0:(1 << SETS_BITS) - 1][0:WAYS - 1];
    reg [31:0] data_array [0:(1 << SETS_BITS) - 1][0:WAYS - 1];
    reg lru_array [0:(1 << SETS_BITS) - 1];

    wire [1:0] offset = r_addr[1:0];
    wire [31:0] r_addr_1 = {r_addr[31:2], 2'b00};
    wire [31:0] r_addr_2 = r_addr_1 + 32'd4;
    wire need_extra_word = (offset != 2'b00);

    wire [TAG_BITS - 1:0] r_tag_1 = r_addr_1[31: OFFSET_BITS + SETS_BITS];
    wire [TAG_BITS - 1:0] r_tag_2 = r_addr_2[31: OFFSET_BITS + SETS_BITS];
    wire [SETS_BITS - 1:0] r_index_1 = r_addr_1[OFFSET_BITS + SETS_BITS - 1: OFFSET_BITS];
    wire [SETS_BITS - 1:0] r_index_2 = r_addr_2[OFFSET_BITS + SETS_BITS - 1: OFFSET_BITS];

    wire hit0_1 = valid_array[r_index_1][0] && (tag_array[r_index_1][0] == r_tag_1);
    wire hit0_2 = valid_array[r_index_2][0] && (tag_array[r_index_2][0] == r_tag_2);
    wire hit1_1 = valid_array[r_index_1][1] && (tag_array[r_index_1][1] == r_tag_1);
    wire hit1_2 = valid_array[r_index_2][1] && (tag_array[r_index_2][1] == r_tag_2);
    
    wire hit1 = hit0_1 || hit1_1;
    wire hit2 = hit0_2 || hit1_2;
    assign hit = need_extra_word ? (hit1 && hit2) : hit1;

    wire [31:0] data_word1 = hit1 ? (hit1_1 ? data_array[r_index_1][1] : 
                                                  data_array[r_index_1][0]) : 32'h0;
    wire [31:0] data_word2 = hit2 ? (hit1_2 ? data_array[r_index_2][1] : 
                                                  data_array[r_index_2][0]) : 32'h0;

    assign r_data = 
        !hit ? 32'd0 :
        !need_extra_word ? data_word1 :
        offset == 2'b01 ? {data_word2[7:0], data_word1[31:8]} :
        offset == 2'b10 ? {data_word2[15:0], data_word1[31:16]} :
        offset == 2'b11 ? {data_word2[23:0], data_word1[31:24]} :
        data_word1;

    wire [31:0] w_addr_aligned = {w_addr[31:2], 2'b00};
    wire [1:0] w_offset = w_addr[1:0];
    wire [31:0] w_addr_next = w_addr_aligned + 32'd4;
    wire [SETS_BITS - 1:0] w_index1 = w_addr_aligned[OFFSET_BITS + SETS_BITS - 1: OFFSET_BITS];
    wire [TAG_BITS - 1:0] w_tag1 = w_addr_aligned[31: OFFSET_BITS + SETS_BITS];
    wire [SETS_BITS - 1:0] w_index2 = w_addr_next[OFFSET_BITS + SETS_BITS - 1: OFFSET_BITS];
    wire [TAG_BITS - 1:0] w_tag2 = w_addr_next[31: OFFSET_BITS + SETS_BITS];
    
    wire w_hit0_1 = valid_array[w_index1][0] && (tag_array[w_index1][0] == w_tag1);
    wire w_hit0_2 = valid_array[w_index2][0] && (tag_array[w_index2][0] == w_tag2);
    wire w_hit1_1 = valid_array[w_index1][1] && (tag_array[w_index1][1] == w_tag1);
    wire w_hit1_2 = valid_array[w_index2][1] && (tag_array[w_index2][1] == w_tag2);
    wire w_hit1 = w_hit0_1 || w_hit1_1;
    wire w_hit2 = w_hit0_2 || w_hit1_2;

    wire [31:0] fill_addr_aligned = {fill_addr[31:2], 2'b00};
    wire [31:0] fill_addr_next = fill_addr_aligned + 32'd4;
    wire [SETS_BITS - 1:0] fill_index1 = fill_addr_aligned[OFFSET_BITS + SETS_BITS - 1: OFFSET_BITS];
    wire [TAG_BITS - 1:0] fill_tag1 = fill_addr_aligned[31: OFFSET_BITS + SETS_BITS];
    wire [SETS_BITS - 1:0] fill_index2 = fill_addr_next[OFFSET_BITS + SETS_BITS - 1: OFFSET_BITS];
    wire [TAG_BITS - 1:0] fill_tag2 = fill_addr_next[31: OFFSET_BITS + SETS_BITS];

    integer i, w;
    reg way;
    reg [31:0] data_tmp;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < (1 << SETS_BITS); i = i + 1) begin
                lru_array[i] <= 1'b0;
                for (w = 0; w < WAYS; w = w + 1) begin
                    valid_array[i][w] <= 1'b0;
                    tag_array[i][w] <= {TAG_BITS{1'b0}};
                    data_array[i][w] <= 32'h0;
                end
            end
        end
        else begin
            if (fill_en) begin
                way = lru_array[fill_index1];
                tag_array[fill_index1][way] <= fill_tag1;
                valid_array[fill_index1][way] <= 1'b1;
                lru_array[fill_index1] <= ~way;

                way = lru_array[fill_index2];
                tag_array[fill_index2][way] <= fill_tag2;
                valid_array[fill_index2][way] <= 1'b1;
                lru_array[fill_index2] <= ~way;
            end

            if (w_en) begin
                if (w_hit1) begin
                    if (w_hit1_1) begin
                        way = 1'b1;
                    end
                    else begin
                        way = 1'b0;
                    end
                    
                    tag_array[w_index1][way] <= w_tag1;
                    valid_array[w_index1][way] <= 1'b1;
                    data_tmp = 
                    w_offset == 2'b00 ? w_data :
                    w_offset == 2'b01 ? {w_data[7:0], data_array[w_index1][way][31:8]} :
                    w_offset == 2'b10 ? {w_data[15:0], data_array[w_index1][way][31:16]} :
                    w_offset == 2'b11 ? {w_data[23:0], data_array[w_index1][way][31:24]} :
                    data_array[w_index1][way];
                    data_array[w_index1][way] <= data_tmp;
                    lru_array[w_index1] <= way;
                end

                if(w_hit2) begin
                    if (w_hit1_2) begin
                        way = 1'b1;
                    end
                    else begin
                        way = 1'b0;
                    end
                    
                    tag_array[w_index2][way] <= w_tag2;
                    valid_array[w_index2][way] <= 1'b1;
                    data_tmp = 
                    w_offset == 2'b00 ? w_data :
                    w_offset == 2'b01 ? {w_data[7:0], data_array[w_index2][way][31:8]} :
                    w_offset == 2'b10 ? {w_data[15:0], data_array[w_index2][way][31:16]} :
                    w_offset == 2'b11 ? {w_data[23:0], data_array[w_index2][way][31:24]} :
                    data_array[w_index2][way];
                    data_array[w_index2][way] <= data_tmp;
                    lru_array[w_index2] <= way;
                end
            end
        end
    end
endmodule