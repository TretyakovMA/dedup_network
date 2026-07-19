`ifndef FIFO_PKG
`define FIFO_PKG
package fifo_pkg;
    `ifndef FIFO_WIDTH
        `define FIFO_WIDTH 8
    `endif

    `ifndef FIFO_DEPTH
        `define FIFO_DEPTH 16
    `endif

    import svm_pkg::*;
    `include "svm_macros.sv"

    typedef bit [`FIFO_WIDTH-1:0]          data_t;
    typedef virtual fifo_if#(`FIFO_WIDTH)  vif_t;
    typedef enum bit {WRITE = 1, READ = 0} op_t;

    
    `include "fifo_transaction.sv"
    typedef mailbox#(fifo_transaction)     mailbox_t;
    `include "fifo_driver.sv"
    `include "fifo_monitor.sv"
    `include "fifo_ref_model.sv"
    `include "fifo_scoreboard.sv"
    `include "fifo_write_only_sequence.sv"
    `include "fifo_overflow_underflow_seq.sv"
    `include "fifo_environment.sv"
    `include "fifo_base_test.sv"
    `include "fifo_write_only_test.sv"
    `include "fifo_overflow_underflow_test.sv"
endpackage
`endif