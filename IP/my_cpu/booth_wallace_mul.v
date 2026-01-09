module booth_wallace_mul (
    input  wire [31 : 0] a,
    input  wire [31 : 0] b,
    input  wire        is_a_sign,
    input  wire        is_b_sign,
    output wire [63 : 0] product
);
    // radix-4 Booth 
    wire [63 : 0] a_ext = is_a_sign ? {{32{a[31]}}, a} : {32'd0, a};
    wire [63 : 0] b_ext = is_b_sign ? {{32{b[31]}}, b} : {32'd0, b};
    reg signed [127 : 0] pp [0 : 15];
    integer i;
    reg [2 : 0] slice;
    reg signed [127 : 0] m96;

    always @(*) begin
        m96 = {{64{a_ext[63]}}, a_ext};

        for (i = 0; i < 16; i = i + 1) begin
            if (i == 0) begin
                slice = {b[1], b[0], 1'b0};
            end
            else begin
                slice = {b[2 * i + 1], b[2 * i], b[2 * i - 1]};
            end

            case (slice)
                3'b000, 3'b111: pp[i] = 128'sd0; 
                3'b001, 3'b010: pp[i] = m96 << (2*i);
                3'b011:         pp[i] = (m96 << 1) << (2*i);
                3'b100:         pp[i] = -((m96 << 1) << (2*i));
                3'b101, 3'b110: pp[i] = -(m96 << (2*i));
                default: pp[i] = 128'sd0;
            endcase
        end
    end

    // Wallace-tree with carry-save adders (CSA)
    reg signed [127 : 0] layer [0 : 31];
    reg signed [127 : 0] next_layer [0 : 31];
    reg signed [127 : 0] final_sum;
    integer n;
    integer j;

    always @(*) begin
        for (i = 0; i < 16; i = i + 1) begin
            layer[i] = pp[i];
        end
        n = 16;

        while (n > 2) begin
            integer k;
            k = 0;
            j = 0;
            while (j + 2 < n) begin
                reg signed [127:0] a3, b3, c3;
                reg signed [127:0] sum3;
                reg signed [127:0] carry3;
                a3 = layer[j]; b3 = layer[j + 1]; c3 = layer[j + 2];
                sum3 = a3 ^ b3 ^ c3; 
                carry3 = (a3 & b3) | (b3 & c3) | (a3 & c3);
                next_layer[k] = sum3;
                k = k + 1;
                next_layer[k] = carry3 << 1;
                k = k + 1;
                j = j + 3;
            end
            while (j < n) begin
                next_layer[k] = layer[j];
                k = k + 1;
                j = j + 1;
            end
            for (j = 0; j < k; j = j + 1) begin
                layer[j] = next_layer[j];
            end
            n = k;
        end

        if (n == 0) begin
            final_sum = 128'sd0;
        end
        else if (n == 1) begin
            final_sum = layer[0];
        end
        else begin
            final_sum = layer[0] + layer[1];
        end
    end

    assign product = final_sum[63 : 0];
endmodule
