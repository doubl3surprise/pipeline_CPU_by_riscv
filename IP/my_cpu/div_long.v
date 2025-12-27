module div_long (
    input  wire [31:0] dividend,
    input  wire [31:0] divisor,
    input  wire        is_signed,
    output reg  [31:0] quot,
    output reg  [31:0] rem
);
    // combinational long division (unsigned algorithm) with sign handling
    integer i;
    reg [31:0] a;
    reg [31:0] b;
    reg a_neg, b_neg;
    reg [63:0] r;
    reg [31:0] q;

    always @(*) begin
        quot = 32'd0;
        rem  = 32'd0;
        a = 32'd0; b = 32'd0; a_neg = 1'b0; b_neg = 1'b0; r = 64'd0; q = 32'd0;
        if (divisor == 32'd0) begin
            quot = 32'hffffffff;
            rem  = dividend;
        end 
        else if (is_signed && (dividend == 32'h80000000) && (divisor == 32'hffffffff)) begin
            quot = 32'h80000000;
            rem  = 32'd0;
        end 
        else begin
            if (is_signed) begin
                a_neg = dividend[31];
                b_neg = divisor[31];
                a = a_neg ? (~dividend + 1) : dividend;
                b = b_neg ? (~divisor + 1) : divisor;
            end else begin
                a_neg = 1'b0; b_neg = 1'b0;
                a = dividend;
                b = divisor;
            end

            r = 64'd0;
            q = 32'd0;
            for (i = 31; i >= 0; i = i - 1) begin
                r = r << 1;
                r[0] = a[i];
                if (r[63:32] >= b) begin
                    r[63:32] = r[63:32] - b;
                    q[i] = 1'b1;
                end else begin
                    q[i] = 1'b0;
                end
            end

            if (is_signed && (a_neg ^ b_neg)) begin
                quot = ~q + 1;
            end else begin
                quot = q;
            end

            if (is_signed && a_neg) begin
                rem = ~r[63:32] + 1;
            end else begin
                rem = r[63:32];
            end
        end
    end
endmodule
