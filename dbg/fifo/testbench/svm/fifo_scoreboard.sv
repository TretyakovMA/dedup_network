`ifndef FIFO_SCOREBOARD
`define FIFO_SCOREBOARD
class fifo_scoreboard;
    mailbox_t mon2scb;
    
    
    //data_t fifo_q[$];
    fifo_ref_model#(16) ref_model;
    int error_count = 0;

    function new(mailbox_t mon2scb);
        this.mon2scb = mon2scb;
        ref_model = new();
    endfunction

    task run();
        forever begin
            fifo_transaction tx;
            mon2scb.get(tx);
            
            // 1. Проверяем логику Записи и флаг Full
            if (tx.op == WRITE) begin
                bit expected_full = ref_model.is_full();
                if (tx.full !== expected_full) begin
                    $error("Time: %0t | ERROR: Full flag mismatch. Expected: %b, Got: %b", $time, expected_full, tx.full);
                    error_count++;
                end
                
                if (!expected_full) begin
                    ref_model.push_data(tx.data);
                end
            end

            // 2. Проверяем логику Чтения, данные и флаг Empty (режим FWFT)
            if (tx.op == READ) begin
                bit expected_empty = ref_model.is_empty();
                if (tx.empty !== expected_empty) begin
                    $error("Time: %0t | ERROR: Empty flag mismatch. Expected: %b, Got: %b", $time, expected_empty, tx.empty);
                    error_count++;
                end

                if (!expected_empty) begin
                    data_t expected_data = ref_model.pop_data();
                    // Для FWFT режима данные проверяются в момент r_en (они уже на шине)
                    if (tx.data !== expected_data) begin
                        $error("Time: %0t | ERROR: Read data %b mismatch. Expected: %b", $time, tx.data, expected_data);
                        error_count++;
                    end
                end
            end
        end
    endtask
endclass
`endif