`ifndef CLOCK_UVC_PKG
`define CLOCK_UVC_PKG

`include "clock_uvc_if.sv"
package clock_uvc_pkg;
    timeunit 1ns;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    typedef enum {
        CLOCK_UVC_TIME_S,
        CLOCK_UVC_TIME_MS,
        CLOCK_UVC_TIME_US,
        CLOCK_UVC_TIME_NS,
        CLOCK_UVC_TIME_PS,
        CLOCK_UVC_TIME_FS
    } clock_uvc_time_unit;

    `include "clock_uvc_config.sv"
    `include "start_clock_seq.sv"
    `include "clock_uvc_driver.sv"
    `include "clock_uvc_agent.sv"
endpackage
`endif