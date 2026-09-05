`ifndef SPI_TX_REGS_WRAPPER
`define SPI_TX_REGS_WRAPPER
module spi_tx_regs_wrapper(
    input logic clk,
    input logic rst_n,

    spi_if.slave s_spi,

    input  tx_regs_pkg::tx_regs__in_t  hwif_in,
    output tx_regs_pkg::tx_regs__out_t hwif_out
);
    logic [2:0] bit_cnt;
    logic       write_op;
    logic [7:0] rx_shift;
    logic [7:0] tx_shift;

    logic       sclk_d;
    logic       bus_req;
    logic       bus_req_is_wr;
    logic [5:0] bus_addr;
    logic [7:0] bus_wr_data;
    logic [7:0] bus_wr_biten;
    logic [2:0] read_bit_cnt;
    logic       read_active;
    logic       response_first_bit;

    logic       cpuif_req_stall_wr;
    logic       cpuif_req_stall_rd;
    logic       cpuif_rd_ack;
    logic       cpuif_rd_err;
    logic [7:0] cpuif_rd_data;
    logic       cpuif_wr_ack;
    logic       cpuif_wr_err;

    typedef enum logic [1:0] {
        IDLE  = 2'b00,
        CMD   = 2'b01,   // приём первого байта (addr + R/W)
        DATA  = 2'b10    // приём/передача второго байта
    } state_t;
    state_t state;
    state_t next_state;

    logic sclk_rise;
    logic sclk_fall;


    // Модель регистров
    tx_regs u_tx_regs (
        .clk                  (clk),
        .rst                  (~rst_n),
        .s_cpuif_req          (bus_req),
        .s_cpuif_req_is_wr    (bus_req_is_wr),
        .s_cpuif_addr         (bus_addr),
        .s_cpuif_wr_data      (bus_wr_data),
        .s_cpuif_wr_biten     (bus_wr_biten),
        .s_cpuif_req_stall_wr (cpuif_req_stall_wr),
        .s_cpuif_req_stall_rd (cpuif_req_stall_rd),
        .s_cpuif_rd_ack       (cpuif_rd_ack),
        .s_cpuif_rd_err       (cpuif_rd_err),
        .s_cpuif_rd_data      (cpuif_rd_data),
        .s_cpuif_wr_ack       (cpuif_wr_ack),
        .s_cpuif_wr_err       (cpuif_wr_err),
        .hwif_in              (hwif_in),
        .hwif_out             (hwif_out)
    );

    // Определяем фронты относительно предыдущего состояния SCLK.
    assign sclk_rise = !sclk_d && s_spi.sclk;
    assign sclk_fall = sclk_d && !s_spi.sclk;

    // Комбинационная логика переходов автомата SPI.
    // Первый байт команды принимается в состоянии CMD, второй байт
    // передаётся или принимается в состоянии DATA.
    always_comb begin
        next_state = state;

        if (s_spi.cs_n) begin
            next_state = IDLE;
        end
        else begin
            case (state)
                IDLE: begin
                    next_state = CMD;
                end
                CMD: begin
                    if (sclk_rise && (bit_cnt == 3'd7)) begin
                        next_state = DATA;
                    end
                end
                DATA: begin
                    next_state = DATA;
                end
                default: begin
                    next_state = IDLE;
                end
            endcase
        end
    end

    

    // MISO отключается при неактивном CS. Во время чтения ответ регистра
    // выдаётся старшим битом первым, остальные режимы используют сдвиговый регистр.
    assign s_spi.miso = s_spi.cs_n ? 1'bz :
                        ((bus_req && !bus_req_is_wr) ? cpuif_rd_data[7 - read_bit_cnt] : tx_shift[7]);

    // Обработка асинхронного SPI-интерфейса.
    // Входные данные фиксируются на rising edge, выходные данные меняются
    // на falling edge, что соответствует режиму SPI CPHA=0.
    always @(s_spi.sclk or s_spi.cs_n or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt            <= '0;
            write_op           <= 1'b0;
            rx_shift           <= '0;
            tx_shift           <= '0;
            sclk_d             <= 1'b0;
            bus_req            <= 1'b0;
            bus_req_is_wr      <= 1'b0;
            bus_addr           <= '0;
            bus_wr_data        <= '0;
            bus_wr_biten       <= 8'hff;
            read_bit_cnt       <= '0;
            read_active        <= 1'b0;
            response_first_bit <= 1'b0;
            state              <= IDLE;
        end 
        else if (s_spi.cs_n) begin
            bit_cnt            <= '0;
            rx_shift           <= '0;
            tx_shift           <= '0;
            bus_req            <= 1'b0;
            response_first_bit <= 1'b0;
            state              <= IDLE;
            sclk_d             <= s_spi.sclk;
        end 
        else begin
            // Переходы, совпадающие с событием SCLK, фиксируем здесь,
            // чтобы исключить гонку между always_comb и обработчиком фронта.
            if (state == IDLE) begin
                state <= CMD;
            end
            else if ((state == CMD) && sclk_rise && (bit_cnt == 3'd7)) begin
                state <= DATA;
            end
            else begin
                state <= next_state;
            end

            // Сгенерированный регистровый блок принимает один запрос за такт.
            if (bus_req && (cpuif_rd_ack || cpuif_wr_ack)) begin
                if (cpuif_wr_ack) begin
                    bus_req <= 1'b0;
                end
            end

            if (sclk_rise) begin
                rx_shift <= {rx_shift[6:0], s_spi.mosi};
                if (state == CMD) begin
                    if (bit_cnt == 3'd7) begin
                        // Последний бит команды: 1 — чтение, 0 — запись.
                        write_op      <= !s_spi.mosi;
                        bus_addr      <= rx_shift[5:0];
                        bus_req_is_wr <= !s_spi.mosi;
                        bus_wr_biten  <= 8'hff;
                        bit_cnt       <= '0;
                        read_bit_cnt  <= '0;
                        read_active   <= 1'b0;

                        if (s_spi.mosi) begin
                            bus_wr_data <= 8'h00;
                            bus_req     <= 1'b1;
                        end
                    end 
                    else begin
                        bit_cnt <= bit_cnt + 3'd1;
                    end
                end 
                else if (state == DATA) begin
                    if (!write_op) begin
                        read_active <= 1'b1;
                    end
                    if (bit_cnt == 3'd7) begin
                        if (write_op) begin
                            bus_wr_data <= {rx_shift[6:0], s_spi.mosi};
                            bus_req     <= 1'b1;
                        end
                        bit_cnt <= '0;
                    end 
                    else begin
                        bit_cnt <= bit_cnt + 3'd1;
                    end
                end
            end
            else if (sclk_fall && (state == DATA) && !write_op) begin
                // Между выборками входа продвигаем следующий бит ответа MISO.
                if (bus_req && read_active) begin
                    if (read_bit_cnt == 3'd7) begin
                        bus_req <= 1'b0;
                    end else begin
                        read_bit_cnt <= read_bit_cnt + 3'd1;
                    end
                end 
                else if (response_first_bit) begin
                    response_first_bit <= 1'b0;
                end 
                else begin
                    tx_shift <= {tx_shift[6:0], 1'b0};
                end
            end
            sclk_d <= s_spi.sclk;
        end
    end

endmodule
`endif