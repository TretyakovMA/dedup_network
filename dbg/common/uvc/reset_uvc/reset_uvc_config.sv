`ifndef RESET_UVC_CONFIG
`define RESET_UVC_CONFIG
class reset_uvc_config extends uvm_object;
    `uvm_object_utils(reset_uvc_config)

    virtual interface reset_uvc_if vif;
    
    // 1 - active high (rst), 0 - active low (rst_n)
    bit active_level = 0; 

    function new(string name = "reset_uvc_config");
        super.new(name);
    endfunction: new

    function void set_vif(virtual interface reset_uvc_if vif);
        this.vif = vif;
    endfunction
endclass
`endif