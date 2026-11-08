`ifndef AXIS_INPUT_FIFO
`define AXIS_INPUT_FIFO
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

    assign tready = !full;


endmodule
`endif