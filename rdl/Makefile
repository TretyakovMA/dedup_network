# Переменные конфигурации
RDL_NAME     = tx_regs
RDL_SRC      = $(RDL_NAME).rdl
OUT_DIR      = gen
OUT_FILE     = reg_model

RTL_DIR      = ../rtl/$(OUT_DIR)
UVM_DIR      = ../dbg/$(OUT_DIR)
HTML_DIR     = ../doc/html/$(OUT_DIR)


PEAKRDL      = peakrdl
CPU_IF       = passthrough   # Варианты: passthrough,apb3,apb3-flat,apb4,apb4-flat,axi4-lite,axi4-lite-flat,avalon-mm,avalon-mm-flat,wishbone,wishbone-flat,obi,obi-flat

.PHONY: all rtl uvm html header python lint help

all: rtl uvm html

# 1. Генерация RTL (SystemVerilog)
rtl: $(RDL_SRC)
	$(PEAKRDL) regblock $(RDL_SRC) -o $(RTL_DIR) --cpuif $(CPU_IF)

# 2. Генерация UVM RAL модели
uvm: $(RDL_SRC)
	$(PEAKRDL) uvm $(RDL_SRC) -o $(UVM_DIR)/$(OUT_FILE).sv

# 3. Генерация HTML документации
html: $(RDL_SRC)
	$(PEAKRDL) html $(RDL_SRC) -o $(HTML_DIR)




help:
	@echo Available targets:
	@echo   make all     - Generate RTL, UVM, and HTML (default)
	@echo   make rtl     - Generate SystemVerilog RTL code
	@echo   make uvm     - Generate UVM register model
	@echo   make html    - Generate HTML documentation