# =============================================================================
# Автоопределение ОС и настройка платформозависимых переменных
# =============================================================================
ifeq ($(OS),Windows_NT)
    # Настройки для Windows
	DPI_OS_DIR   := win64
    RM           := del /Q /F
    RMDIR        := rmdir /S /Q
    # Команда создания библиотеки, если её нет
    CREATE_WORK  := if not exist work vlib work
    # Игнорирование ошибок удаления (в Windows del падает, если файлов нет)
    SUB_ERR      := 2>NUL || rem
	# Отключение файла transcript для Windows
    TRANSCRIPT_OUT := NUL
else
    # Настройки для Linux
	DPI_OS_DIR   := linux_x86_64
    RM           := rm -f
    RMDIR        := rm -rf
    CREATE_WORK  := vlib work
    SUB_ERR      := 2>/dev/null || true
	TRANSCRIPT_OUT := /dev/null
endif
#
# =============================================================================
# Переменные путей
# =============================================================================
QUESTASIM_DIR ?= $(QUESTA_HOME)


DBG_PATH      := $(CURDIR)/..
PROJECT_PATH  := $(DBG_PATH)/../..
TB_TOP_PATH   := $(DBG_PATH)/testbench
RTL_PATH      := $(PROJECT_PATH)/rtl
TB_PKG_PATH   := $(TB_TOP_PATH)/svm

SVM_PATH	  := $(PROJECT_PATH)/dbg/common/svm

SVM_PKG       := svm_pkg.sv

TOP_MODULE    ?= fifo_tb_top
RTL_MODULE    ?= fifo.sv
TB_PKG        ?= fifo_pkg.sv


UVM_SRC        = $(QUESTASIM_DIR)/verilog_src/uvm-1.2/src
UVM_DPI        = $(QUESTASIM_DIR)/uvm-1.2/$(DPI_OS_DIR)/uvm_dpi

# Переменные от Python
TEST_NAME      ?= fifo_write_only_test
SEED           ?= random
VERBOSITY      ?= UVM_LOW
ITER           ?= 1
SIM_START_TIME ?= N/A
RUN_DIR        ?= .

# =============================================================================
# Правила сборки (одинаковые для всех ОС)
# =============================================================================

all: compile sim

pre_compile:
	@$(CREATE_WORK)

compile: pre_compile
	vlog -sv +acc -cover f +incdir+$(UVM_SRC) \
		$(SVM_PATH)/$(SVM_PKG) \
		$(RTL_PATH)/interfaces/fifo_if.sv \
		$(RTL_PATH)/$(RTL_MODULE) \
		$(TB_PKG_PATH)/$(TB_PKG) \
		$(TB_TOP_PATH)/$(TOP_MODULE).sv

sim:
	vsim -c \
		-l $(TRANSCRIPT_OUT) \
		-cvgperinstance \
		-wlf "$(RUN_DIR)/vsim_$(TEST_NAME)_$(ITER).wlf" \
		-do "log -r /*; vcd file $(RUN_DIR)/vsim_$(TEST_NAME)_$(ITER).vcd; vcd add -r /*; run -all; coverage save $(RUN_DIR)/ucdb_$(TEST_NAME)_$(ITER).ucdb; quit" \
		$(TOP_MODULE) \
		-coverage \
		-sv_seed $(SEED) \
		+TESTNAME=$(TEST_NAME) \
		"+RUN_COUNT=$(ITER)" \
		"+UVM_VERBOSITY=$(VERBOSITY)" \
		"+SIM_START_TIME=$(SIM_START_TIME)" \
		"+LOG_DIR=$(RUN_DIR)/" \
		-sv_lib $(UVM_DPI)

UCDB_FILES = $(wildcard ucdb_*.ucdb) $(wildcard runs/*/ucdb_*.ucdb)
merge_coverage:
	vcover merge -testassociated -verbose -out total.ucdb $(foreach f,$(UCDB_FILES),"$(f)")

clean:
	-$(RM) transcript *.wlf *.ucdb *.log *.vcd total.ucdb $(SUB_ERR)
	-$(RMDIR) work rtl_work $(SUB_ERR)

clean_all: clean
	-$(RMDIR) runs bugs summary.md $(SUB_ERR)

.PHONY: all pre_compile compile sim merge_coverage clean clean_all