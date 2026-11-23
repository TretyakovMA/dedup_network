module tdl_tx_reg_bridge_tb_top;
    timeunit 1ns;
    timeprecision 1ps;

    import tx_regs_pkg::*;
    import tdl_tx_pkg::TINYLFU_IDLE_WAIT_CYCLES;

    localparam time CLK_PERIOD = 20ns;
    typedef logic [TX_REGS_MIN_ADDR_WIDTH-1:0] addr_t;
    localparam addr_t CTRL = 'h00, MODE = 'h01, AGING_LO = 'h02, AGING_HI = 'h03,
                      BF_CTRL = 'h04, SLRU_CFG = 'h05, CMD = 'h06, STATUS = 'h07,
                      INT_STATUS = 'h09, HIT_RATE = 'h0b, SDR_DIV_LO = 'h20,
                      SDR_DIV_HI = 'h21, I2C_STATUS = 'h2a;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    tx_regs__in_t hwif_in;
    tx_regs__out_t hwif_out;
    logic cpu_req, cpu_wr, wr_stall, rd_stall, wr_ack, rd_ack, wr_err, rd_err;
    addr_t cpu_addr;
    logic [7:0] cpu_wr_data, cpu_rd_data;

    logic word_take, fifo_empty, fifo_full, controller_busy, policy_ready;
    logic [2:0] controller_state;
    logic [31:0] cnt_total_words, cnt_key_frames, cnt_raw_frames, cnt_sync_frames, cnt_bf_filtered;
    logic fifo_full_event, aging_event, high_hit_rate, spi_addr_err;
    logic tx_en, bypass_en;
    logic [31:0] policy_cfg;
    logic [15:0] sdr_clk_div;
    logic [7:0] hit_rate_thresh;

    int checked_accesses = 0;
    bit test_passed = 1'b0;

    tx_regs csr (
        .clk                 (clk),
        .rst                 (!rst_n),
        .s_cpuif_req         (cpu_req),
        .s_cpuif_req_is_wr   (cpu_wr),
        .s_cpuif_addr        (cpu_addr),
        .s_cpuif_wr_data     (cpu_wr_data),
        .s_cpuif_wr_biten    (8'hff),
        .s_cpuif_req_stall_wr(wr_stall),
        .s_cpuif_req_stall_rd(rd_stall),
        .s_cpuif_rd_ack      (rd_ack),
        .s_cpuif_rd_err      (rd_err),
        .s_cpuif_rd_data     (cpu_rd_data),
        .s_cpuif_wr_ack      (wr_ack),
        .s_cpuif_wr_err      (wr_err),
        .hwif_in            (hwif_in),
        .hwif_out           (hwif_out)
    );

    tdl_tx_reg_bridge dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .hwif_out       (hwif_out),
        .hwif_in        (hwif_in),
        .word_take      (word_take),
        .fifo_empty     (fifo_empty),
        .fifo_full      (fifo_full),
        .controller_busy(controller_busy),
        .controller_state(controller_state),
        .policy_ready   (policy_ready),
        .cnt_total_words(cnt_total_words),
        .cnt_key_frames (cnt_key_frames),
        .cnt_raw_frames (cnt_raw_frames),
        .cnt_sync_frames(cnt_sync_frames),
        .cnt_bf_filtered(cnt_bf_filtered),
        .fifo_full_event(fifo_full_event),
        .aging_event    (aging_event),
        .high_hit_rate   (high_hit_rate),
        .spi_addr_err   (spi_addr_err),
        .tx_en          (tx_en),
        .bypass_en      (bypass_en),
        .policy_cfg     (policy_cfg),
        .sdr_clk_div    (sdr_clk_div),
        .hit_rate_thresh(hit_rate_thresh)
    );

    always #(CLK_PERIOD / 2) clk = ~clk;

    task automatic tick();
        @(posedge clk);
        #1ns;
    endtask

    task automatic reset_dut();
        @(negedge clk);
        rst_n = 1'b0;
        {cpu_req, cpu_wr, cpu_addr, cpu_wr_data} = '0;
        {word_take, fifo_full, controller_busy, controller_state} = '0;
        fifo_empty = 1'b1;
        policy_ready = 1'b1;
        {cnt_total_words, cnt_key_frames, cnt_raw_frames, cnt_sync_frames, cnt_bf_filtered} = '0;
        {fifo_full_event, aging_event, high_hit_rate, spi_addr_err} = '0;
        tick();
        @(negedge clk);
        rst_n = 1'b1;
        tick();
    endtask

    task automatic write_csr(
        input addr_t addr,
        input logic [7:0] data,
        input bit expected_error = 0,
        input logic [3:0] simultaneous_events = '0
    );
        @(negedge clk);
        cpu_addr    = addr;
        cpu_wr_data = data;
        cpu_wr      = 1'b1;
        cpu_req     = 1'b1;
        {fifo_full_event, aging_event, high_hit_rate, spi_addr_err} = simultaneous_events;
        #1ns;
        if ({wr_stall, wr_ack, wr_err} !== {2'b01, expected_error})
            $fatal(1, "CSR write to 0x%02h failed", addr);
        tick();
        cpu_req = 1'b0;
        {fifo_full_event, aging_event, high_hit_rate, spi_addr_err} = '0;
        checked_accesses++;
    endtask

    task automatic read_csr(input addr_t addr, output logic [7:0] value, input bit expected_error = 0);
        @(negedge clk);
        cpu_addr = addr;
        cpu_wr   = 1'b0;
        cpu_req  = 1'b1;
        #1ns;
        if ({rd_stall, rd_ack, rd_err} !== {2'b01, expected_error})
            $fatal(1, "CSR read from 0x%02h returned stall/ack/err=%b/%b/%b, expected 0/1/%b",
                   addr, rd_stall, rd_ack, rd_err, expected_error);
        value = cpu_rd_data;
        tick();
        cpu_req = 1'b0;
        checked_accesses++;
    endtask

    task automatic expect_csr(input addr_t addr, input logic [7:0] expected, input bit expected_error = 0);
        logic [7:0] value;
        read_csr(addr, value, expected_error);
        if (value !== expected)
            $fatal(1, "CSR read from 0x%02h returned %02h, expected %02h", addr, value, expected);
    endtask

    task automatic expect_settings(
        input string phase,
        input logic [31:0] expected_cfg,
        input logic [15:0] expected_div,
        input logic [7:0] expected_thresh,
        input logic [1:0] expected_enables
    );
        if (policy_cfg !== expected_cfg || sdr_clk_div !== expected_div ||
            hit_rate_thresh !== expected_thresh || {tx_en, bypass_en} !== expected_enables)
            $fatal(1, "%s: cfg/div/thresh/en=%h/%h/%h/%b expected=%h/%h/%h/%b",
                   phase, policy_cfg, sdr_clk_div, hit_rate_thresh, {tx_en, bypass_en},
                   expected_cfg, expected_div, expected_thresh, expected_enables);
    endtask

    task automatic test_configuration();
        expect_settings("reset settings", 32'h0400_4010, 16'h0000, 8'h80, 2'b00);
        write_csr(MODE, 8'h01); // SLRU
        write_csr(SLRU_CFG, 8'h00);
        expect_settings("invalid SLRU quota passed through", 32'h0400_0011, 16'h0000, 8'h80, 2'b00);
        write_csr(SLRU_CFG, 8'h12);
        expect_settings("SLRU quota corrected before first pop", 32'h0400_1211, 16'h0000, 8'h80, 2'b00);

        write_csr(MODE, 8'hf6); // Clock and CU_DISABLE, with reserved bits set.
        write_csr(AGING_LO, 8'h34);
        write_csr(AGING_HI, 8'h12);
        write_csr(SDR_DIV_LO, 8'hcd);
        write_csr(SDR_DIV_HI, 8'hab);
        write_csr(HIT_RATE, 8'h6e);
        write_csr(BF_CTRL, 8'h07);
        write_csr(CMD, 8'h03);
        write_csr(CTRL, 8'h07); // TX_EN, BYPASS_EN and the inactive SOFT_RESET command.
        expect_settings("settings before first Bypass word", 32'h1234_1216, 16'habcd, 8'h6e, 2'b11);

        @(negedge clk);
        policy_ready = 1'b0;
        word_take = 1'b1;
        tick();
        word_take = 1'b0;

        // Две поздние записи должны вызвать диагностику и сохранить активную пару.
        write_csr(MODE, 8'h05);
        expect_csr(MODE, 8'h05);
        write_csr(SLRU_CFG, 8'h21);
        expect_csr(SLRU_CFG, 8'h21);
        expect_settings("first Bypass pop locked algorithm and quota", 32'h1234_1216,
                        16'habcd, 8'h6e, 2'b11);

        @(negedge clk);
        policy_ready = 1'b1;
        write_csr(CTRL, 8'h00);
        write_csr(AGING_LO, 8'h78);
        expect_settings("low aging byte while paused", 32'h1278_1216, 16'habcd, 8'h6e, 2'b00);
        write_csr(AGING_HI, 8'h56);
        write_csr(MODE, 8'h09); // Keep the programmed mode and change both live flags.
        write_csr(BF_CTRL, 8'h00);
        write_csr(SDR_DIV_LO, 8'hef);
        expect_settings("low SDR byte while paused", 32'h5678_120a, 16'habef, 8'h6e, 2'b00);
        write_csr(SDR_DIV_HI, 8'hbe);
        write_csr(CTRL, 8'h01);
        expect_settings("resume with live settings and original locked pair", 32'h5678_120a,
                        16'hbeef, 8'h6e, 2'b10);

        reset_dut();
        expect_settings("reset released the lock", 32'h0400_4010, 16'h0000, 8'h80, 2'b00);
        write_csr(MODE, 8'h03);
        write_csr(SLRU_CFG, 8'h34);
        expect_settings("new settings after reset", 32'h0400_3413, 16'h0000, 8'h80, 2'b00);
    endtask

    task automatic expect_counter(input addr_t base, input logic [31:0] expected);
        for (int byte_index = 0; byte_index < 4; byte_index++)
            expect_csr(base + addr_t'(byte_index), expected[8 * byte_index +: 8]);
    endtask

    task automatic pulse_irq(input logic [3:0] events);
        @(negedge clk);
        {fifo_full_event, aging_event, high_hit_rate, spi_addr_err} = events;
        tick();
        {fifo_full_event, aging_event, high_hit_rate, spi_addr_err} = '0;
        tick();
    endtask

    task automatic test_hwif_readback();
        @(negedge clk);
        fifo_empty       = 1'b0;
        fifo_full        = 1'b1;
        controller_busy  = 1'b1;
        controller_state = 3'd5;
        policy_ready     = 1'b0;
        cnt_total_words  = 32'h0123_4567;
        cnt_key_frames   = 32'h1020_3040;
        cnt_raw_frames   = 32'h8765_4321;
        cnt_sync_frames  = 32'h1234_abcd;
        cnt_bf_filtered  = 32'hffff_ffff;
        expect_csr(STATUS, 8'ha2);
        expect_counter(6'h0c, 32'h0123_4567);
        expect_counter(6'h10, 32'h1020_3040);
        expect_counter(6'h14, 32'h8765_4321);
        expect_counter(6'h18, 32'h1234_abcd);
        expect_counter(6'h1c, 32'hffff_ffff);
        expect_csr(I2C_STATUS, 8'h00);

        @(negedge clk);
        fifo_empty       = 1'b1;
        fifo_full        = 1'b0;
        controller_busy  = 1'b0;
        controller_state = '0;
        expect_csr(STATUS, 8'h01); // Backend still busy, reserved CONFIG_PENDING stays zero.

        expect_csr(INT_STATUS, 8'h00);
        pulse_irq(4'b1000);
        expect_csr(INT_STATUS, 8'h01);
        pulse_irq(4'b0100);
        expect_csr(INT_STATUS, 8'h05);
        pulse_irq(4'b0010);
        expect_csr(INT_STATUS, 8'h0d);
        pulse_irq(4'b0001);
        expect_csr(INT_STATUS, 8'h1d);
        write_csr(INT_STATUS, 8'h04);
        expect_csr(INT_STATUS, 8'h19);
        write_csr(INT_STATUS, 8'h19);
        expect_csr(INT_STATUS, 8'h00);

        write_csr(INT_STATUS, 8'h1d, 0, 4'b1111);
        expect_csr(INT_STATUS, 8'h1d); // Events win over W1C on the same edge.
        write_csr(INT_STATUS, 8'h00);
        expect_csr(INT_STATUS, 8'h1d);
        write_csr(INT_STATUS, 8'h1d, 0, 4'b0010);
        expect_csr(INT_STATUS, 8'h08); // The high-hit-rate level keeps its own bit set.
        write_csr(INT_STATUS, 8'h08);
        expect_csr(INT_STATUS, 8'h00);
    endtask

    task automatic test_address_errors_and_shadow();
        expect_csr(6'h2b, 8'h40);
        expect_csr(6'h2c, 8'h00, 1);
        expect_csr(6'h3f, 8'h00, 1);
        write_csr(6'h2c, 8'hff, 1);
        write_csr(6'h3f, 8'hff, 1);
        write_csr(STATUS, 8'hff);
        expect_csr(STATUS, 8'h01);

        @(negedge clk);
        cnt_total_words = 32'h1234_ffff;
        expect_csr(6'h0c, 8'hff);
        @(negedge clk);
        cnt_total_words = 32'habcd_0000;
        expect_csr(6'h0d, 8'hff);
        expect_csr(6'h0e, 8'h34);
        expect_csr(6'h0f, 8'h12);
        expect_counter(6'h0c, 32'habcd_0000);
    endtask

    task automatic wait_for_input_drain(input int max_polls, output bit drained);
        logic [7:0] status;
        drained = 0;
        repeat (max_polls) begin
            read_csr(STATUS, status);
            // IN_FIFO_EMPTY and FSM_STATE=IDLE must come from the same CSR read.
            if ((status & 8'he1) === 8'h01) begin
                drained = 1;
                return;
            end
        end
    endtask

    task automatic test_tinylfu_reconfiguration();
        bit drained;
        reset_dut();
        write_csr(CTRL, 8'h01);

        @(negedge clk);
        fifo_empty = 0;
        word_take = 1;
        tick();
        word_take = 0;
        // Model the final pop after the source has stopped feeding the FIFO.
        fifo_empty = 1;
        controller_busy = 1;
        controller_state = 3'd5;
        policy_ready = 0;

        wait_for_input_drain(3, drained);
        if (drained || tx_en !== 1'b1 || policy_cfg !== 32'h0400_4010)
            $fatal(1, "Drain timeout must leave TX_EN and configuration intact");

        fork
            begin
                repeat (4) tick();
                // Commit releases the controller while maintenance keeps policy busy.
                controller_busy = 0;
                controller_state = '0;
                repeat (TINYLFU_IDLE_WAIT_CYCLES) tick();
                policy_ready = 1;
            end
            begin
                wait_for_input_drain(8, drained);
                if (!drained || policy_ready !== 1'b0 || tx_en !== 1'b1)
                    $fatal(1, "Expected drained status before TinyLFU is ready, with TX still enabled");

                repeat (TINYLFU_IDLE_WAIT_CYCLES) tick();
                if (policy_ready !== 1'b1 || tx_en !== 1'b1)
                    $fatal(1, "Timed wait did not reach policy idle while TX is enabled");

                write_csr(CTRL, 8'h00);
                write_csr(MODE, 8'h0c);
                write_csr(BF_CTRL, 8'h00);
                write_csr(AGING_LO, 8'h02);
                expect_settings("one period byte written, TX paused", 32'h0402_400c, 16'h0000, 8'h80, 2'b00);
                write_csr(AGING_HI, 8'h01);
                write_csr(CTRL, 8'h01);
                expect_settings("new TinyLFU settings active", 32'h0102_400c, 16'h0000, 8'h80, 2'b10);
            end
        join
        $display("PASS TinyLFU reconfiguration after a %0d-cycle wait with TX enabled",
                 TINYLFU_IDLE_WAIT_CYCLES);
    endtask

    initial begin
        reset_dut();
        test_configuration();
        test_hwif_readback();
        test_address_errors_and_shadow();
        test_tinylfu_reconfiguration();
        test_passed = 1'b1;
        $display("PASS tdl_tx_reg_bridge (%0d checked CSR accesses)", checked_accesses);
        $finish;
    end

    initial begin
        #100us;
        $fatal(1, "tdl_tx_reg_bridge simulation timeout");
    end
endmodule
