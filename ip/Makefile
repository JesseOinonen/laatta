VIVADO ?= /opt/2025.2/Vivado/bin/vivado
XSIM := $(dir $(VIVADO))xsim

PROJECT := laatta
BUILD := build/$(PROJECT)
XPR := $(BUILD)/$(PROJECT).xpr
SIM_DIR     := $(BUILD)/$(PROJECT).sim/sim_1/behav/xsim
SIM_DIR_ABS := $(abspath $(SIM_DIR))
SCRIPTS_DIR := ../../scripts

TEST ?= csr_test
TESTS := csr_test stream_test dram_read_test datapath_test

.PHONY: all build files sim regression gui clean

all: build

$(BUILD):
	@mkdir -p $(BUILD)

# Create project + refresh file list.
build: $(BUILD)
	@cd $(BUILD) && $(VIVADO) -mode batch -source $(SCRIPTS_DIR)/build.tcl

# Refresh the Vivado file list (after adding/removing sources).
files: $(BUILD)
	@cd $(BUILD) && $(VIVADO) -mode batch -source $(SCRIPTS_DIR)/add_files.tcl

# Run a single test.
sim: build
	@echo "================================================"
	@echo "Running test: $(TEST)"
	@echo "================================================"
	@if [ ! -d "$(SIM_DIR)" ]; then \
	  echo "Simulation build not found, compiling..."; \
	  cd $(BUILD) && $(VIVADO) -mode batch -source $(SCRIPTS_DIR)/compile.tcl; \
	fi
	@cd $(SIM_DIR) && $(XSIM) top_behav -R --testplusarg "UVM_TESTNAME=$(TEST)"
	@echo "Test $(TEST) completed"

# Run every test in $(TESTS).
regression: build
	@echo "================================================"
	@echo "Starting REGRESSION - Tests: $(TESTS)"
	@echo "================================================"
	@if [ ! -d "$(SIM_DIR)" ]; then \
	  echo "Simulation build not found, compiling..."; \
	  cd $(BUILD) && $(VIVADO) -mode batch -source $(SCRIPTS_DIR)/compile.tcl; \
	fi
	@failed=0; passed=0; failed_tests=""; \
	for t in $(TESTS); do \
	  echo ""; echo ">>> Running test: $$t"; \
	  _log="/tmp/laatta_regress_$$t.log"; \
	  cd $(SIM_DIR_ABS) && $(XSIM) top_behav -R --testplusarg "UVM_TESTNAME=$$t" 2>&1 | tee "$$_log"; \
	  if grep -q "TEST PASSED" "$$_log"; then \
	    passed=$$((passed+1)); echo "PASSED: $$t"; \
	  else \
	    failed=$$((failed+1)); failed_tests="$$failed_tests $$t"; echo "FAILED: $$t"; \
	  fi; \
	  rm -f "$$_log"; \
	done; \
	echo ""; echo "================================================"; \
	echo "REGRESSION COMPLETE: $$passed passed, $$failed failed"; \
	if [ $$failed -gt 0 ]; then \
	  echo "Failed tests:"; for ft in $$failed_tests; do echo "  - $$ft"; done; \
	fi; \
	echo "================================================"; \
	[ $$failed -eq 0 ]

# Open Vivado GUI with a test configured.
gui: build
	@echo "Opening Vivado GUI for test: $(TEST)"
	cd $(BUILD) && $(VIVADO) -mode gui -source $(SCRIPTS_DIR)/sim.tcl -tclargs $(TEST) &

# Scaffold a new UVM test: make testcase-<name>
testcase-%:
	python3 scripts/new_test.py $*

clean:
	@echo "Cleaning build directory..."
	rm -rf $(BUILD)
