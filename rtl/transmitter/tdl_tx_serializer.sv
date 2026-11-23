`ifndef TDL_TX_SERIALIZER
`define TDL_TX_SERIALIZER
// Преобразует дескриптор RAW, KEY или SYNC в однобитный кадр на выходе SDR.
module tdl_tx_serializer #(
    parameter int DATA_WIDTH = 32,
    parameter int DICT_SIZE  = 256
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  tx_en,
    input  logic [15:0]           sdr_clk_div,
    output logic                  busy,
    output logic                  frame_done,
    output logic [1:0]            frame_done_type,

    input  logic                  desc_valid,
    output logic                  desc_ready,
    input  logic [1:0]            desc_type,
    input  logic [7:0]            desc_key,
    input  logic [DATA_WIDTH-1:0] desc_data,

    output logic                  sdr_data,
    output logic                  sdr_clk,
    input  logic                  sdr_ready
);

    import tdl_tx_pkg::*;

    typedef enum logic [1:0] {
        ST_IDLE,
        ST_ACTIVE,
        ST_LAST_HIGH,
        ST_ERROR
    } state_t;

    state_t state;

    // Поля кадра и делитель фиксируются вместе в момент приёма дескриптора.
    logic [1:0]            type_q;
    logic [7:0]            key_q;
    logic [DATA_WIDTH-1:0] data_q;
    logic [15:0]           div_q;
    logic [2:0]            byte_index_q;
    logic [2:0]            last_byte_index;
    logic [2:0]            next_byte_index;
    logic [2:0]            bit_index_q;
    logic [7:0]            current_byte;
    logic [7:0]            next_byte;
    logic                  desc_accept;
    logic                  desc_is_valid;
    logic                  timing_active;
    logic                  allow_rise;
    logic                  rise_ce;
    logic                  fall_ce;

    // Кадр начинается заголовком, за которым идут ключ для KEY/SYNC и слово для RAW/SYNC.
    function automatic logic [7:0] frame_byte(
        input logic [1:0]            frame_type,
        input logic [2:0]            index,
        input logic [7:0]            key,
        input logic [DATA_WIDTH-1:0] data
    );
        begin
            frame_byte = 8'h00;
            case (frame_type)
                FRAME_RAW: begin
                    case (index)
                        3'd0: frame_byte = 8'hA1;
                        3'd1: frame_byte = data[31:24];
                        3'd2: frame_byte = data[23:16];
                        3'd3: frame_byte = data[15:8];
                        3'd4: frame_byte = data[7:0];
                        default: frame_byte = 8'h00;
                    endcase
                end
                FRAME_KEY: begin
                    case (index)
                        3'd0: frame_byte = 8'hB2;
                        3'd1: frame_byte = key;
                        default: frame_byte = 8'h00;
                    endcase
                end
                FRAME_SYNC: begin
                    case (index)
                        3'd0: frame_byte = 8'hC3;
                        3'd1: frame_byte = key;
                        3'd2: frame_byte = data[31:24];
                        3'd3: frame_byte = data[23:16];
                        3'd4: frame_byte = data[15:8];
                        3'd5: frame_byte = data[7:0];
                        default: frame_byte = 8'h00;
                    endcase
                end
                default: frame_byte = 8'h00;
            endcase
        end
    endfunction

    // Свободный сериализатор может принять дескриптор и ждать разрешения линии.
    assign desc_ready = rst_n && tx_en && (state == ST_IDLE);
    assign desc_accept = desc_valid && desc_ready;
    assign busy = (state != ST_IDLE);

    // После последнего подъёма новые биты запрещены, но высокая фаза ещё заканчивается.
    assign timing_active = (state == ST_ACTIVE) || (state == ST_LAST_HIGH);
    assign allow_rise = tx_en && sdr_ready && (state == ST_ACTIVE);

    always_comb begin
        desc_is_valid = 1'b1;
        case (desc_type)
            FRAME_RAW: desc_is_valid = 1'b1;
            FRAME_KEY,
            FRAME_SYNC: desc_is_valid = (desc_key < DICT_SIZE);
            default: desc_is_valid = 1'b0;
        endcase
    end

    always_comb begin
        last_byte_index = 3'd0;
        case (type_q)
            FRAME_RAW:  last_byte_index = 3'd4;
            FRAME_KEY:  last_byte_index = 3'd1;
            FRAME_SYNC: last_byte_index = 3'd5;
            default:    last_byte_index = 3'd0;
        endcase

        next_byte_index = byte_index_q + 3'd1;
        current_byte = frame_byte(type_q, byte_index_q, key_q, data_q);
        next_byte = frame_byte(type_q, next_byte_index, key_q, data_q);
    end

    tdl_sdr_timing u_tdl_sdr_timing (
        .clk           (clk),
        .rst_n         (rst_n),
        .timing_active (timing_active),
        .timing_div    (div_q),
        .allow_rise    (allow_rise),
        .sdr_clk       (sdr_clk),
        .rise_ce       (rise_ce),
        .fall_ce       (fall_ce)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            type_q          <= FRAME_RAW;
            key_q           <= 8'd0;
            data_q          <= '0;
            div_q           <= 16'd0;
            byte_index_q    <= 3'd0;
            bit_index_q     <= 3'd7;
            sdr_data        <= 1'b0;
            frame_done      <= 1'b0;
            frame_done_type <= FRAME_RAW;
        end
        else begin
            frame_done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (desc_accept) begin
                        if (desc_is_valid) begin
                            type_q       <= desc_type;
                            key_q        <= desc_key;
                            data_q       <= desc_data;
                            div_q        <= sdr_clk_div;
                            byte_index_q <= 3'd0;
                            bit_index_q  <= 3'd7;
                            // Старший бит всех трёх заголовков равен 1. Данные выставляются до первого подъёма SDR.
                            case (desc_type)
                                FRAME_RAW:  sdr_data <= 1'b1;
                                FRAME_KEY:  sdr_data <= 1'b1;
                                FRAME_SYNC: sdr_data <= 1'b1;
                                default:    sdr_data <= 1'b0;
                            endcase
                            state <= ST_ACTIVE;
                        end
                        else begin
`ifndef SYNTHESIS
                            $error("tdl_tx_serializer accepted an invalid descriptor");
`endif
                            state <= ST_ERROR;
                        end
                    end
                end

                ST_ACTIVE: begin
                    if (rise_ce && (byte_index_q == last_byte_index) &&
                        (bit_index_q == 3'd0)) begin
                        state <= ST_LAST_HIGH;
                    end

                    // После спада выставляем следующий бит, чтобы данные были стабильны на подъёме.
                    if (fall_ce) begin
                        if (bit_index_q == 3'd0) begin
                            byte_index_q <= next_byte_index;
                            bit_index_q  <= 3'd7;
                            sdr_data     <= next_byte[7];
                        end
                        else begin
                            bit_index_q <= bit_index_q - 3'd1;
                            sdr_data    <= current_byte[bit_index_q - 3'd1];
                        end
                    end
                end

                ST_LAST_HIGH: begin
                    if (fall_ce) begin
                        state           <= ST_IDLE;
                        // Кадр завершён только после последнего спада. Тип сохраняется для статистики.
                        frame_done      <= 1'b1;
                        frame_done_type <= type_q;
                    end
                end

                ST_ERROR: begin
                    state <= ST_ERROR;
                end

                default: state <= ST_ERROR;
            endcase
        end
    end

`ifndef SYNTHESIS
    // Проверки параметров при запуске моделирования.
    initial begin
        assert (DATA_WIDTH == 32)
            else $error("tdl_tx_serializer requires DATA_WIDTH == 32");
        assert ((DICT_SIZE >= 2) && (DICT_SIZE <= 256))
            else $error("tdl_tx_serializer requires 2 <= DICT_SIZE <= 256");
    end
`endif

endmodule
`endif
