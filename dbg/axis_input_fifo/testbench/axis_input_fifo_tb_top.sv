
`define GREEN_STR(str) ($sformatf("\033[32m%s\033[0m", str))
`define RED_STR(str) ($sformatf("\033[31;1m%s\033[0m", str))

module axis_input_fifo_tb_top;

    enum {
        WIDTH      = 8, 
        DEPTH      = 16,
        CLK_PERIOD = 20,
        RESET_TIME = 40
    } param_e;

    

    logic clk;
    logic rst_n;

    axis_if #(WIDTH) axis_bus (clk, rst_n);
    fifo_if #(WIDTH) fifo_bus (clk, rst_n);

    
    virtual axis_if#(WIDTH)   axis_vif = axis_bus.tb_driver;
    virtual fifo_if#(WIDTH)   fifo_vif = fifo_bus.axis_tb_driver;


    typedef logic[WIDTH-1:0] data_t;

    int error_count = 0;




    data_t fifo_q[$];

    function bit is_fifo_empty();
        return fifo_q.size() == 0;
    endfunction

    function bit is_fifo_full();
        return fifo_q.size() == DEPTH;
    endfunction

    function void push_fifo(data_t data);
        if(is_fifo_full()) begin
            $display("Time: %0t, FIFO is full. Cannot push data: %b", $time, data);
            return;
        end
        fifo_q.push_back(data);
    endfunction

    function data_t pop_fifo();
        if(is_fifo_empty()) begin
            $display("Time: %0t, FIFO is empty. Cannot pop data.", $time);
            return '0;
        end
        return fifo_q.pop_front();
    endfunction


    axis_input_fifo #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) dut (
        .s_axis(axis_bus),
        .full  (fifo_bus.full),
        .r_data(fifo_bus.r_data),
        .r_en  (fifo_bus.r_en),
        .empty (fifo_bus.empty)
    );

    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end



    task initialize();
        rst_n      = 0;

        axis_vif.tvalid = 0;
        axis_vif.tdata  = 0;
        axis_vif.tlast  = 0;
        fifo_vif.r_en   = 0;

        #(RESET_TIME);
        rst_n = 1;
        @(axis_vif.driver_cb); 
    endtask



    task timeout();
        #10000;
    endtask



    task write(input data_t data);
        // 1. Запоминаем ожидаемый флаг ДО того, как запись применится в DUT
        automatic bit expected_full = is_fifo_full(); 
        
        // 2. Выставляем данные и разрешение строго через клокблок (<=)
        axis_vif.driver_cb.tdata  <= data;
        axis_vif.driver_cb.tvalid <= 1;
        
        $display("Time: %0t, Writing data: %b to FIFO", $time, data);
        
        // 3. Ждем фронта (клокблок сэмплирует full за 1нс до этой точки)
        @(axis_vif.driver_cb);
        
        // 4. Проверяем флаг full через клокблок
        if(fifo_vif.axis_cb.full !== expected_full) begin
            $error(`RED_STR("Time: %0t, ERROR: Full flag mismatch. Expected: %b, Got: %b"), 
                    $time, expected_full, fifo_vif.axis_cb.full);
            error_count++;
        end 
        
        // 5. Только теперь обновляем локальную модель и снимаем w_en
        push_fifo(data);
        axis_vif.driver_cb.tvalid <= 0;
    endtask

    task read();
        automatic bit expected_empty = is_fifo_empty();
        automatic data_t expected_data;
        
        // Если FIFO не пуст, подглядываем (peek) данные на вершине очереди, 
        // но пока не удаляем их из модели
        if (!expected_empty) begin
            expected_data = fifo_q[0]; 
        end
        
        // 1. Выставляем запрос на чтение через клокблок
        fifo_vif.axis_cb.r_en <= 1;
        
        // 2. Ждем фронта (клокблок сэмплирует сигналы за 1нс до этой точки)
        @(fifo_vif.axis_cb);
        
        // 3. Проверяем флаг empty (он отражает состояние ДО этого чтения)
        if(fifo_vif.axis_cb.empty !== expected_empty) begin
            $error(`RED_STR("Time: %0t, ERROR: Empty flag mismatch. Expected: %b, Got: %b"), 
                    $time, expected_empty, fifo_vif.axis_cb.empty);
            error_count++;
        end
        
        // 4. Проверяем данные (для FWFT-режима они уже были на шине к моменту сэмплирования)
        if(!expected_empty) begin
            if(fifo_vif.axis_cb.r_data !== expected_data) begin
                $error(`RED_STR("Time: %0t, ERROR: Read data %b does not match expected data %b"), 
                        $time, fifo_vif.axis_cb.r_data, expected_data);
                error_count++;
            end 
            else begin
                $display("Time: %0t, Read data %b matches expected data %b", 
                        $time, fifo_vif.axis_cb.r_data, expected_data);
            end
            // 5. И только после успешной проверки удаляем элемент из модели
            void'(pop_fifo()); 
        end
        
        // 6. Снимаем запрос чтения
        fifo_vif.axis_cb.r_en <= 0;
    endtask


    task rw_test();
        // Тестирование записи и чтения данных
        repeat (10) begin
            write($urandom);
            read();
        end
    endtask

    task test_overflow_underflow();
        // Тестирование переполнения FIFO
        repeat (DEPTH + 2) begin
            write($urandom);
        end

        // Тестирование опустошения FIFO
        repeat (DEPTH) begin
            read();
        end
    endtask

    task rand_op_test();
        // Случайные операции записи и чтения
        repeat (200) begin
            if ($urandom_range(1)) begin
                write($urandom);
            end 
            else begin
                read();
            end
        end
    endtask

    task test_top();
        initialize();

        rw_test();
        test_overflow_underflow();
        rand_op_test();
    endtask



    initial begin: run_test
        $timeformat(-9, 0, " ns", 5);
        fork
            test_top();
            timeout();
        join_any

        $finish;
    end: run_test

    final begin
        if (error_count == 0) begin
            $display(`GREEN_STR("All tests passed successfully."));
        end 
        else begin
            $display(`RED_STR("Test completed with %0d errors."), error_count);
        end
    end
endmodule