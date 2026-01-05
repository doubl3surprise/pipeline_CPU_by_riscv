# 顶层辅助 Makefile：封装常用测试流程

.PHONY: riscv cpu project pred pc riscv_pred_pc cpu_pred_pc project_pred_pc

# Defaults (可在命令行覆盖)
ARCH ?= riscv32-npc
CPU_HOME ?= $(shell pwd)
SIM_HOME ?= $(CPU_HOME)/simulator
AM_HOME ?= $(CPU_HOME)/abstract-machine
ISA_LIST ?= i m

# 兼容用户想输入的命令：
# - make riscv pred pc
# - make cpu pred pc
#
# 注意：make 会把每个“词”当作一个目标来构建，所以 pred/pc 做成占位目标（不执行任何事），
# 真正的动作由 riscv/cpu 目标触发。
riscv: riscv_pred_pc
cpu:   cpu_pred_pc
project: project_pred_pc
pred:
	@true
pc:
	@true

project_pred_pc:
	@echo "[INFO] Project PC prediction evaluation (800k commit + progress curve)"
	@echo "[INFO] ARCH=$(ARCH)"
	@echo "[INFO] AM_HOME=$(AM_HOME)"
	@echo "[INFO] SIM_HOME=$(SIM_HOME)"
	@ARCH="$(ARCH)" AM_HOME="$(AM_HOME)" SIM_HOME="$(SIM_HOME)" MAX_COMMIT=800000 INTERVAL=50000 WORKLOAD=pcpred-mix-800k \
		bash scripts/run_project_pred_pc.sh

riscv_pred_pc:
	@echo "[INFO] Batch run riscv-tests-am PC prediction stats"
	@echo "[INFO] ARCH=$(ARCH)"
	@echo "[INFO] ISA_LIST=$(ISA_LIST)"
	@echo "[INFO] AM_HOME=$(AM_HOME)"
	@echo "[INFO] SIM_HOME=$(SIM_HOME)"
	@ISA_LIST="$(ISA_LIST)" ARCH="$(ARCH)" AM_HOME="$(AM_HOME)" SIM_HOME="$(SIM_HOME)" REBUILD_SIM=1 \
		bash scripts/run_riscv_tests_am_pcpred.sh
	@echo ""
	@echo "[INFO] Summary CSV: simulator/build/pcpred_logs/riscv-tests-am/pcpred_summary.csv"
	@echo ""
	@echo "==================== PC Pred Summary (weighted) ===================="
	@awk -F, 'NR>1 && $$3!="NA" {tot+=($$3+0); cor+=($$4+0)} \
	          NR>1 && $$7!="NA" {btot+=($$7+0); bcor+=($$8+0)} \
	          NR>1 && $$9!="NA" {bftot+=($$9+0); bfcor+=($$10+0)} \
	          NR>1 && $$11!="NA" {bbtot+=($$11+0); bbcor+=($$12+0)} \
	          NR>1 && $$13!="NA" {jtot+=($$13+0); jcor+=($$14+0)} \
		END { \
		  if (tot>0) printf("[ALL ] %.2f%%  (%d/%d)\n", cor*100.0/tot, cor, tot); else print("[ALL ] N/A"); \
		  if (btot>0) printf("[B   ] %.2f%%  (%d/%d)\n", bcor*100.0/btot, bcor, btot); else print("[B   ] N/A"); \
		  if (bftot>0) printf("[B-F ] %.2f%%  (%d/%d)\n", bfcor*100.0/bftot, bfcor, bftot); else print("[B-F ] N/A"); \
		  if (bbtot>0) printf("[B-B ] %.2f%%  (%d/%d)\n", bbcor*100.0/bbtot, bbcor, bbtot); else print("[B-B ] N/A"); \
		  if (jtot>0) printf("[JALR] %.2f%%  (%d/%d)\n", jcor*100.0/jtot, jcor, jtot); else print("[JALR] N/A"); \
		}' simulator/build/pcpred_logs/riscv-tests-am/pcpred_summary.csv || true
	@echo "===================================================================="
	@echo ""
	@echo "Top 15 worst tests by overall rate (with split B/JALR):"
	@echo "  overall     B        JALR   ISA  test           ALL(c/t)   B(c/t)     JALR(c/t)"
	@awk -F, 'NR==1{next} $$3=="NA"{next} { \
	      tot=($$3+0); cor=($$4+0); r= (tot>0)? (cor*100.0/tot) : 0; \
	      btot=$$7; bcor=$$8; \
	      jtot=$$9; jcor=$$10; \
	      brs="--"; jrs="--"; \
	      if (btot!="NA" && (btot+0)>0) { br=(bcor+0)*100.0/(btot+0); brs=sprintf("%.2f%%", br); } \
	      if (jtot!="NA" && (jtot+0)>0) { jr=(jcor+0)*100.0/(jtot+0); jrs=sprintf("%.2f%%", jr); } \
	      printf("%8.2f%%  %7s  %7s   %-3s  %-12s  %4d/%-4d  %4s/%-4s  %4s/%-4s\n", \
	             r, brs, jrs, $$1, $$2, cor, tot, bcor, btot, jcor, jtot); }' \
	    simulator/build/pcpred_logs/riscv-tests-am/pcpred_summary.csv | sort -n | head -15 || true

cpu_pred_pc:
	@echo "[INFO] Batch run cpu-tests PC prediction stats"
	@echo "[INFO] ARCH=$(ARCH)"
	@echo "[INFO] AM_HOME=$(AM_HOME)"
	@echo "[INFO] SIM_HOME=$(SIM_HOME)"
	@ARCH="$(ARCH)" AM_HOME="$(AM_HOME)" SIM_HOME="$(SIM_HOME)" REBUILD_SIM=1 \
		bash scripts/run_cpu_tests_pcpred.sh
	@echo ""
	@echo "[INFO] Summary CSV: simulator/build/pcpred_logs/cpu-tests/pcpred_summary.csv"
	@echo ""
	@echo "==================== PC Pred Summary (weighted) ===================="
	@awk -F, 'NR>1 && $$2!="NA" {tot+=($$2+0); cor+=($$3+0)} \
	          NR>1 && $$6!="NA" {btot+=($$6+0); bcor+=($$7+0)} \
	          NR>1 && $$8!="NA" {bftot+=($$8+0); bfcor+=($$9+0)} \
	          NR>1 && $$10!="NA" {bbtot+=($$10+0); bbcor+=($$11+0)} \
	          NR>1 && $$12!="NA" {jtot+=($$12+0); jcor+=($$13+0)} \
		END { \
		  if (tot>0) printf("[ALL ] %.2f%%  (%d/%d)\n", cor*100.0/tot, cor, tot); else print("[ALL ] N/A"); \
		  if (btot>0) printf("[B   ] %.2f%%  (%d/%d)\n", bcor*100.0/btot, bcor, btot); else print("[B   ] N/A"); \
		  if (bftot>0) printf("[B-F ] %.2f%%  (%d/%d)\n", bfcor*100.0/bftot, bfcor, bftot); else print("[B-F ] N/A"); \
		  if (bbtot>0) printf("[B-B ] %.2f%%  (%d/%d)\n", bbcor*100.0/bbtot, bbcor, bbtot); else print("[B-B ] N/A"); \
		  if (jtot>0) printf("[JALR] %.2f%%  (%d/%d)\n", jcor*100.0/jtot, jcor, jtot); else print("[JALR] N/A"); \
		}' simulator/build/pcpred_logs/cpu-tests/pcpred_summary.csv || true
	@echo "===================================================================="
	@echo ""
	@echo "Worst 15 tests by overall rate:"
	@echo "  overall     B        JALR   test           ALL(c/t)   B(c/t)     JALR(c/t)"
	@awk -F, 'NR==1{next} $$2=="NA"{next} { \
	      tot=($$2+0); cor=($$3+0); r= (tot>0)? (cor*100.0/tot) : 0; \
	      btot=$$6; bcor=$$7; \
	      jtot=$$8; jcor=$$9; \
	      brs="--"; jrs="--"; \
	      if (btot!="NA" && (btot+0)>0) { br=(bcor+0)*100.0/(btot+0); brs=sprintf("%.2f%%", br); } \
	      if (jtot!="NA" && (jtot+0)>0) { jr=(jcor+0)*100.0/(jtot+0); jrs=sprintf("%.2f%%", jr); } \
	      printf("%8.2f%%  %7s  %7s   %-12s  %4d/%-4d  %4s/%-4s  %4s/%-4s\n", \
	             r, brs, jrs, $$1, cor, tot, bcor, btot, jcor, jtot); }' \
	    simulator/build/pcpred_logs/cpu-tests/pcpred_summary.csv | sort -n | head -15 || true