`ifndef RESET_UVC_DRIVER
`define RESET_UVC_DRIVER
class reset_uvc_driver extends uvm_driver #(reset_seq_item);
    `uvm_component_utils(reset_uvc_driver)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    virtual interface reset_uvc_if vif;
    reset_uvc_config cfg;

    local task run_phase(uvm_phase phase);
        // Установка неактивного уровня по умолчанию
        vif.rst <= ~cfg.active_level;

        forever begin
            seq_item_port.get_next_item(req);
            
            // Ожидание перед сбросом
            if (req.delay > 0) #(req.delay);
            
            // Установка активного уровня сброса
            vif.rst <= cfg.active_level;
            
            // Длительность удержания сброса
            if (req.duration > 0) #(req.duration);
            
            // Снятие сброса (возврат к неактивному уровню)
            vif.rst <= ~cfg.active_level;
            
            seq_item_port.item_done(req);
        end
    endtask: run_phase
endclass
`endif