TOP_MODULE := tdl_tab_hash_tb_top
USE_UVM := OFF

BENCH_RUN_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
include $(BENCH_RUN_DIR)/../../../../common/scripts/questa.mk

# Questa may return zero after $fatal when followed by an unconditional quit.
# Preserve the common runner's waveform/coverage commands and check the TB verdict.
ifeq ($(GUI),OFF)
DO_COMMAND := $(subst quit;,if {[examine -radix unsigned /tdl_tab_hash_tb_top/test_passed] == 1} {quit -code 0} else {quit -code 1};,$(DO_COMMAND))
endif
