`include "define.v"
module icache(
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
    parameter OFFSET_BITS = 2;
    parameter TAG_BITS = 32 - SETS_BITS - OFFSET_BITS;

    reg [TAG_BITS-1:0] tag_array [0:(1<<SETS_BITS)-1][0:WAYS-1];
    reg valid_array [0:(1<<SETS_BITS)-1][0:WAYS-1];
    reg [31:0] data_array [0:(1<<SETS_BITS)-1][0:WAYS-1];
    reg lru_array [0:(1<<SETS_BITS)-1];

    wire [SETS_BITS-1:0] r_index = r_addr[OFFSET_BITS + SETS_BITS - 1: OFFSET_BITS];
    wire [TAG_BITS-1:0] r_tag = r_addr[31: OFFSET_BITS + SETS_BITS];

    wire hit0 = valid_array[r_index][0] && (tag_array[r_index][0] == r_tag);
    wire hit1 = valid_array[r_index][1] && (tag_array[r_index][1] == r_tag);
    assign hit = hit0 || hit1;
    
    assign r_data = hit0 ? data_array[r_index][0] :
                    hit1 ? data_array[r_index][1] : 
                    32'd0;
    
    wire [SETS_BITS-1:0] fill_index = fill_addr[OFFSET_BITS + SETS_BITS - 1: OFFSET_BITS];
    wire [TAG_BITS-1:0] fill_tag = fill_addr[31: OFFSET_BITS + SETS_BITS];

    wire [SETS_BITS-1:0] w_index = w_addr[OFFSET_BITS + SETS_BITS - 1: OFFSET_BITS];
    wire [TAG_BITS-1:0] w_tag = w_addr[31: OFFSET_BITS + SETS_BITS];

    integer i, w;
    reg way;
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < (1<<SETS_BITS); i = i + 1) begin
                lru_array[i] <= 1'b0;
                for (w = 0; w < WAYS; w = w + 1) begin
                    valid_array[i][w] <= 1'b0;
                    tag_array[i][w] <= {TAG_BITS{1'b0}};
                end
            end
        end
        else begin
            if (fill_en) begin
                way = lru_array[fill_index];
                tag_array[fill_index][way] <= fill_tag;
                valid_array[fill_index][way] <= 1'b1;
                lru_array[fill_index] <= ~way;
            end

            if (w_en) begin
                way = lru_array[w_index];
                tag_array[w_index][way] <= w_tag;
                valid_array[w_index][way] <= 1'b1;
                data_array[w_index][way] <= w_data;
                lru_array[w_index] <= ~way;
            end
        end
    end

endmodule
