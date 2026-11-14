`ifndef TX_BASE_TEST
`define TX_BASE_TEST
class tx_base_test extends uvm_test;
    `uvm_component_utils(tx_base_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    spi_config     cfg;
    tx_env         env;

    custom_report_server my_server;


    virtual function void adjust_spi_config();
        return;
    endfunction: adjust_spi_config




    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        my_server = new();
		uvm_report_server::set_server(my_server);

        cfg = spi_config::type_id::create("cfg");
        uvm_config_db #(spi_config)::set(null, "*", "spi_config", cfg);
        env = tx_env::type_id::create("env", this);
    endfunction: build_phase

    virtual function void start_of_simulation_phase(uvm_phase phase);
        super.start_of_simulation_phase(phase);

        uvm_top.print_topology();
    endfunction: start_of_simulation_phase
    

    virtual task main_phase(uvm_phase phase);
        super.main_phase(phase);
        phase.phase_done.set_drain_time(this, 500);
    endtask: main_phase

    virtual function void report_phase(uvm_phase phase);
        uvm_report_server server = uvm_report_server::get_server();
        
        if(server.get_severity_count(UVM_ERROR) > 0 || server.get_severity_count(UVM_FATAL) > 0) begin
            `uvm_error(get_name(), {"\n",
                "* * * * * * * * * * * * * * * * * * * *\n",
                "* * * * * * * TEST FAILED * * * * * * *\n",
                "* * * * * * * * * * * * * * * * * * * *"
            })
        end
        else begin
            `uvm_info(get_name(), {"\n",
                "* * * * * * * * * * * * * * * * * * * *\n",
                "* * * * * * * TEST PASSED * * * * * * *\n",
                "* * * * * * * * * * * * * * * * * * * *"
            }, UVM_LOW)
        end
    endfunction: report_phase

endclass
`endif
