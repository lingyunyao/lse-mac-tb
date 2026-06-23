# Makefile for the log-domain MAC unit testbench.
#
# Usage:
#   make            compile + run (default)
#   make compile    elaborate tb_mac.sv with Verilator
#   make run        run the compiled binary
#   make clean      remove build artifacts
#
# Override the Verilator binary if needed:
#   make VERILATOR=/path/to/verilator

# Auto-detect: PATH first, then any conda-forge env, then Homebrew.
VERILATOR ?= $(or \
  $(shell command -v verilator 2>/dev/null), \
  $(shell find $(HOME)/conda-envs -maxdepth 3 -name verilator -type f 2>/dev/null | head -1), \
  $(shell find /opt/homebrew /usr/local -maxdepth 4 -name verilator -type f 2>/dev/null | head -1), \
  verilator)
export PATH := $(dir $(VERILATOR)):$(PATH)
OUT_DIR   := obj_dir
SIM_BIN   := $(OUT_DIR)/Vtb_mac

VERILATOR_FLAGS := \
  --binary --top-module tb_mac \
  --timing -sv \
  --no-assert \
  --Mdir $(OUT_DIR) \
  -Wno-fatal \
  -Wno-WIDTH -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC \
  -Wno-UNOPTFLAT -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
  -Wno-CASEINCOMPLETE -Wno-LATCH -Wno-COMBDLY \
  -Wno-BLKANDNBLK -Wno-PROCASSWIRE

.PHONY: all compile run clean

all: compile run

compile:
	$(VERILATOR) $(VERILATOR_FLAGS) tb_mac.sv
	@test -x $(SIM_BIN) && echo "[make] OK -> $(SIM_BIN)"

run: $(SIM_BIN)
	$(SIM_BIN)

clean:
	rm -rf $(OUT_DIR)
