// ============================================================================
// Модуль FSM-контроллера передатчика дедупликатора
// Формирует кадры RAW, KEY и SYNC в зависимости от результатов поиска
// ============================================================================
module dedup_tx_controller #(
    parameter int DATA_WIDTH = 32,
    parameter int KEY_WIDTH  = 8,
    
    // Префиксы/Типы заголовков кадров (1 байт)
    parameter logic [7:0] HDR_RAW  = 8'hA1, // RAW:  [HDR] + [4B DATA]
    parameter logic [7:0] HDR_KEY  = 8'hB2, // KEY:  [HDR] + [1B KEY]
    parameter logic [7:0] HDR_SYNC = 8'hC3  // SYNC: [HDR] + [4B DATA] + [1B KEY]
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // ------------------------------------------------------------------------
    // Интерфейс входного FIFO 
    // ------------------------------------------------------------------------
    input  logic                    fifo_empty,
    input  logic [DATA_WIDTH-1:0]   fifo_rdata,
    output logic                    fifo_rd_en,

    // ------------------------------------------------------------------------
    // Интерфейс от модуля словаря / результата поиска
    // ------------------------------------------------------------------------
    // Флаг нахождения текущего слова в массиве дедупликации
    input  logic                    dict_hit,
    // Индекс (Key) текущего слова в массиве дедупликации
    input  logic [KEY_WIDTH-1:0]    dict_key,
    // Флаг того, что данное слово будет добавлено в массив дедупликации
    input  logic                    force_sync,

    // ------------------------------------------------------------------------
    // Выходной AXI-Stream интерфейс (Master modport)
    // ------------------------------------------------------------------------
    axis_if.master                  m_axis
);

    // Типы кадров
    typedef enum logic [1:0] {
        FRAME_RAW  = 2'b00,
        FRAME_KEY  = 2'b01,
        FRAME_SYNC = 2'b10
    } frame_t;

    // Состояния автомата (FSM)
    typedef enum logic [2:0] {
        ST_IDLE,       // Ожидание данных в FIFO
        ST_HEADER,     // Передача 1 байта заголовка
        ST_DATA_3,     // Передача 4-го байта слова (MSB [31:24])
        ST_DATA_2,     // Передача 3-го байта слова ([23:16])
        ST_DATA_1,     // Передача 2-го байта слова ([15:8])
        ST_DATA_0,     // Передача 1-го байта слова (LSB [7:0])
        ST_INDEX       // Передача 1 байта индекса словаря
    } state_t;

    state_t state, next_state;

    // Регистры хранения текущего кадра
    logic [DATA_WIDTH-1:0] latched_data;
    logic [KEY_WIDTH-1:0]  latched_key;
    frame_t                frame_type;

    // Рукопожатие (Handshake) AXI-Stream
    logic tx_handshake;
    assign tx_handshake = m_axis.tvalid && m_axis.tready;

    // ------------------------------------------------------------------------
    // 1. Регистр состояния и защелкивание входных данных
    // ------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_IDLE;
            latched_data <= '0;
            latched_key  <= '0;
            frame_type   <= FRAME_RAW;
        end 
        else begin
            state <= next_state;

            // Защелкивание данных и определение типа кадра при старте
            if (state == ST_IDLE && !fifo_empty) begin
                latched_data <= fifo_rdata;
                latched_key  <= dict_key;

                if (dict_hit) begin
                    frame_type <= FRAME_KEY;
                end 
                else if (force_sync) begin
                    frame_type <= FRAME_SYNC;
                end 
                else begin
                    frame_type <= FRAME_RAW;
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // 2. Логика переходов FSM и управление вычиткой FIFO
    // ------------------------------------------------------------------------
    always_comb begin
        next_state = state;
        fifo_rd_en = 1'b0;

        case (state)
            ST_IDLE: begin
                if (!fifo_empty) begin
                    next_state = ST_HEADER;
                end
            end

            ST_HEADER: begin
                if (tx_handshake) begin
                    if (frame_type == FRAME_RAW) begin
                        next_state = ST_DATA_3;
                    end 
                    else begin
                        // Для KEY и SYNC кадров Key отправляется сразу после Header
                        next_state = ST_INDEX;
                    end
                end
            end

            ST_INDEX: begin
                if (tx_handshake) begin
                    if (frame_type == FRAME_SYNC) begin
                        next_state = ST_DATA_3; // В SYNC кадрах следом передаются данные
                    end 
                    else begin
                        // KEY кадр завершен -> вычитываем слово из FIFO
                        fifo_rd_en = 1'b1;
                        next_state = ST_IDLE;
                    end
                end
            end

            ST_DATA_3: begin
                if (tx_handshake) next_state = ST_DATA_2;
            end

            ST_DATA_2: begin
                if (tx_handshake) next_state = ST_DATA_1;
            end

            ST_DATA_1: begin
                if (tx_handshake) next_state = ST_DATA_0;
            end

            ST_DATA_0: begin
                if (tx_handshake) begin
                    // RAW или SYNC кадр завершен -> вычитываем слово из FIFO
                    fifo_rd_en = 1'b1;
                    next_state = ST_IDLE;
                end
            end

            default: next_state = ST_IDLE;
        endcase
    end

    // ------------------------------------------------------------------------
    // 3. Формирование сигналов выходного интерфейса AXI-Stream
    // ------------------------------------------------------------------------
    always_comb begin
        //m_axis.tvalid = 1'b0;
        //m_axis.tdata  = 'h0;
        //m_axis.tlast  = 1'b0;

        case (state)
            ST_IDLE: begin
                m_axis.tvalid = 1'b0;
            end

            ST_HEADER: begin
                m_axis.tvalid = 1'b1;
                case (frame_type)
                    FRAME_RAW:  m_axis.tdata = HDR_RAW;
                    FRAME_KEY:  m_axis.tdata = HDR_KEY;
                    FRAME_SYNC: m_axis.tdata = HDR_SYNC;
                    default:    m_axis.tdata = HDR_RAW;
                endcase
            end

            ST_INDEX: begin
                m_axis.tvalid = 1'b1;
                m_axis.tdata  = latched_key;
                if (frame_type == FRAME_KEY) begin
                    m_axis.tlast = 1'b1; // Завершение KEY кадра
                end
            end

            ST_DATA_3: begin
                m_axis.tvalid = 1'b1;
                m_axis.tdata  = latched_data[31:24]; // Big-Endian
            end

            ST_DATA_2: begin
                m_axis.tvalid = 1'b1;
                m_axis.tdata  = latched_data[23:16];
            end

            ST_DATA_1: begin
                m_axis.tvalid = 1'b1;
                m_axis.tdata  = latched_data[15:8];
            end

            ST_DATA_0: begin
                m_axis.tvalid = 1'b1;
                m_axis.tdata  = latched_data[7:0];
                m_axis.tlast  = 1'b1; // Завершение RAW или SYNC кадра
            end

            default: begin
                m_axis.tvalid = 1'b0;
                m_axis.tdata  = 'h0;
                m_axis.tlast  = 1'b0;
            end
        endcase
    end

endmodule