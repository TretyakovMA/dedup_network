class spi_unmapped_access_seq extends uvm_sequence #(spi_transaction);
    `uvm_object_utils(spi_unmapped_access_seq)

    spi_transaction::spi_command_t op;

    function new(string name = "spi_unmapped_access_seq");
        super.new(name);
    endfunction

    task body();
        spi_transaction req, rsp;
        req = spi_transaction::type_id::create("req");
        start_item(req);
        req.addr = 7'h2c;
        req.op   = op;
        req.data = (op == spi_transaction::WRITE) ? 8'hff : 8'h00;
        finish_item(req);
        get_response(rsp);
        if (op == spi_transaction::READ && rsp.data !== 8'h00)
            `uvm_fatal(get_name(), $sformatf("Unmapped SPI read returned %02h", rsp.data))
    endtask
endclass

class spi_irq_test extends spi_base_test;
    `uvm_component_utils(spi_irq_test)

    localparam uvm_reg_data_t ADDR_ERR = 'h10;
    virtual spi_irq_check_if.monitor irq_vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual spi_irq_check_if.monitor)::get(this, "", "irq_vif", irq_vif))
            `uvm_fatal(get_name(), "IRQ monitor interface is missing")
    endfunction

    task write_reg(uvm_reg rg, uvm_reg_data_t value);
        uvm_status_e status;
        rg.write(status, value, UVM_FRONTDOOR);
        if (status != UVM_IS_OK)
            `uvm_fatal(get_name(), $sformatf("Write to %s failed", rg.get_name()))
    endtask

    task check_irq(uvm_reg_data_t expected_status, logic expected_irq);
        uvm_reg_data_t value;
        uvm_status_e status;
        env.reg_block.INT_STATUS_REG.read(status, value, UVM_FRONTDOOR);
        if (status != UVM_IS_OK || value !== expected_status || irq_vif.irq !== expected_irq)
            `uvm_fatal(get_name(), $sformatf("IRQ status/pin=%02h/%b, expected %02h/%b",
                                           value, irq_vif.irq, expected_status, expected_irq))
    endtask

    task bad_access(spi_transaction::spi_command_t op);
        int unsigned initial_accesses, initial_errors;
        spi_unmapped_access_seq seq;
        initial_accesses = irq_vif.accesses;
        initial_errors   = irq_vif.errors;
        seq = spi_unmapped_access_seq::type_id::create("seq");
        seq.op = op;
        seq.start(env.agent.sequencer);
        repeat (5) @(negedge irq_vif.clk);
        if (irq_vif.accesses != initial_accesses + 1 || irq_vif.errors != initial_errors + 1)
            `uvm_fatal(get_name(), $sformatf("Invalid %s produced %0d accesses and %0d error pulses", op.name(),
                       irq_vif.accesses - initial_accesses, irq_vif.errors - initial_errors))
    endtask

    task main_phase(uvm_phase phase);
        super.main_phase(phase);
        phase.raise_objection(this);
        check_irq(0, 0);
        bad_access(spi_transaction::READ);
        check_irq(ADDR_ERR, 0);
        write_reg(env.reg_block.INT_ENABLE_REG, ADDR_ERR);
        check_irq(ADDR_ERR, 1);
        write_reg(env.reg_block.INT_ENABLE_REG, 0);
        check_irq(ADDR_ERR, 0);
        write_reg(env.reg_block.INT_ENABLE_REG, ADDR_ERR);
        write_reg(env.reg_block.INT_STATUS_REG, 0);
        check_irq(ADDR_ERR, 1);
        write_reg(env.reg_block.INT_STATUS_REG, ADDR_ERR);
        check_irq(0, 0);

        bad_access(spi_transaction::WRITE);
        check_irq(ADDR_ERR, 1);
        write_reg(env.reg_block.INT_STATUS_REG, ADDR_ERR);
        check_irq(0, 0);
        if (irq_vif.accesses != 16 || irq_vif.errors != 2)
            `uvm_fatal(get_name(), $sformatf("Expected 16 CSR accesses and 2 error pulses, got %0d/%0d",
                                           irq_vif.accesses, irq_vif.errors))
        `uvm_info(get_name(), "Checked SPI IRQ masking, W1C and exactly one event per unmapped access", UVM_LOW)
        phase.drop_objection(this);
    endtask
endclass
