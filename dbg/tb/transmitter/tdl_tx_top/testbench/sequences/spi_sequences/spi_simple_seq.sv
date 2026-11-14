class spi_simple_seq extends uvm_sequence;
    `uvm_object_utils(spi_simple_seq)

    function new(string name = "spi_simple_seq");
        super.new(name);
    endfunction: new

    tx_regs        reg_block;
    uvm_status_e   status;
    uvm_reg_data_t value;
    uvm_reg        registers[$];

    task pre_body();
        if(!uvm_config_db #(tx_regs)::get(null, "*", "reg_block", reg_block)) begin
            `uvm_fatal(get_name(), "Failed to get reg_block from uvm_config_db")
        end
        reg_block.get_registers(registers);
    endtask

    task body();
        reg_block.reset();
        reg_block.MODE_REG.write(status, 8'hA5);
        reg_block.MODE_REG.read(status, value);
        `uvm_info(get_name(), $sformatf("MODE_REG value: 0x%0h", value), UVM_MEDIUM)

        foreach(registers[i]) begin
            registers[i].read(status, value);
        end
    endtask: body
endclass