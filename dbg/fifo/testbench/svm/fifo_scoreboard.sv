`ifndef FIFO_SCOREBOARD
`define FIFO_SCOREBOARD
class fifo_scoreboard #(parameter int WIDTH = 8, parameter int DEPTH = 16);
    mailbox #(fifo_transaction#(WIDTH)) mon2scb;
    
    // Внутренняя эталонная очередь (Golden Model)
    typedef logic [WIDTH-1:0] data_t;
    data_t fifo_q[$];
    int error_count = 0;

    function new(mailbox #(fifo_transaction#(WIDTH)) mon2scb);
        this.mon2scb = mon2scb;
    endfunction

    task run();
        forever begin
            fifo_transaction#(WIDTH) tx;
            mon2scb.get(tx);
            
            // 1. Проверяем логику Записи и флаг Full
            if (tx.op == WRITE) begin
                bit expected_full = (fifo_q.size() == DEPTH);
                if (tx.full !== expected_full) begin
                    $error("Time: %0t | ERROR: Full flag mismatch. Expected: %b, Got: %b", $time, expected_full, tx.full);
                    error_count++;
                end
                
                if (!expected_full) begin
                    fifo_q.push_back(tx.data);
                end
            end

            // 2. Проверяем логику Чтения, данные и флаг Empty (режим FWFT)
            if (tx.op == READ) begin
                bit expected_empty = (fifo_q.size() == 0);
                if (tx.empty !== expected_empty) begin
                    $error("Time: %0t | ERROR: Empty flag mismatch. Expected: %b, Got: %b", $time, expected_empty, tx.empty);
                    error_count++;
                end

                if (!expected_empty) begin
                    data_t expected_data = fifo_q.pop_front(); 
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