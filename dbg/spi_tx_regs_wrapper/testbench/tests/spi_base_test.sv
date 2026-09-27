`ifndef SPI_BASE_TEST
`define SPI_BASE_TEST
class spi_base_test extends uvm_test;
    `uvm_component_utils(spi_base_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    spi_config     cfg;
    spi_env        env;

    custom_report_server my_server;

    clock_uvc_config clk_cfg;
    reset_uvc_config rst_cfg;

    start_clock_seq start_clk_seq;
    reset_seq       rst_seq;


    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        my_server = new();
		uvm_report_server::set_server(my_server);

        cfg = spi_config::type_id::create("cfg");

        if(!uvm_config_db#(clock_uvc_config)::get(this, "", "clk_config", clk_cfg)) begin
            `uvm_fatal(get_name(), "Failed to get clock config")
        end
        if(!uvm_config_db#(reset_uvc_config)::get(this, "", "rst_config", rst_cfg)) begin
            `uvm_fatal(get_name(), "Failed to get reset config")
        end

        cfg.clk_period = clk_cfg.get_period();

        uvm_config_db #(spi_config)::set(null, "*", "spi_config", cfg);
        env         = spi_env::type_id::create("env", this);
        env.clk_cfg = clk_cfg;
        env.rst_cfg = rst_cfg;
    endfunction: build_phase

    

    virtual function void start_of_simulation_phase(uvm_phase phase);
        super.start_of_simulation_phase(phase);

        uvm_top.print_topology();
    endfunction: start_of_simulation_phase

    task run_phase(uvm_phase phase);
        start_clk_seq = start_clock_seq::type_id::create("start_clk_seq");
        start_clk_seq.start(env.clk_agent.sequencer);
    endtask

    task reset_phase(uvm_phase phase);
        rst_seq = reset_seq::type_id::create("rst_seq");
        rst_seq.delay_time = 0;
        rst_seq.duration_time = cfg.get_clk_period() * 10;
        rst_seq.start(env.rst_agent.sequencer);
    endtask
    

    virtual task main_phase(uvm_phase phase);
        super.main_phase(phase);
        phase.phase_done.set_drain_time(this, 500);
    endtask: main_phase

    virtual function void report_phase(uvm_phase phase);
        uvm_report_server server = uvm_report_server::get_server();
        
        if(server.get_severity_count(UVM_ERROR) > 0 || server.get_severity_count(UVM_FATAL) > 0) begin
            `uvm_error(get_name(), {
                "* * * * * * * * * * * * * * * * * * * *\n",
                "* * * * * * * TEST FAILED * * * * * * *\n",
                "* * * * * * * * * * * * * * * * * * * *"
            })
        end
        else begin
            `uvm_info({get_name(), " mark_green"}, {
                "* * * * * * * * * * * * * * * * * * * *\n",
                "* * * * * * * TEST PASSED * * * * * * *\n",
                "* * * * * * * * * * * * * * * * * * * *"
            }, UVM_LOW)
        end
    endfunction: report_phase

endclass
`endif
