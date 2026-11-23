module spi_tx_regs_wrapper_protocol_tb_top;
    timeunit 1ns;
    timeprecision 1ps;

    localparam time CLK_PERIOD = 20ns;
    localparam time SCLK_HALF = 4 * CLK_PERIOD;

    logic clk = 0, rst_n = 1;
    logic sclk = 0, cs_n = 1, mosi = 0, miso, spi_irq, addr_error;
    logic [7:0] live_status = '0;
    tx_regs_pkg::tx_regs__in_t hwif_in;
    int accesses = 0, error_pulses = 0;
    bit test_passed = 0;

    spi_tx_regs_wrapper dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .spi_sclk          (sclk),
        .spi_cs_n          (cs_n),
        .spi_mosi          (mosi),
        .spi_miso          (miso),
        .spi_irq           (spi_irq),
        .spi_addr_err_event(addr_error),
        .hwif_in           (hwif_in),
        .hwif_out          ()
    );

    always #(CLK_PERIOD / 2) clk = ~clk;
    always @(posedge clk) begin
        if (dut.bus_complete) accesses++;
        if (addr_error) error_pulses++;
    end

    always_comb begin
        hwif_in = '{default: '0};
        hwif_in.STATUS_REG.in_fifo_empty.next = live_status[0];
        hwif_in.STATUS_REG.in_fifo_full.next  = live_status[1];
        hwif_in.STATUS_REG.fsm_state.next      = live_status[7:5];
        hwif_in.INT_STATUS_REG.spi_addr_err.hwset = addr_error;
    end

    task automatic select_slave(input time skew);
        @(posedge clk);
        #(skew);
        cs_n = 0;
    endtask

    task automatic deselect_slave();
        cs_n = 1;
        #1ns;
        if (miso !== 1'bz) $fatal(1, "MISO is not high-impedance outside CS");
        #(SCLK_HALF - 1ns);
    endtask

    task automatic transfer_bit(input logic outgoing, output logic incoming);
        mosi = outgoing;
        #(SCLK_HALF);
        incoming = miso;
        sclk = 1;
        #(SCLK_HALF);
        sclk = 0;
    endtask

    task automatic transfer_byte(input logic [7:0] outgoing, output logic [7:0] incoming,
                                 input int bit_count = 8);
        incoming = '0;
        for (int bit_index = 7; bit_index >= 8 - bit_count; bit_index--)
            transfer_bit(outgoing[bit_index], incoming[bit_index]);
    endtask

    task automatic expect_read(input logic [5:0] address, input logic [7:0] expected, input time skew);
        logic [7:0] response;
        select_slave(skew);
        transfer_byte({1'b0, address, 1'b1}, response);
        transfer_byte('0, response);
        deselect_slave();
        if (response !== expected)
            $fatal(1, "SPI read %02h returned %02h, expected %02h", address, response, expected);
    endtask

    task automatic expect_counts(input int expected_accesses, input int expected_errors);
        if (accesses != expected_accesses || error_pulses != expected_errors)
            $fatal(1, "CSR accesses/errors=%0d/%0d, expected %0d/%0d",
                   accesses, error_pulses, expected_accesses, expected_errors);
    endtask

    initial begin
        logic [7:0] response;
        #1ns;
        rst_n = 0;
        repeat (5) @(negedge clk);
        rst_n = 1;

        select_slave(1ns);
        transfer_byte(8'h7f, response, 7); // Aborted command for an unmapped read.
        deselect_slave();
        select_slave(7ns);
        transfer_byte(8'h16, response); // Mapped write, incomplete payload.
        transfer_byte(8'hff, response, 7);
        deselect_slave();
        select_slave(19ns);
        transfer_byte(8'h7e, response); // Unmapped write, incomplete payload.
        transfer_byte(8'hff, response, 7);
        deselect_slave();
        expect_counts(0, 0);
        expect_read(6'h0b, 8'h80, 19ns);

        select_slave(7ns);
        transfer_byte(8'h16, response);
        transfer_byte(8'ha5, response);
        transfer_byte(8'h5a, response); // Extra clocks under the same CS.
        deselect_slave();
        expect_read(6'h0b, 8'ha5, 1ns);
        expect_counts(3, 0);

        select_slave(19ns);
        transfer_byte(8'h7f, response); // The read command completes before CS rises.
        deselect_slave();
        expect_counts(4, 1);
        expect_read(6'h09, 8'h10, 7ns);

        live_status = 8'ha1;
        select_slave(19ns);
        transfer_byte(8'h0f, response);
        transfer_bit(0, response[7]);
        live_status = 8'h42;
        for (int bit_index = 6; bit_index >= 0; bit_index--)
            transfer_bit(0, response[bit_index]);
        deselect_slave();
        if (response !== 8'ha1) $fatal(1, "MISO byte changed during read: %02h", response);
        expect_read(6'h07, 8'h42, 7ns);
        expect_counts(7, 1);

        test_passed = 1;
        $display("PASS SPI protocol (abort, minimum timing, stable MISO and access counts)");
        $finish;
    end

    initial begin
        #100us;
        $fatal(1, "SPI protocol test timed out");
    end
endmodule
