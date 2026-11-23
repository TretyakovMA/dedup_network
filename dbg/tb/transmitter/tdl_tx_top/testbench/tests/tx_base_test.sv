`ifndef TX_BASE_TEST
`define TX_BASE_TEST
class tx_base_test extends uvm_test;
    `uvm_component_utils(tx_base_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    tx_config      cfg;
    tx_env         env;

    custom_report_server my_server;

    start_clock_seq start_clk_seq;
    reset_seq       rst_seq;

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        my_server = new();
		uvm_report_server::set_server(my_server);

        cfg = tx_config::type_id::create("cfg");

        if(!uvm_config_db#(clock_uvc_config)::get(this, "", "clk_config", cfg.clk_cfg))
            `uvm_fatal(get_name(), "Failed to get clock config")
        if(!uvm_config_db#(reset_uvc_config)::get(this, "", "rst_config", cfg.rst_cfg))
            `uvm_fatal(get_name(), "Failed to get reset config")

        cfg.spi_agent_cfg.clk_period = cfg.clk_cfg.get_period();
        cfg.spi_agent_cfg.prer = 2;
        uvm_config_db #(tx_config)::set(null, "*", "tx_config", cfg);
        env = tx_env::type_id::create("env", this);
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
        rst_seq.duration_time = cfg.spi_agent_cfg.clk_period * 4;
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
