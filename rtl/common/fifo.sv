`ifndef FIFO
`define FIFO
module fifo #(
    parameter int WIDTH = 32, // Разрядность данных
    parameter int DEPTH = 16  // Глубина FIFO (должна быть степенью двойки)
)(
    input  logic              clk,
    input  logic              rst_n,
    input  logic              w_en,   // Сигнал записи
    input  logic [WIDTH-1:0]  w_data, // Данные для записи
    input  logic              r_en,   // Сигнал чтения
    output logic [WIDTH-1:0]  r_data, // Данные для чтения
    output logic              full,   // Флаг переполнения
    output logic              empty   // Флаг опустошения
);

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
    assign empty = (wptr == rptr);

    // FIFO полное, если младшие биты адреса равны, а старший (MSB) отличается
    assign full  = (wptr[ADDR_WIDTH] != rptr[ADDR_WIDTH]) && (waddr == raddr);

    // --- Логика записи в память ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr <= '0;
        end 
        else if (w_en && !full) begin
            mem[waddr] <= w_data;
            wptr       <= wptr + 1'b1;
        end
    end

    // --- Логика чтения из памяти ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rptr <= '0;
        end 
        else if (r_en && !empty) begin
            rptr <= rptr + 1'b1;
        end
    end

    // --- Выходные данные (Режим FWFT) ---
    // В данной реализации применен режим First-Word Fall-Through (FWFT):
    // как только данные появляются в FIFO, они сразу видны на шине rdata.
    assign r_data = mem[raddr];

endmodule
`endif