`ifndef SPI_BASE_MONITOR
`define SPI_BASE_MONITOR
virtual class spi_base_monitor extends uvm_monitor;
    `uvm_component_utils(spi_base_monitor)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    virtual spi_if.slave  vif;

    spi_transaction   transaction;
    spi_config        cfg;

    realtime          delay;

    uvm_analysis_port #(spi_transaction) ap;



    task wait_initial_reset();
        @(posedge vif.clk iff vif.rst_n == 1);
    endtask: wait_initial_reset



    // Дополнительные задачи для определение момента мониторинга
    task edge_sck();
        if(cfg.cpol) @(negedge vif.sclk);
        else         @(posedge vif.sclk);
    endtask: edge_sck

    task wait_sck_delay();
        if(cfg.cpha) #(delay);
    endtask: wait_sck_delay

    


    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
    endfunction: build_phase


    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        if(!uvm_config_db#(virtual spi_if.slave)::get(this, "", "vif", vif))
            `uvm_fatal(get_name(), "Faild to get interface")

    endfunction: connect_phase


    task post_configure_phase(uvm_phase phase);
        delay = cfg.get_sclk_half_period();
    endtask: post_configure_phase

    task collect_mosi(output bit[7:0] data);
        for (int i = 0; i < 8; i++) begin
            edge_sck();
            wait_sck_delay();

            if($isunknown(vif.mosi)) begin
                `uvm_error(get_name(), "MOSI signal is unknown")
            end
            data[7 - i] = vif.mosi;
            `uvm_info(get_name(), $sformatf("mosi = %b", data[7-i]), UVM_HIGH)
        end
    endtask

    task collect_miso(output bit[7:0] data);
        for (int i = 0; i < 8; i++) begin
            edge_sck();
            wait_sck_delay();

            if($isunknown(vif.miso)) begin
                `uvm_error(get_name(), "MISO signal is unknown")
            end
            data[7 - i] = vif.miso;
            `uvm_info(get_name(), $sformatf("miso = %b", data[7-i]), UVM_HIGH)
        end
    endtask

    pure virtual task collect_transaction_data(spi_transaction tr);

    virtual function bit select_transaction(spi_transaction tr);
        return 0;
    endfunction

    task main_phase(uvm_phase phase);
        super.main_phase(phase);

        wait_initial_reset();

        forever begin
            bit[7:0] val;
            transaction = spi_transaction::type_id::create("tr");

            collect_mosi(val);
            transaction.addr = val[7:1];
            transaction.op = spi_transaction::spi_command_t'(val[0]);

            if(select_transaction(transaction)) begin
                collect_transaction_data(transaction);

                `uvm_info(get_name(), {"Get transaction: ", transaction.convert2string()}, UVM_MEDIUM)
                ap.write(transaction);    
            end
            else begin
                repeat(8) begin
                    edge_sck();
                    wait_sck_delay();
                end
            end
        end
    endtask: main_phase

endclass
`endif