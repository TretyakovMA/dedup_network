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

TOP_MODULE    ?= dedup_tx_top_tb
RTL_MODULE    ?= dedup_tx_top.sv

UVM_SRC        = $(QUESTASIM_DIR)/verilog_src/uvm-1.2/src
UVM_DPI        = $(QUESTASIM_DIR)/uvm-1.2/$(DPI_OS_DIR)/uvm_dpi

# Переменные от Python
TEST_NAME      ?= base_test
SEED           ?= random
VERBOSITY      ?= UVM_MEDIUM
ITER           ?= 1
SIM_START_TIME ?= N/A
RUN_DIR        ?= .

TIMEOUT        = 1000000000

GUI      = OFF
SAVE_WLF = ON
SAVE_VCD = OFF
COVERAGE = OFF
DEL_TRANSCRIPT = ON

RUN_SETUP =
TEST_SETUP =
TEST_DEFINES =
DO_COMMAND =




ifeq ($(GUI),ON)
    VSIM_MODE ?= -gui
	DO_COMMAND += log -r /*;
else
    VSIM_MODE ?= -c
endif

ifeq ($(SAVE_WLF),ON)
	RUN_SETUP += -wlf "$(RUN_DIR)/vsim_$(TEST_NAME)_$(ITER).wlf"
endif

ifeq ($(SAVE_VCD),ON)
	DO_COMMAND += vcd file "$(RUN_DIR)/vsim_$(TEST_NAME)_$(ITER).vcd"; vcd add -r /*;
endif

DO_COMMAND += onfinish stop; run -all;

ifeq ($(COVERAGE),ON)
	RUN_SETUP += -cvgperinstance
	RUN_SETUP += -coverage
	DO_COMMAND += coverage save "$(RUN_DIR)/ucdb_$(TEST_NAME)_$(ITER).ucdb";
endif

ifeq ($(DEL_TRANSCRIPT),ON)
	RUN_SETUP += -l $(TRANSCRIPT_OUT)
endif

ifeq ($(GUI),OFF)
	DO_COMMAND += quit;
endif


RUN_COMMAND = vsim         \
			  $(VSIM_MODE) \
			  $(RUN_SETUP) \
			  $(TEST_SETUP) \
			  $(TEST_DEFINES) \
			  -do "$(DO_COMMAND)" \
			  $(TOP_MODULE) \
			  -sv_seed $(SEED) \
			  +UVM_TIMEOUT=$(TIMEOUT) \
			  "+UVM_TESTNAME=$(TEST_NAME)" \
			  "+RUN_COUNT=$(ITER)" \
			  "+UVM_VERBOSITY=$(VERBOSITY)" \
			  "+SIM_START_TIME=$(SIM_START_TIME)" \
			  "+LOG_DIR=$(RUN_DIR)/" \
			  -sv_lib $(UVM_DPI)


# =============================================================================
# Правила сборки (одинаковые для всех ОС)
# =============================================================================

all: compile run

pre_compile:
	@$(CREATE_WORK)

# b=block, c=condition, e=FSM, s=statement, f=functional
compile: pre_compile
	vlog -sv +acc -cover bcesf +incdir+$(UVM_SRC) \
		$(RTL_PATH)/interfaces/axis_if.sv \
		$(RTL_PATH)/interfaces/spi_if.sv \
		$(RTL_PATH)/gen/tx_regs_pkg.sv \
		$(RTL_PATH)/gen/tx_regs.sv \
		$(RTL_PATH)/common/fifo.sv \
		$(RTL_PATH)/common/axis_input_fifo.sv \
		$(RTL_PATH)/transmitter/spi_tx_regs_wrapper.sv \
		$(RTL_PATH)/transmitter/gf2_xor_hash.sv \
		$(RTL_PATH)/transmitter/dedup_tx_controller.sv \
		$(RTL_PATH)/transmitter/$(RTL_MODULE) \
		$(TB_TOP_PATH)/$(TOP_MODULE).sv
		

run: compile
	$(RUN_COMMAND)


UCDB_FILES = $(wildcard ucdb_*.ucdb) $(wildcard runs/*/ucdb_*.ucdb)
merge_coverage:
	vcover merge -testassociated -verbose -out total.ucdb $(foreach f,$(UCDB_FILES),"$(f)")

clean:
	-$(RM) transcript *.wlf *.ucdb *.log *.vcd total.ucdb *.txt $(SUB_ERR) 
	-$(RMDIR) work rtl_work $(SUB_ERR)

clean_all: clean
	-$(RMDIR) runs bugs summary.md $(SUB_ERR)

.PHONY: all pre_compile compile sim run merge_coverage clean clean_all