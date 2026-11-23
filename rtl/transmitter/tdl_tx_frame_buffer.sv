`ifndef TDL_TX_FRAME_BUFFER
`define TDL_TX_FRAME_BUFFER
// Одноэлементный буфер дескрипторов между контроллером и сериализатором.
module tdl_tx_frame_buffer #(
    parameter int DATA_WIDTH = 32,
    parameter int DICT_SIZE  = 256,
    // Ширина индекса словаря; внешний ключ дескриптора всегда 8-битный.
    localparam int KEY_WIDTH = $clog2(DICT_SIZE)
) (
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic                  s_desc_valid,
    output logic                  s_desc_ready,
    input  logic [1:0]            s_desc_type,
    input  logic [7:0]            s_desc_key,
    input  logic [DATA_WIDTH-1:0] s_desc_data,

    output logic                  m_desc_valid,
    input  logic                  m_desc_ready,
    output logic [1:0]            m_desc_type,
    output logic [7:0]            m_desc_key,
    output logic [DATA_WIDTH-1:0] m_desc_data
);

    import tdl_tx_pkg::*;

    // full_q отмечает занятость буфера; payload хранится до следующего push.
    logic                  full_q;
    logic [1:0]            type_q;
    logic [7:0]            key_q;
    logic [DATA_WIDTH-1:0] data_q;
    logic                  push;
    logic                  pop;

    // Пустой буфер принимает данные; полный может принять замену при выдаче.
    assign m_desc_valid = rst_n && full_q;
    assign s_desc_ready = rst_n && (!full_q || m_desc_ready);

    // Передача каждого дескриптора происходит только при valid и ready.
    assign push = s_desc_valid && s_desc_ready;
    assign pop  = m_desc_valid && m_desc_ready;

    assign m_desc_type = type_q;
    assign m_desc_key  = key_q;
    assign m_desc_data = data_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Сброс отменяет ожидающий дескриптор и задаёт безопасный payload.
            full_q <= 1'b0;
            type_q <= FRAME_RAW;
            key_q  <= '0;
            data_q <= '0;
        end
        else begin
            // При push сохраняем новый дескриптор, даже если одновременно
            // выдаётся старый: получатель видит старое значение до фронта.
            if (push) begin
                type_q <= s_desc_type;
                key_q  <= s_desc_key;
                data_q <= s_desc_data;
            end

            // Приоритет push сохраняет занятость при одновременных push/pop.
            if (push)
                full_q <= 1'b1;
            else if (pop)
                full_q <= 1'b0;
        end
    end

`ifndef SYNTHESIS
    // Проверки параметров при запуске моделирования.
    initial begin
        assert (DATA_WIDTH == 32)
            else $error("tdl_tx_frame_buffer requires DATA_WIDTH == 32");
        assert ((DICT_SIZE >= 2) && (DICT_SIZE <= 256))
            else $error("tdl_tx_frame_buffer requires 2 <= DICT_SIZE <= 256");
    end
`endif

endmodule
`endif
