`ifndef FIFO_PKG
`define FIFO_PKG
package fifo_pkg;
    typedef enum bit {WRITE = 1, READ = 0} op_t;
    `include "fifo_transaction.sv"
    `include "fifo_driver.sv"
    `include "fifo_monitor.sv"
    `include "fifo_scoreboard.sv"
    `include "fifo_generator.sv"
    `include "fifo_environment.sv"
endpackage
`endif