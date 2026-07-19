`ifndef FIFO_ENVIRONMENT
`define FIFO_ENVIRONMENT

typedef svm_sequencer#(fifo_transaction) fifo_sequencer;

class fifo_environment extends svm_component;
    `svm_component_utils(fifo_environment)
    // Компоненты тестбенча
    fifo_driver        drv;
    fifo_monitor       mon;
    fifo_scoreboard    scb;
    fifo_sequencer     seqr;
    

    // Почтовые ящики для связи
    mailbox_t mon2scb;

    

    function new(string name, svm_component parent);
        super.new(name, parent);
    endfunction

    


    function void build_phase();
        mon2scb  = new(1);

        drv = fifo_driver::type_id::create("drv", this);
        mon = fifo_monitor::type_id::create("mon", this);
        scb = fifo_scoreboard::type_id::create("scb", this);

        seqr = new("seqr", this);
        
    endfunction


    function void connect_phase();
        // Связываем компоненты через почтовые ящики
        
        drv.seq_item_mailbox = seqr.seq_item_mailbox;
        mon.mon2scb = mon2scb;
        scb.mon2scb = mon2scb;
    endfunction



    task timeout();
        #10000;
        $fatal("\033[31;1m[TIMEOUT] Time: %t Test exceeded maximum execution time limit!\033[0m", $time);
    endtask


    // Вынос логики отчета в отдельную функцию для чистоты кода
    function void report_results();
        if (scb.error_count == 0) begin
            $display("\033[32m[TEST PASSED] All operations verified successfully!\033[0m");
        end 
        else begin
            $display("\033[31;1m[TEST FAILED] Verification finished with %0d errors\033[0m", 
                     scb.error_count);
        end
    endfunction

endclass
`endif