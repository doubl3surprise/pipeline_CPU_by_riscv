`include "define.v"
module csr_file (
    input  wire        clk,
    input  wire        rst,

    input  wire        csr_access, 
    input  wire [2:0]  csr_funct3, 
    input  wire [11:0] csr_addr,
    input  wire [31:0] csr_src,
    output wire [31:0] csr_rdata,

    input  wire        do_ecall,
    input  wire        do_mret,
    input  wire [31:0] cur_pc,
    output wire [31:0] mtvec_out,
    output wire [31:0] mepc_out,

    input  wire        instret_inc
);
    // machine CSRs (subset)
    reg [31:0] mstatus;   // 0x300
    reg [31:0] mie;       // 0x304
    reg [31:0] mtvec;     // 0x305
    reg [31:0] mscratch;  // 0x340
    reg [31:0] mepc;      // 0x341
    reg [31:0] mcause;    // 0x342
    reg [31:0] mip;       // 0x344

    reg [63:0] mcycle;
    reg [63:0] minstret;

    assign mtvec_out = mtvec;
    assign mepc_out  = mepc;

    reg [31:0] rdata_r;
    always @(*) begin
        rdata_r = 32'd0;
        case (csr_addr)
            12'h300: rdata_r = mstatus;
            12'h304: rdata_r = mie;
            12'h305: rdata_r = mtvec;
            12'h340: rdata_r = mscratch;
            12'h341: rdata_r = mepc;
            12'h342: rdata_r = mcause;
            12'h344: rdata_r = mip;
            12'hC00: rdata_r = mcycle[31:0];
            12'hC80: rdata_r = mcycle[63:32];
            12'hC02: rdata_r = minstret[31:0];
            12'hC82: rdata_r = minstret[63:32];
            default: rdata_r = 32'd0;
        endcase
    end
    assign csr_rdata = rdata_r;

    wire is_imm  = csr_funct3[2];  
    wire [2:0] op = csr_funct3[2] ? {1'b0, csr_funct3[1:0]} : csr_funct3;

    wire is_rw = (op == 3'b001);
    wire is_rs = (op == 3'b010);
    wire is_rc = (op == 3'b011);

    wire [31:0] old = csr_rdata;
    wire [31:0] new_rw = csr_src;
    wire [31:0] new_rs = old | csr_src;
    wire [31:0] new_rc = old & ~csr_src;

    wire write_enable =
        csr_access && (
            is_rw ||
            (is_rs && (csr_src != 32'd0)) ||
            (is_rc && (csr_src != 32'd0))
        );

    wire [31:0] write_data =
        is_rw ? new_rw :
        is_rs ? new_rs :
        is_rc ? new_rc : old;

    always @(posedge clk) begin
        if (rst) begin
            mstatus  <= 32'd0;
            mie      <= 32'd0;
            mtvec    <= 32'd0;
            mscratch <= 32'd0;
            mepc     <= 32'd0;
            mcause   <= 32'd0;
            mip      <= 32'd0;
            mcycle   <= 64'd0;
            minstret <= 64'd0;
        end else begin
            mcycle <= mcycle + 64'd1;
            if (instret_inc) minstret <= minstret + 64'd1;

            if (do_ecall) begin
                mepc   <= cur_pc;
                mcause <= 32'd11; 
                mstatus[7]   <= mstatus[3];
                mstatus[3]   <= 1'b0;
                mstatus[12:11] <= 2'b11;
            end else if (do_mret) begin
                mstatus[3]   <= mstatus[7];
                mstatus[7]   <= 1'b1;
                mstatus[12:11] <= 2'b00;
            end

            if (write_enable) begin
                case (csr_addr)
                    12'h300: mstatus  <= write_data;
                    12'h304: mie      <= write_data;
                    12'h305: mtvec    <= write_data;
                    12'h340: mscratch <= write_data;
                    12'h341: mepc     <= write_data;
                    12'h342: mcause   <= write_data;
                    12'h344: mip      <= write_data;
                    12'hC00: mcycle[31:0]   <= write_data;
                    12'hC80: mcycle[63:32]  <= write_data;
                    12'hC02: minstret[31:0] <= write_data;
                    12'hC82: minstret[63:32]<= write_data;
                    default: ;
                endcase
            end
        end
    end
endmodule


