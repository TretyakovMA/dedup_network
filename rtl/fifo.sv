module fifo #(
    parameter int DEPTH = 16  // Глубина FIFO (должна быть степенью двойки)
)(
    fifo_if.rtl io
);

    localparam int WIDTH = $bits(io.w_data);

    // Вычисляем разрядность адреса
    localparam int ADDR_WIDTH = $clog2(DEPTH);

    // Двумерный массив для хранения данных (память FIFO)
    logic [WIDTH-1:0] mem [DEPTH];

    // Указатели чтения и записи (с дополнительным битом переполнения)
    logic [ADDR_WIDTH:0] wptr;
    logic [ADDR_WIDTH:0] rptr;

    // Выделяем чистые индексы для адресации памяти (младшие биты)
    logic [ADDR_WIDTH-1:0] waddr;
    logic [ADDR_WIDTH-1:0] raddr;

    assign waddr = wptr[ADDR_WIDTH-1:0];
    assign raddr = rptr[ADDR_WIDTH-1:0];

    // --- Логика флагов Full и Empty ---
    // FIFO пустое, если указатели записи и чтения полностью равны
    assign io.empty = (wptr == rptr);

    // FIFO полное, если младшие биты адреса равны, а старший (MSB) отличается
    assign io.full  = (wptr[ADDR_WIDTH] != rptr[ADDR_WIDTH]) && (waddr == raddr);

    // --- Логика записи в память ---
    always_ff @(posedge io.clk or negedge io.rst_n) begin
        if (!io.rst_n) begin
            wptr <= '0;
        end 
        else if (io.w_en && !io.full) begin
            mem[waddr] <= io.w_data;
            wptr       <= wptr + 1'b1;
        end
    end

    // --- Логика чтения из памяти ---
    always_ff @(posedge io.clk or negedge io.rst_n) begin
        if (!io.rst_n) begin
            rptr <= '0;
        end 
        else if (io.r_en && !io.empty) begin
            rptr <= rptr + 1'b1;
        end
    end

    // --- Выходные данные (Режим FWFT) ---
    // В данной реализации применен режим First-Word Fall-Through (FWFT):
    // как только данные появляются в FIFO, они сразу видны на шине rdata.
    assign io.r_data = mem[raddr];

endmodule