`ifndef AXIS_INPUT_FIFO
`define AXIS_INPUT_FIFO
module axis_input_fifo #(
    parameter int WIDTH = 32, // Разрядность входных данных
    parameter int DEPTH = 16  // Глубина FIFO
)(
    // Порт AXI-Stream Slave
    axis_if.slave s_axis,

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
        .clk   (s_axis.clk   ),
        .rst_n (s_axis.rst_n ),
        .w_en  (s_axis.tvalid),
        .w_data(s_axis.tdata ),
        .r_en  (r_en         ),
        .r_data(r_data       ),
        .full  (full         ), 
        .empty (empty        )
    );

    assign s_axis.tready = !full;


endmodule
`endif