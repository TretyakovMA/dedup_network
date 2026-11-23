TOP_MODULE := tdl_bloom_filter_tb_top
USE_UVM := OFF

BENCH_RUN_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
include $(BENCH_RUN_DIR)/../../../../common/scripts/questa.mk

# Return a nonzero status from make if the bench stops before PASS.
ifeq ($(GUI),OFF)
DO_COMMAND := $(subst quit;,if {[examine -radix unsigned /$(TOP_MODULE)/test_passed] == 1} {quit -code 0} else {quit -code 1};,$(DO_COMMAND))
endif
