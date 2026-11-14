# Shared single-test runner. Invoke make from a bench's run/ directory
# (or use make -C). Test verdicts and non-UVM timeouts belong to the TB.
.DEFAULT_GOAL := run
.NOTPARALLEL:

# Capture this file's directory before including the bench's test list.
# GnuWin32 make 3.81 incorrectly prefixes CURDIR when abspath receives
# an absolute drive-letter path. Keep these paths absolute but uncollapsed.
QUESTA_MK_DIR := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))
PROJECT_PATH  := $(QUESTA_MK_DIR)/../../..
DBG_PATH      := $(PROJECT_PATH)/dbg
COMMON_PATH   := $(DBG_PATH)/common
RTL_PATH      := $(PROJECT_PATH)/rtl
BENCH_RUN_DIR ?= $(CURDIR)
TB_PATH       := $(BENCH_RUN_DIR)/..
TB_TOP_PATH   := $(TB_PATH)/testbench
FILES_TO_COMP ?= $(BENCH_RUN_DIR)/bench_opt.opt

ifneq ($(CURDIR),$(BENCH_RUN_DIR))
    $(error Run make from $(BENCH_RUN_DIR), or use make -C)
endif
ifeq ($(strip $(TOP_MODULE)),)
    $(error TOP_MODULE must be set in the local Makefile)
endif

QUESTASIM_DIR ?= $(subst \,/,$(QUESTA_HOME))
USE_UVM      ?= OFF
SEED         ?= random
VERBOSITY    ?= UVM_MEDIUM
TIMEOUT      ?= 1000000000
ITER         ?= 1
SIM_START_TIME ?= N/A
RUN_DIR      ?= .
# Recursive expansion is intentional: $@ is the selected test target.
TESTNAME     ?= $@

GUI             ?= OFF
SAVE_WLF        ?= ON
SAVE_VCD        ?= OFF
COVERAGE        ?= OFF
DEL_TRANSCRIPT  ?= OFF

VLIB   ?= vlib
VMAP   ?= vmap
VLOG   ?= vlog
VSIM   ?= vsim
VCOVER ?= vcover
VLOG_FLAGS ?=
VSIM_FLAGS ?=
PLUSARGS   ?=

ifeq ($(OS),Windows_NT)
    SHELL := cmd.exe
    DPI_OS_DIR := win64
    NULL_FILE  := NUL
    CREATE_WORK = if not exist work $(VLIB) work
    CREATE_RUN_DIR = if not exist "$(RUN_DIR)" mkdir "$(RUN_DIR)"
else
    DPI_OS_DIR := linux_x86_64
    NULL_FILE  := /dev/null
    CREATE_WORK = test -d work || $(VLIB) work
    CREATE_RUN_DIR = mkdir -p "$(RUN_DIR)"
endif

UVM_SRC ?= $(QUESTASIM_DIR)/verilog_src/uvm-1.2/src
UVM_DPI ?= $(QUESTASIM_DIR)/uvm-1.2/$(DPI_OS_DIR)/uvm_dpi
export UVM_SRC RTL_PATH TB_TOP_PATH COMMON_PATH

UVM_VLOG_FLAGS =
UVM_VSIM_FLAGS =
UVM_PLUSARGS =
ifeq ($(USE_UVM),ON)
    include $(BENCH_RUN_DIR)/testlist.inc
    ifeq ($(strip $(TESTLIST)),)
        $(error TESTLIST is empty for this UVM bench)
    endif
    UVM_VLOG_FLAGS += +incdir+"$(UVM_SRC)"
    UVM_VSIM_FLAGS += -sv_lib "$(UVM_DPI)"
    UVM_PLUSARGS += +UVM_TESTNAME=$(TESTNAME) +UVM_TIMEOUT=$(TIMEOUT)
    UVM_PLUSARGS += +UVM_VERBOSITY=$(VERBOSITY)
else ifeq ($(USE_UVM),OFF)
    TESTLIST := unit
else
    $(error USE_UVM must be ON or OFF)
endif
DEFAULT_TEST ?= $(firstword $(TESTLIST))
ifeq ($(filter $(DEFAULT_TEST),$(TESTLIST)),)
    $(error DEFAULT_TEST must be present in TESTLIST)
endif

COMPILE_SETUP = -sv +acc
RUN_SETUP =
TEST_SETUP ?=
DO_COMMAND =

ifeq ($(GUI),ON)
    VSIM_MODE := -gui
    RUN_SETUP += +GUI
else
    VSIM_MODE := -c
endif

ifeq ($(SAVE_WLF),ON)
    RUN_SETUP += -wlf "$(RUN_DIR)/vsim_$(TESTNAME)_$(ITER).wlf"
    DO_COMMAND += log -r /*;
endif
ifeq ($(SAVE_VCD),ON)
    DO_COMMAND += vcd file {$(RUN_DIR)/vsim_$(TESTNAME)_$(ITER).vcd}; vcd add -r /*;
endif

# Keep simulation control inline; the testbench decides PASS/FAIL.
DO_COMMAND += onfinish stop; run -all;
ifeq ($(COVERAGE),ON)
    COMPILE_SETUP += -cover bcesf
    RUN_SETUP += -coverage -cvgperinstance
    DO_COMMAND += coverage save {$(RUN_DIR)/ucdb_$(TESTNAME)_$(ITER).ucdb};
endif
ifeq ($(DEL_TRANSCRIPT),ON)
    RUN_SETUP += -l $(NULL_FILE)
else
    RUN_SETUP += -l "$(RUN_DIR)/vsim_$(TESTNAME)_$(ITER).log"
endif
ifeq ($(GUI),OFF)
    DO_COMMAND += quit;
endif

RUN_COMMAND = $(VSIM) $(VSIM_MODE) $(RUN_SETUP) $(VSIM_FLAGS) \
    $(TEST_SETUP) $(UVM_VSIM_FLAGS) -do "$(DO_COMMAND)" \
    $(TOP_MODULE) -sv_seed $(SEED) $(UVM_PLUSARGS) \
    "+RUN_COUNT=$(ITER)" "+SIM_START_TIME=$(SIM_START_TIME)" \
    "+LOG_DIR=$(RUN_DIR)/" $(PLUSARGS)

.PHONY: all run pre_compile compile clean clean_all help merge_coverage $(TESTLIST)
all: run
run: $(DEFAULT_TEST)

pre_compile:
	@$(CREATE_WORK)
	$(VMAP) work

compile: pre_compile
	$(VLOG) $(COMPILE_SETUP) $(UVM_VLOG_FLAGS) $(VLOG_FLAGS) -l "$(BENCH_RUN_DIR)/compile.log" -f "$(FILES_TO_COMP)"

$(TESTLIST): compile
	@$(CREATE_RUN_DIR)
	$(RUN_COMMAND)

UCDB_FILES = $(wildcard *.ucdb) $(wildcard runs/*/*.ucdb) $(wildcard results/*/*.ucdb)
MERGE_INPUTS = $(filter-out total.ucdb,$(UCDB_FILES))
merge_coverage:
	$(if $(strip $(MERGE_INPUTS)),,$(error No input coverage databases found))
	$(VCOVER) merge -testassociated -verbose -out total.ucdb $(foreach f,$(MERGE_INPUTS),"$(f)")

# Only remove known local simulation outputs. Arbitrary RUN_DIR paths are
# deliberately excluded. clean_all also removes local runs/ and results/.
ifeq ($(OS),Windows_NT)
CLEAN_DIR_NAMES = 'work','rtl_work'
clean_all: CLEAN_DIR_NAMES = 'work','rtl_work','runs','results'
clean clean_all:
	powershell.exe -NoProfile -NonInteractive -Command "& { $$ErrorActionPreference = 'Stop'; $$root = [IO.Path]::GetFullPath('$(BENCH_RUN_DIR)'); Get-ChildItem -LiteralPath $$root -File | Where-Object { $$_.Name -eq 'transcript' -or $$_.Name -match '\.(wlf|ucdb|log|vcd)$$' } | ForEach-Object { Remove-Item -LiteralPath $$_.FullName -Force }; foreach ($$name in @($(CLEAN_DIR_NAMES))) { $$target = [IO.Path]::GetFullPath((Join-Path $$root $$name)); if (-not $$target.StartsWith($$root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Cleanup path is outside the bench' }; if (Test-Path -LiteralPath $$target) { Remove-Item -LiteralPath $$target -Recurse -Force } } }"
else
clean:
	rm -f transcript *.wlf *.ucdb *.log *.vcd
	rm -rf work rtl_work
clean_all: clean
	rm -rf runs results
endif

help:
	@echo Tests: $(TESTLIST)
	@echo Default test: $(DEFAULT_TEST)
	@echo Targets: clean clean_all compile run merge_coverage
	@echo Options: SEED GUI SAVE_WLF SAVE_VCD COVERAGE RUN_DIR ITER VERBOSITY
