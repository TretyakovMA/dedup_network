class fifo_write_only_generator extends fifo_generator;

    function new(string name, svm_component parent);
        super.new(name, parent);
    endfunction

    // Переопределяем логику генерации
    virtual task run_phase();
        repeat(num_transactions) begin
            fifo_transaction tx = new("tr", this);
            // Кастомизируем рандомизацию: только запись
            assert (tx.randomize() with { op == WRITE; }); 
            gen2drv.put(tx);
        end
        -> done;
    endtask

    static svm_pkg::svm_proxy#(fifo_write_only_generator) p = new("fifo_write_only_generator");
endclass