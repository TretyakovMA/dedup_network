`ifndef CLOCK_UVC_CONFIG
`define CLOCK_UVC_CONFIG
class clock_uvc_config extends uvm_object;
    `uvm_object_utils(clock_uvc_config)

    function new(string name = "clock_uvc_config");
        super.new(name);
    endfunction: new

    virtual interface clock_uvc_if vif;
    realtime   period;

    function void set_period(
        realtime          period,
        clock_uvc_time_unit unit = CLOCK_UVC_TIME_NS
    );
        case (unit)
            CLOCK_UVC_TIME_S:  this.period = period * 1.0e9;
            CLOCK_UVC_TIME_MS: this.period = period * 1.0e6;
            CLOCK_UVC_TIME_US: this.period = period * 1.0e3;
            CLOCK_UVC_TIME_NS: this.period = period;
            CLOCK_UVC_TIME_PS: this.period = period * 1.0e-3;
            CLOCK_UVC_TIME_FS: this.period = period * 1.0e-6;
        endcase
    endfunction

    function void set_vif(virtual interface clock_uvc_if vif);
        this.vif = vif;
    endfunction

    function realtime get_period();
        return period;
    endfunction
endclass
`endif