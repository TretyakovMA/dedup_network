`ifndef SPI_TX_REGS_WRAPPER
`define SPI_TX_REGS_WRAPPER
// Обёртка SPI mode 0 для байтового доступа к CSR и выдачи IRQ.
// Каждая фаза SCLK и интервалы установки и удержания CS занимают не менее четырёх тактов clk.
module spi_tx_regs_wrapper (
    input  logic clk,
    input  logic rst_n,

    input  logic spi_sclk,
    input  logic spi_cs_n,
    input  logic spi_mosi,
    output logic spi_miso,
    output logic spi_irq,
    output logic spi_addr_err_event,

    input  var tx_regs_pkg::tx_regs__in_t hwif_in,
    output var tx_regs_pkg::tx_regs__out_t hwif_out
);
    typedef enum logic [1:0] { ST_CMD, ST_READ_DATA, ST_WRITE_DATA, ST_DONE } state_t;
    state_t state;

    // SPI-входы синхронизируются в clk, где выполняются автомат SPI и доступ к CSR.
    (* ASYNC_REG = "TRUE" *) logic [1:0] sclk_sync, cs_n_sync, mosi_sync;
    logic sclk_previous, sclk_rise, sclk_fall;
    logic [2:0] bit_count;
    logic [7:0] rx_shift, read_data;
    logic read_started;

    logic bus_req, bus_req_is_wr, bus_complete;
    logic [5:0] bus_addr;
    logic [7:0] bus_wr_data;
    logic cpuif_req_stall_wr, cpuif_req_stall_rd;
    logic cpuif_rd_ack, cpuif_rd_err, cpuif_wr_ack, cpuif_wr_err;
    logic [7:0] cpuif_rd_data;

    tx_regs u_tx_regs (
        .clk                  (clk),
        .rst                  (!rst_n),
        .s_cpuif_req          (bus_req),
        .s_cpuif_req_is_wr    (bus_req_is_wr),
        .s_cpuif_addr         (bus_addr),
        .s_cpuif_wr_data      (bus_wr_data),
        .s_cpuif_wr_biten     (8'hff),
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

    // Обёртка объединяет только разрешённые источники. Sticky-биты хранит tx_regs.
    assign spi_irq = rst_n && (
        (hwif_out.INT_STATUS_REG.fifo_overflow.value && hwif_out.INT_ENABLE_REG.fifo_overflow.value) ||
        (hwif_out.INT_STATUS_REG.aging_event.value   && hwif_out.INT_ENABLE_REG.aging_event.value)   ||
        (hwif_out.INT_STATUS_REG.high_hit_rate.value && hwif_out.INT_ENABLE_REG.high_hit_rate.value) ||
        (hwif_out.INT_STATUS_REG.spi_addr_err.value  && hwif_out.INT_ENABLE_REG.spi_addr_err.value));

    assign sclk_rise = sclk_sync[1] && !sclk_previous;
    assign sclk_fall = !sclk_sync[1] && sclk_previous;

    // The generated passthrough interface returns ack in the acceptance cycle.
    assign bus_complete = bus_req && (bus_req_is_wr
                        ? (!cpuif_req_stall_wr && cpuif_wr_ack)
                        : (!cpuif_req_stall_rd && cpuif_rd_ack));

    // Raw CS controls only the pad output enable. The FSM sees synchronized CS.
    assign spi_miso = spi_cs_n ? 1'bz :
                      ((state == ST_READ_DATA && read_started) ? read_data[3'd7 - bit_count] : 1'b0);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_sync     <= '0;
            cs_n_sync     <= '1;
            mosi_sync     <= '0;
            sclk_previous <= 1'b0;
        end else begin
            sclk_sync     <= {sclk_sync[0], spi_sclk};
            cs_n_sync     <= {cs_n_sync[0], spi_cs_n};
            mosi_sync     <= {mosi_sync[0], spi_mosi};
            sclk_previous <= sclk_sync[1];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= ST_CMD;
            bit_count          <= '0;
            rx_shift           <= '0;
            read_data          <= '0;
            read_started       <= 1'b0;
            bus_req            <= 1'b0;
            bus_req_is_wr      <= 1'b0;
            bus_addr           <= '0;
            bus_wr_data        <= '0;
            spi_addr_err_event <= 1'b0;
        end else begin
            spi_addr_err_event <= 1'b0;
            // Принимаем байт чтения и выдаём событие ошибки на одном завершении CPUIF.
            if (bus_complete) begin
                bus_req            <= 1'b0;
                spi_addr_err_event <= bus_req_is_wr ? cpuif_wr_err : cpuif_rd_err;
                if (!bus_req_is_wr)
                    read_data <= cpuif_rd_err ? 8'h00 : cpuif_rd_data;
            end

            if (cs_n_sync[1]) begin
                state        <= ST_CMD;
                bit_count    <= '0;
                rx_shift     <= '0;
                read_started <= 1'b0;
            end else begin
                case (state)
                    ST_CMD, ST_WRITE_DATA: if (sclk_rise) begin
                        rx_shift  <= {rx_shift[6:0], mosi_sync[1]};
                        bit_count <= bit_count + 3'd1;

                        if (bit_count == 3'd7) begin
                            if (state == ST_CMD) begin
                                bus_addr      <= rx_shift[5:0];
                                bus_req_is_wr <= !mosi_sync[1];
                                bus_req       <= mosi_sync[1];
                                state         <= mosi_sync[1] ? ST_READ_DATA : ST_WRITE_DATA;
                            end else begin
                                bus_wr_data <= {rx_shift[6:0], mosi_sync[1]};
                                bus_req     <= 1'b1;
                                state       <= ST_DONE;
                            end
                        end
                    end
                    ST_READ_DATA: if (sclk_fall) begin
                        if (!read_started)
                            read_started <= 1'b1; // Falling edge after the command launches bit 7.
                        else if (bit_count == 3'd7)
                            state <= ST_DONE;
                        else
                            bit_count <= bit_count + 3'd1;
                    end
                    ST_DONE: ; // A new access requires deasserting CS.
                    default: state <= ST_CMD;
                endcase
            end
        end
    end

endmodule
`endif
