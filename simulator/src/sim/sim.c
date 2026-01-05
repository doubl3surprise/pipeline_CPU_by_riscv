#include <common.h>
#include <defs.h>
#include <debug.h>
#include <sys/types.h>
#include <verilated.h>
#include <verilated_vcd_c.h>
#include <npc.h>



#include <simulator_state.h>
#include <common.h>
#include <defs.h>

extern CPU_state  cpu;
extern SIMState  sim_state;
uint64_t          g_nr_guest_inst = 0;
static uint64_t   g_timer = 0; // unit: us
static bool       g_print_step = false;
#define MAX_INST_TO_PRINT 100


static TOP_NAME dut;  			    //CPU
static VerilatedVcdC *m_trace;  //仿真波形
static word_t sim_time = 0;			//时间
static word_t clk_count = 0;

// PC prediction statistics (for control-flow instructions)
static uint64_t g_pc_pred_total = 0;
static uint64_t g_pc_pred_correct = 0;
// Split statistics
static uint64_t g_pc_pred_b_total = 0;
static uint64_t g_pc_pred_b_correct = 0;
// Split B-type into forward/backward (roughly if vs loop)
static uint64_t g_pc_pred_b_fwd_total = 0;
static uint64_t g_pc_pred_b_fwd_correct = 0;
static uint64_t g_pc_pred_b_bwd_total = 0;
static uint64_t g_pc_pred_b_bwd_correct = 0;
static uint64_t g_pc_pred_jalr_total = 0; // includes RET
static uint64_t g_pc_pred_jalr_correct = 0;

// When enabled, reaching the step limit (cpu_exec(n)) will stop the simulation with SIM_QUIT,
// so statistics are printed (useful for fixed-window benchmarks in batch mode).
static int g_quit_on_limit = 0;
void sim_set_quit_on_limit(int en) { g_quit_on_limit = en ? 1 : 0; }

// Periodic PC prediction reporting
static uint64_t g_pcpred_report_interval = 0; // 0 means disabled
void sim_set_pcpred_report_interval(uint64_t interval) { g_pcpred_report_interval = interval; }

// Snapshot for windowed reporting
static uint64_t g_last_report_guest_inst = 0;
static uint64_t g_last_report_cf_total = 0;
static uint64_t g_last_report_cf_correct = 0;

static void pcpred_maybe_report_progress() {
  if (g_pcpred_report_interval == 0) return;
  if (g_nr_guest_inst == 0) return;
  if (g_nr_guest_inst % g_pcpred_report_interval != 0) return;

  const uint64_t cf_total = g_pc_pred_total;
  const uint64_t cf_correct = g_pc_pred_correct;
  const uint64_t cf_wrong = (cf_total >= cf_correct) ? (cf_total - cf_correct) : 0;

  const uint64_t win_inst = g_nr_guest_inst - g_last_report_guest_inst;
  const uint64_t win_cf_total = cf_total - g_last_report_cf_total;
  const uint64_t win_cf_correct = cf_correct - g_last_report_cf_correct;
  const uint64_t win_cf_wrong = (win_cf_total >= win_cf_correct) ? (win_cf_total - win_cf_correct) : 0;

  double rate = 0.0, win_rate = 0.0;
  if (cf_total > 0) rate = (double)cf_correct * 100.0 / (double)cf_total;
  if (win_cf_total > 0) win_rate = (double)win_cf_correct * 100.0 / (double)win_cf_total;

  // A single, parse-friendly progress line for scripts.
  // Meaning:
  // - commit: total committed instructions so far
  // - win_inst: instructions since last report
  // - cf_total/cf_correct/cf_wrong: cumulative control-flow prediction stats
  // - cf_rate: cumulative success rate
  // - win_cf_* / win_cf_rate: window success rate for the last interval
  Log("[PCPRED] commit=%" PRIu64 " win_inst=%" PRIu64
      " cf_total=%" PRIu64 " cf_correct=%" PRIu64 " cf_wrong=%" PRIu64 " cf_rate=%.2f%%"
      " win_cf_total=%" PRIu64 " win_cf_correct=%" PRIu64 " win_cf_wrong=%" PRIu64 " win_cf_rate=%.2f%%",
      g_nr_guest_inst, win_inst,
      cf_total, cf_correct, cf_wrong, rate,
      win_cf_total, win_cf_correct, win_cf_wrong, win_rate);

  g_last_report_guest_inst = g_nr_guest_inst;
  g_last_report_cf_total = cf_total;
  g_last_report_cf_correct = cf_correct;
}

void npc_get_clk_count(){
  printf("你的处理器运行了%u个clk\n", clk_count);
}


void npc_open_simulation(){
  Verilated::traceEverOn(true);
  m_trace= new VerilatedVcdC;
  dut.trace(m_trace, 5);
  m_trace->open("waveform.vcd");
  Log("NPC open simulation");
}
void npc_close_simulation(){
  IFDEF(CONFIG_NPC_OPEN_SIM, 	m_trace->close());
  IFDEF(CONFIG_NPC_OPEN_SIM, Log("NPC close simulation"));
}


extern uint32_t * reg_ptr;
void update_cpu_state(){
  cpu.pc = dut.cur_pc;
  memcpy(&cpu.gpr[0], reg_ptr, 4 * 32);
}
void npc_single_cycle() {
  dut.clk = 0;  
  // printf("make_clk = 0, single_cycle clk = %d, rst = %d, cur_pc = %x, commit = %d, instr = %b, commit_pc = %x, commit_pre_pc = %x\n", dut.clk, dut.rst, dut.cur_pc, dut.commit, dut.instr, dut.commit_pc, dut.commit_pre_pc);
  dut.eval();   
  IFDEF(CONFIG_NPC_OPEN_SIM,   m_trace->dump(sim_time++));
  dut.clk = 1;  
  // printf("make_clk = 1, single_cycle clk = %d, rst = %d, cur_pc = %x, commit = %d, instr = %b, commit_pc = %x, commit_pre_pc = %x\n", dut.clk, dut.rst, dut.cur_pc, dut.commit, dut.instr, dut.commit_pc, dut.commit_pre_pc);
  dut.eval();
  IFDEF(CONFIG_NPC_OPEN_SIM,   m_trace->dump(sim_time++));
  clk_count++;
  update_cpu_state();
}
void npc_reset(int n) {
  dut.rst = 1;
  while (n -- > 0) npc_single_cycle();
  dut.rst = 0;
}

void npc_init() {
  IFDEF(CONFIG_NPC_OPEN_SIM, npc_open_simulation());  
  npc_reset(1);
  if(cpu.pc != 0x80000000){
    npc_close_simulation();
    printf("当前cpu.pc为%d\n", cpu.pc);
    Assert(cpu.pc== 0x80000000, "npc初始化之后, cpu.pc的值应该为0x80000000");
  }
}




word_t commit_pre_pc = 0; 
//si 1执行一条指令就确定是一次commit, 而不是多次clk
void execute(uint64_t n){
  for (   ;n > 0; n --) {
    if (sim_state.state != SIM_RUNNING) {
      if(sim_state.state == SIM_END) printf("下一条要执行的指令是----![信息待添加]\n");
      break; 
    }
    int cnt = 0;
    // printf("start clk = %d, rst = %d, cur_pc = %x, commit = %d, instr = %x, default_pc = %x\n", dut.clk, dut.rst, dut.cur_pc, dut.commit, dut.instr, dut.commit_pre_pc);
    while(dut.commit != 1){
      npc_single_cycle();
      // printf("rotate clk = %d, rst = %d, cur_pc = %x, commit = %d, instr = %x, default_pc = %x\n", dut.clk, dut.rst, dut.cur_pc, dut.commit, dut.instr, dut.commit_pre_pc);
      if(++cnt > 20) break;
    }
    word_t commit_pc = dut.commit_pc;
    commit_pre_pc = dut.commit_pre_pc;
    word_t commit_pred_pc = dut.commit_pred_pc;
    uint32_t commit_instr = dut.instr;
    g_nr_guest_inst++;

    // count prediction accuracy for control-flow instructions (B/J/JALR)
    uint32_t opcode = commit_instr & 0x7f;
    if (opcode == 0x63 || opcode == 0x6f || opcode == 0x67) {
      g_pc_pred_total++;
      if (commit_pred_pc == commit_pre_pc) g_pc_pred_correct++;
    }
    // split: B-type (0x63) and JALR/RET (0x67)
    if (opcode == 0x63) {
      g_pc_pred_b_total++;
      if (commit_pred_pc == commit_pre_pc) g_pc_pred_b_correct++;

      // Further split B-type: forward vs backward by signed branch offset (imm_b)
      // imm_b encoding (13-bit signed, bit0=0):
      // imm[12]   = inst[31]
      // imm[10:5] = inst[30:25]
      // imm[4:1]  = inst[11:8]
      // imm[11]   = inst[7]
      // imm[0]    = 0
      int32_t imm_b = 0;
      imm_b |= ((commit_instr >> 31) & 0x1) << 12;
      imm_b |= ((commit_instr >> 25) & 0x3f) << 5;
      imm_b |= ((commit_instr >> 8) & 0xf) << 1;
      imm_b |= ((commit_instr >> 7) & 0x1) << 11;
      // sign-extend 13-bit
      imm_b = (imm_b << 19) >> 19;

      const bool is_backward = (imm_b < 0);
      if (is_backward) {
        g_pc_pred_b_bwd_total++;
        if (commit_pred_pc == commit_pre_pc) g_pc_pred_b_bwd_correct++;
      } else {
        g_pc_pred_b_fwd_total++;
        if (commit_pred_pc == commit_pre_pc) g_pc_pred_b_fwd_correct++;
      }
    } else if (opcode == 0x67) {
      g_pc_pred_jalr_total++;
      if (commit_pred_pc == commit_pre_pc) g_pc_pred_jalr_correct++;
    }

    npc_single_cycle();                             //再执行一次,该指令执行完毕.   
    update_cpu_state();
    IFDEF(CONFIG_ITRACE,   instr_trace(commit_pc));
    IFDEF(CONFIG_DIFFTEST, difftest_step(commit_pc, commit_pc + 4));  

    // Periodic progress report (for showing accuracy evolution)
    pcpred_maybe_report_progress();

    // Stop at the requested commit window in batch mode.
    // Here, n==1 means this is the last iteration (because the for-loop will decrement n after this body).
    if (g_quit_on_limit && n == 1 && sim_state.state == SIM_RUNNING) {
      set_sim_state(SIM_QUIT, commit_pc, 0);
      break;
    }
  }
}


void statistic() {
  npc_close_simulation();
  #define NUMBERIC_FMT MUXDEF(CONFIG_TARGET_AM, "%", "%'") PRIu64
  Log("host time spent = " NUMBERIC_FMT " us", g_timer);
  Log("total guest instructions = " NUMBERIC_FMT, g_nr_guest_inst);
  if (g_timer > 0) {
    Log("simulation frequency = " NUMBERIC_FMT " inst/s", g_nr_guest_inst * 1000000 / g_timer);
  }else{
    Log("Finish running in less than 1 us and can not calculate the simulation frequency");
  }

  Log("=== PC Prediction Statistics ===");
  Log("[INFO] Total control-flow insts: %" PRIu64, g_pc_pred_total);
  Log("[INFO] Correct predictions:      %" PRIu64, g_pc_pred_correct);
  Log("[INFO] Mispredictions:           %" PRIu64, g_pc_pred_total - g_pc_pred_correct);
  if (g_pc_pred_total > 0) {
    double rate = (double)g_pc_pred_correct * 100.0 / (double)g_pc_pred_total;
    Log("[INFO] Prediction success rate:  %.2f%%", rate);
  } else {
    Log("[INFO] Prediction success rate:  N/A (no control-flow inst executed)");
  }

  Log("=== PC Prediction Split (requested) ===");
  Log("[INFO] B-type (opcode 0x63): total=%" PRIu64 ", correct=%" PRIu64 ", wrong=%" PRIu64,
      g_pc_pred_b_total, g_pc_pred_b_correct, g_pc_pred_b_total - g_pc_pred_b_correct);
  Log("[INFO] B-forward (imm_b>=0): total=%" PRIu64 ", correct=%" PRIu64 ", wrong=%" PRIu64,
      g_pc_pred_b_fwd_total, g_pc_pred_b_fwd_correct, g_pc_pred_b_fwd_total - g_pc_pred_b_fwd_correct);
  Log("[INFO] B-backward (imm_b<0): total=%" PRIu64 ", correct=%" PRIu64 ", wrong=%" PRIu64,
      g_pc_pred_b_bwd_total, g_pc_pred_b_bwd_correct, g_pc_pred_b_bwd_total - g_pc_pred_b_bwd_correct);
  if (g_pc_pred_b_total > 0) {
    double rate_b = (double)g_pc_pred_b_correct * 100.0 / (double)g_pc_pred_b_total;
    Log("[INFO] B-type success rate:      %.2f%%", rate_b);
  } else {
    Log("[INFO] B-type success rate:      N/A");
  }
  if (g_pc_pred_b_fwd_total > 0) {
    double rate_bf = (double)g_pc_pred_b_fwd_correct * 100.0 / (double)g_pc_pred_b_fwd_total;
    Log("[INFO] B-forward success rate:   %.2f%%", rate_bf);
  } else {
    Log("[INFO] B-forward success rate:   N/A");
  }
  if (g_pc_pred_b_bwd_total > 0) {
    double rate_bb = (double)g_pc_pred_b_bwd_correct * 100.0 / (double)g_pc_pred_b_bwd_total;
    Log("[INFO] B-backward success rate:  %.2f%%", rate_bb);
  } else {
    Log("[INFO] B-backward success rate:  N/A");
  }

  Log("[INFO] JALR/RET (opcode 0x67): total=%" PRIu64 ", correct=%" PRIu64 ", wrong=%" PRIu64,
      g_pc_pred_jalr_total, g_pc_pred_jalr_correct, g_pc_pred_jalr_total - g_pc_pred_jalr_correct);
  if (g_pc_pred_jalr_total > 0) {
    double rate_jalr = (double)g_pc_pred_jalr_correct * 100.0 / (double)g_pc_pred_jalr_total;
    Log("[INFO] JALR/RET success rate:    %.2f%%", rate_jalr);
  } else {
    Log("[INFO] JALR/RET success rate:    N/A");
  }
}




void cpu_exec(uint64_t n) {
  g_print_step = (n < MAX_INST_TO_PRINT); 
  switch (sim_state.state) {
    case SIM_END: 
    case SIM_ABORT:
      printf("Program execution has ended. To restart the program, exit  and run again.\n");
      return;
    default: sim_state.state = SIM_RUNNING;
  }
  uint64_t timer_start = get_time();
  execute(n); 

  uint64_t timer_end = get_time();
  g_timer += timer_end - timer_start;

  switch (sim_state.state) {
    case SIM_RUNNING: sim_state.state = SIM_STOP; break;
    case SIM_END: 
    case SIM_ABORT:
      Log("SIM: %s at pc = [pc值信息有误,待修复]" FMT_WORD,
          (sim_state.state == SIM_ABORT ? ANSI_FMT("ABORT", ANSI_FG_RED) :
          (sim_state.halt_ret == 0 ? ANSI_FMT("HIT GOOD TRAP", ANSI_FG_GREEN) :
          ANSI_FMT("HIT BAD TRAP", ANSI_FG_RED))),
          sim_state.halt_pc);
      npc_get_clk_count();
    case SIM_QUIT: 
        statistic();
  }
}



//我想的就是复位的时候