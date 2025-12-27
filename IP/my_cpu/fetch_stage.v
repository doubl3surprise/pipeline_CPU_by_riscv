`include "define.v"
module fetch_stage # (
    parameter N = 12
) (
    input wire clk,
    input wire rst,
    
    // touch signal
    output f_allow_in,
    input d_allow_in,
    output f_to_d_valid,
    
    // pc signal
    input wire [31:0] F_pc,

    // fetch siganl
    output wire [6:0] f_opcode,
    output wire [4:0] f_rd,
    output wire [4:0] f_rs1,
    output wire [4:0] f_rs2,
    output wire [9:0] f_funct,
    output wire [31:0] f_imm,
    output wire [2:0] f_instr_type,
    output wire [31:0] f_default_pc,

    // branch pred signal
    output wire f_is_jump_instr,
    output wire f_pred_taken,
    output reg [N - 1:0] f_pred_history,

    input wire e_valid,
    input wire e_is_jump_instr,
    input wire fact_taken,
    input wire fact_success,
    input reg [N - 1:0] train_history,
    input wire [31:0] fact_pc,

    // update pc value
    output reg [31:0] nw_pc,

    // signal for cpu interface
    output wire [31:0] f_instr
);
    // DPI import
    import "DPI-C" function int dpi_mem_read (input int addr, input int len);

    // fetch function
    wire [2:0] func3;
    wire [6:0] func7;
    wire [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
    wire is_imm_i, is_imm_s, is_imm_b, is_imm_u, is_imm_j;
    wire is_funct_r, is_funct_i, is_funct_s, is_funct_b;
    assign f_instr = dpi_mem_read(F_pc, 4);
    assign func3 = f_instr[14:12];
    assign func7 = f_instr[31:25];
    assign f_opcode = f_instr[6:0];
    assign f_rd = f_instr[11:7];
    assign f_rs1 = f_instr[19:15];
    assign f_rs2 = f_instr[24:20];

    assign imm_i = {{20{f_instr[31]}}, f_instr[31:20]};
    assign imm_s = {{20{f_instr[31]}}, f_instr[31:25], f_instr[11:7]};
    assign imm_b = {{19{f_instr[31]}}, f_instr[31], f_instr[7], f_instr[30:25], f_instr[11:8], 1'b0};
    assign imm_u = {f_instr[31:12], 12'b0};
    assign imm_j = {{12{f_instr[31]}}, f_instr[19:12], f_instr[20], f_instr[30:21], 1'b0};

	assign f_instr_type = 
		(f_opcode == `OP_B)    ? `TYPEB :
		(f_opcode == `OP_S)    ? `TYPES :
		(f_opcode == `OP_JAL)  ? `TYPEJ :
		(f_opcode == `OP_JALR) ? `TYPEI :
		(f_opcode == `OP_R)    ? `TYPER :
		(f_opcode == `OP_IMM)  ? `TYPEI :
		(f_opcode == `OP_LOAD) ? `TYPEI :
		((f_opcode == `OP_LUI) || (f_opcode == `OP_AUIPC)) ? `TYPEU :
		3'd0;

    assign is_funct_r = (f_instr_type == `TYPER);
    assign is_funct_i = (f_instr_type == `TYPEI);
    assign is_funct_s = (f_instr_type == `TYPES);
    assign is_funct_b = (f_instr_type == `TYPEB);

	assign f_funct = is_funct_r ? {func7, func3} :
        (is_funct_i || is_funct_s || is_funct_b) ?
            (f_opcode == `OP_IMM) && (func3 == 3'b001 || func3 == 3'b101) ? {func7, func3} :
            {7'b0, func3} :
            10'd0;

    assign is_imm_i = (f_instr_type == `TYPEI);
	assign is_imm_s = (f_instr_type == `TYPES);
	assign is_imm_b = (f_instr_type == `TYPEB);
	assign is_imm_u = (f_instr_type == `TYPEU);
	assign is_imm_j = (f_instr_type == `TYPEJ);
	assign f_imm = ({32{is_imm_i}} & imm_i) |
		({32{is_imm_s}} & imm_s) |
		({32{is_imm_b}} & imm_b) |
		({32{is_imm_u}} & imm_u) |
		({32{is_imm_j}} & imm_j);

    // pipeline control
    reg f_valid;
    wire f_ready_go = 1;
    always@ (posedge clk) begin
        if(rst) f_valid <= 1'b1;
        else if(f_allow_in) f_valid <= 1'b1;
    end
    assign f_to_d_valid = f_valid && f_ready_go;
    assign f_allow_in = ~f_valid || (f_ready_go && d_allow_in);

    assign f_default_pc = F_pc + 4;

    // branch predictor
    wire is_jump_instr;
    wire [31:0] pred_jump_pc;
    reg [N - 1:0] ghr;
    reg [1:0] pht [(1 << N) - 1:0];
    reg [31:0] tat [(1 << N) - 1:0];
    assign is_jump_instr = (f_instr_type == `TYPEB) || (f_instr_type == `TYPEJ)
        || (f_opcode == `OP_JALR);

    assign f_is_jump_instr = is_jump_instr;

    always@ (posedge clk) begin
        if (rst) begin
            ghr <= 0;
            for(integer i = 0; i < (1 << N) - 1; i = i + 1) begin
                pht[i] = 2'b01;
                tat[i] = 32'h80000000;
            end
        end
        else begin
            if (e_is_jump_instr && !fact_success) begin
                ghr <= {train_history[N - 2:0], fact_taken};
            end
            else if (is_jump_instr) begin
                ghr <= {ghr[N - 2:0], f_pred_taken};
            end

            if (e_is_jump_instr) begin
                if (fact_taken) begin
                    pht[train_history ^ fact_pc[N - 1:0]] <= 
                        (pht[train_history ^ fact_pc[N - 1:0]] == 2'b11) 
                        ? 2'b11 : pht[train_history ^ fact_pc[N - 1:0]] + 1'b1;
                end
                else begin
                    pht[train_history ^ fact_pc[N - 1:0]] <= 
                        (pht[train_history ^ fact_pc[N - 1:0]] == 2'b00) 
                        ? 2'b00 : pht[train_history ^ fact_pc[N - 1:0]] - 1'b1;
                end
                tat[fact_pc[N - 1:0]] <= fact_pc;
            end
        end 
    end

    assign f_pred_taken = pht[F_pc[N - 1:0] ^ ghr][1];
    assign f_pred_history = ghr;

    assign pred_jump_pc = (f_instr_type == `TYPEB && f_imm >= 32'h80000000 && f_imm <= 32'h87fffff) ? (F_pc + f_imm) & -1
        : (f_instr_type == `TYPEJ && ((F_pc + f_imm) & -1) >= 32'h80000000 && ((F_pc + f_imm) & -1) <= 32'h87fffff) ? (F_pc + f_imm) & -1
        : (f_opcode == `OP_JALR && f_imm >= tat[F_pc[N - 1:0]] && f_imm <= tat[F_pc[N - 1:0]]) ? tat[F_pc[N - 1:0]] : 32'h80000000;

    always@ (posedge clk) begin
        if (rst) begin
            nw_pc <= 32'h80000000;
        end
        else if (!fact_success && e_is_jump_instr && e_valid) begin
            nw_pc <= fact_pc;
        end
        else if (f_allow_in) begin
            nw_pc <= (is_jump_instr && f_pred_taken) ? pred_jump_pc : f_default_pc;
        end
    end
endmodule
