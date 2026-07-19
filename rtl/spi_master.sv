module spi_master #(
    parameter int CLK_DIV = 4 // Делитель частоты (sclk = clk / CLK_DIV). Должен быть четным и >= 4
)(
    input  logic       clk,
    input  logic       rst_n,
    
    // Интерфейс пользователя
    input  logic       start,
    input  logic [7:0] tx_data,
    output logic [7:0] rx_data,
    output logic       ready,
    
    // Физический интерфейс SPI
    output logic       sclk,
    output logic       cs_n,
    output logic       mosi,
    input  logic       miso
);

    // Автоматический расчет параметров счетчика частоты
    localparam int HALF_DIV         = CLK_DIV / 2;
    localparam int CLK_CNT_WIDTH    = $clog2(HALF_DIV);
    localparam logic [CLK_CNT_WIDTH-1:0] HALF_PERIOD_CYCLES = (HALF_DIV - 1);

    // Состояния и переменные автомата (FSM)
    typedef enum logic {IDLE, TRANSFER} state_t;
    state_t state, next_state; 

    logic [7:0] tx_reg;
    logic [7:0] rx_reg;
    logic [2:0] bit_cnt;
    logic [CLK_CNT_WIDTH-1:0] clk_cnt;

    // Строб полупериода частоты
    logic tick;
    assign tick = (state == TRANSFER) && (clk_cnt == HALF_PERIOD_CYCLES);
    
    // =========================================================================
    // 1. Блок памяти автомата (Sequential: State Register)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            state <= IDLE;
        else        
            state <= next_state;
    end

    // =========================================================================
    // 2. Блок логики переходов (Combinational: Next State Logic)
    // =========================================================================
    always_comb begin
        next_state = state; // По умолчанию состояние не меняется
        
        case (state)
            IDLE: begin
                if (start) next_state = TRANSFER;
                else       next_state = IDLE;
            end

            TRANSFER: begin
                // Переход в IDLE происходит по тику, когда текущее значение sclk равно 1 
                // (то есть сейчас будет спад) и мы обработали последний бит (bit_cnt == 0)
                if (tick && sclk && (bit_cnt == 3'd0)) begin
                    next_state = IDLE;
                end
            end
            
            default: next_state = IDLE;
        endcase
    end

    // =========================================================================
    // 3. Блок делителя частоты (Sequential)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_cnt <= '0;
        end 
        else begin
            if (state == TRANSFER) begin
                if (clk_cnt == HALF_PERIOD_CYCLES)
                    clk_cnt <= '0;
                else
                    clk_cnt <= clk_cnt + 1'b1;
            end 
            else begin
                clk_cnt <= '0;
            end
        end
    end

    // =========================================================================
    // 4. Блок тракта данных и выходных сигналов (Sequential Datapath)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cs_n     <= 1'b1;
            sclk     <= 1'b0;
            mosi     <= 1'b0;
            rx_data  <= 8'h00;
            ready    <= 1'b1;
            bit_cnt  <= 3'd0;
            tx_reg   <= 8'h00;
            rx_reg   <= 8'h00;
        end 
        else begin
            case (state)
                IDLE: begin
                    ready <= 1'b1;
                    cs_n  <= 1'b1;
                    sclk  <= 1'b0;
                    mosi  <= 1'b0;
                    
                    if (start) begin
                        ready   <= 1'b0;
                        cs_n    <= 1'b0; 
                        tx_reg  <= tx_data;
                        mosi    <= tx_data[7]; 
                        bit_cnt <= 3'd7;
                    end
                end

                TRANSFER: begin
                    if (tick) begin
                        sclk <= ~sclk; 

                        if (!sclk) begin 
                            // Был 0, станет 1 -> Фронт. Сэмплируем входные данные
                            rx_reg[bit_cnt] <= miso;
                        end 
                        else begin 
                            // Был 1, станет 0 -> Спад. Обновляем выходы или завершаем работу
                            if (bit_cnt == 3'd0) begin
                                cs_n    <= 1'b1;
                                ready   <= 1'b1;
                                rx_data <= rx_reg;
                            end 
                            else begin
                                bit_cnt <= bit_cnt - 1'b1;
                                mosi    <= tx_reg[bit_cnt - 1'b1]; 
                            end
                        end
                    end
                end
            endcase
        end
    end
endmodule