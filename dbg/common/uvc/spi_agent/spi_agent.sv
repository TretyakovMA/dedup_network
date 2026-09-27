`ifndef SPI_AGENT
`define SPI_AGENT
class spi_agent extends uvm_agent;
    `uvm_component_utils(spi_agent)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    typedef uvm_sequencer #(spi_transaction) spi_sequencer;

    spi_driver       driver;
    spi_sequencer    sequencer;
    spi_monitor      monitor;
    

    spi_config       cfg;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if(!uvm_config_db#(spi_config)::get(this, "", "spi_config", cfg))
            `uvm_fatal(get_type_name(), "Faild to get config")

        if(cfg.is_active == UVM_ACTIVE) begin
            driver     = spi_driver::type_id::create("driver", this);
            sequencer  = spi_sequencer::type_id::create("sequencer", this);
            driver.cfg = cfg;
        end

        monitor     = spi_monitor::type_id::create("monitor", this);
        monitor.cfg = cfg;
    endfunction: build_phase

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if(cfg.is_active == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
            monitor.rsp_ap.connect(driver.rsp_ap);
        end
    endfunction: connect_phase


endclass
`endif
