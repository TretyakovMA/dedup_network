`ifndef RESET_UVC_PKG
`define RESET_UVC_PKG

`include "reset_uvc_if.sv"
package reset_uvc_pkg;
    timeunit 1ns;
    timeprecision 1ns;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "reset_uvc_config.sv"
    `include "reset_seq_item.sv"
    `include "reset_seq.sv"
    `include "reset_uvc_driver.sv"
    `include "reset_uvc_agent.sv"
endpackage
`endif