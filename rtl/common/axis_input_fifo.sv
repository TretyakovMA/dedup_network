`ifndef AXIS_INPUT_FIFO
`define AXIS_INPUT_FIFO
// Входной AXI-Stream FIFO с выдачей головного слова до чтения (FWFT).
module axis_input_fifo #(
    parameter int WIDTH = 32, // Разрядность входных данных
    parameter int DEPTH = 16  // Глубина FIFO
)(
    input  logic                  clk,
    input  logic                  rst_n,

    // Порт AXI-Stream Slave
    input  logic [WIDTH-1:0]      tdata,
    input  logic                  tvalid,
    output logic                  tready,

    // Выходной интерфейс чтения для FSM кодера передатчика
    input  logic                  r_en,   // Сигнал чтения
    output logic [WIDTH-1:0]      r_data, // Выходные 32-битные данные
    output logic                  empty,  // Флаг отсутствия данных
    output logic                  full    // Флаг переполнения
);

    // Внутреннее FIFO блокирует запись при full, поэтому push соответствует tvalid && tready.
    fifo #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) fifo_inst (
        .clk   (clk   ),
        .rst_n (rst_n ),
        .w_en  (tvalid),
        .w_data(tdata ),
        .r_en  (r_en  ),
        .r_data(r_data),
        .full  (full  ),
        .empty (empty )
    );

    // При полном FIFO одновременное чтение освобождает место для следующего такта.
    assign tready = !full;

`ifndef SYNTHESIS
    // Проверки параметров при запуске моделирования.
    initial begin
        assert (WIDTH > 0)
            else $error("axis_input_fifo requires WIDTH > 0");
        assert ((DEPTH >= 2) && ((DEPTH & (DEPTH - 1)) == 0))
            else $error("axis_input_fifo requires DEPTH to be a power of two >= 2");
    end
`endif

endmodule
`endif
