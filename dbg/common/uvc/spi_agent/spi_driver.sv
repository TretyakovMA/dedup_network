`ifndef SPI_DRIVER
`define SPI_DRIVER
class spi_driver extends uvm_driver #(spi_transaction);
    `uvm_component_utils(spi_driver)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction: new

    `uvm_analysis_imp_decl(_rsp)
    uvm_analysis_imp_rsp#(spi_transaction, spi_driver) rsp_ap;

    virtual spi_if.master  vif;
    spi_transaction        transaction;
    spi_config             cfg;
    realtime               sclk_half_period;

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        rsp_ap = new("rsp_ap", this);
    endfunction


    task wait_initial_reset();
        @(posedge vif.clk iff vif.rst_n == 1);
    endtask: wait_initial_reset

    task post_configure_phase(uvm_phase phase);
        sclk_half_period = cfg.get_sclk_half_period();
    endtask: post_configure_phase


    task edge_sck();
        if(cfg.cpol)
            @(posedge vif.sclk);
        else
            @(negedge vif.sclk);
    endtask: edge_sck

    task wait_sck_delay();
        if(cfg.cpha) begin
            #(sclk_half_period);
        end
    endtask: wait_sck_delay


    function void write_rsp(spi_transaction rsp);
        `uvm_info(get_type_name(), {"get rsp_tr: ", rsp.convert2string()}, UVM_FULL)

        rsp.set_id_info(transaction);
        seq_item_port.item_done(rsp);
    endfunction: write_rsp

    

    task generate_sclk();
        for(int i = 0; i < 8; i++) begin
            #(sclk_half_period);
            vif.sclk <= ~vif.sclk;
            #(sclk_half_period);
            vif.sclk <= ~vif.sclk;
        end
    endtask: generate_sclk

    task drive_byte(bit[7:0] data);
        foreach(data[i]) begin
            vif.mosi <= data[i];
            `uvm_info(get_name(), {$sformatf("Set signal:mosi = %b, i = %d", data[i], i)}, UVM_HIGH)
            edge_sck();
            wait_sck_delay();
        end
    endtask: drive_byte

    task send_byte(bit[7:0] data);
        fork
            drive_byte(data);
            generate_sclk();
        join
    endtask



    // Основная задача для отправки данных через интерфейс
    task drive_transaction(spi_transaction tr);
        vif.cs_n <= 0;
        send_byte({tr.addr, tr.op});
        send_byte({tr.data});
        vif.cs_n <= 1; 
        #(sclk_half_period);
    endtask: drive_transaction






    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if(!uvm_config_db#(virtual spi_if.master)::get(this, "", "vif", vif))
            `uvm_fatal(get_name(), "Faild to get interface")
            
    endfunction: connect_phase

    task reset_phase(uvm_phase phase);
        super.reset_phase(phase);
        vif.mosi = 0;
        vif.cs_n = 1;
        vif.sclk = 0;
    endtask: reset_phase

    



    task main_phase(uvm_phase phase);
        
        wait_initial_reset();

        forever begin
            seq_item_port.get_next_item(transaction);
            drive_transaction(transaction);
            `uvm_info(get_name(), {"Send transaction: ", transaction.convert2string()}, UVM_HIGH)
    
            if(transaction.op == spi_transaction::WRITE) begin
                seq_item_port.item_done(transaction);
            end
        end
        
    endtask: main_phase


endclass
`endif
