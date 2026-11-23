module tdl_tx_stats_tb_top;
    timeunit 1ns;
    timeprecision 1ps;

    import tdl_tx_pkg::*;

    localparam time CLK_PERIOD = 20ns;
    localparam logic [31:0] COUNT_MAX = 32'hffff_ffff;

    logic clk = 1'b0;
    logic rst_n = 1'b1;
    logic axis_accept, frame_done, bf_filtered_event, fifo_full;
    logic aging_done, spi_addr_err_event;
    logic [1:0] frame_done_type;
    logic [7:0] hit_rate_thresh;
    logic [31:0] cnt_total_words, cnt_key_frames, cnt_raw_frames, cnt_sync_frames, cnt_bf_filtered;
    logic fifo_full_event, aging_event, high_hit_rate, spi_addr_err;

    // Эталон хранит полные суммы и ограничивает их при сравнении с RTL.
    longint unsigned model_total, model_frames[3], model_bf;
    bit previous_full;
    int checked_cycles = 0;
    bit test_passed = 1'b0;

    tdl_tx_stats dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .axis_accept       (axis_accept),
        .frame_done        (frame_done),
        .frame_done_type   (frame_done_type),
        .bf_filtered_event (bf_filtered_event),
        .fifo_full         (fifo_full),
        .aging_done        (aging_done),
        .spi_addr_err_event(spi_addr_err_event),
        .hit_rate_thresh   (hit_rate_thresh),
        .cnt_total_words   (cnt_total_words),
        .cnt_key_frames    (cnt_key_frames),
        .cnt_raw_frames    (cnt_raw_frames),
        .cnt_sync_frames   (cnt_sync_frames),
        .cnt_bf_filtered   (cnt_bf_filtered),
        .fifo_full_event   (fifo_full_event),
        .aging_event       (aging_event),
        .high_hit_rate     (high_hit_rate),
        .spi_addr_err      (spi_addr_err)
    );

    always #(CLK_PERIOD / 2) clk = ~clk;

    function automatic logic [31:0] bounded_count(input longint unsigned value);
        return value > 64'(COUNT_MAX) ? COUNT_MAX : value[31:0];
    endfunction

    task automatic check_outputs(input string phase);
        logic [31:0] expected_total, expected_key, expected_raw, expected_sync, expected_bf;
        bit expected_rate, expected_full, expected_aging, expected_spi_error;

        expected_total = bounded_count(model_total);
        expected_key   = bounded_count(model_frames[FRAME_KEY]);
        expected_raw   = bounded_count(model_frames[FRAME_RAW]);
        expected_sync  = bounded_count(model_frames[FRAME_SYNC]);
        expected_bf    = bounded_count(model_bf);
        if ({cnt_total_words, cnt_key_frames, cnt_raw_frames, cnt_sync_frames, cnt_bf_filtered}
            !== {expected_total, expected_key, expected_raw, expected_sync, expected_bf}) begin
            $fatal(1, "%s at %t: total/KEY/RAW/SYNC/BF=%h/%h/%h/%h/%h expected=%h/%h/%h/%h/%h",
                   phase, $time, cnt_total_words, cnt_key_frames, cnt_raw_frames,
                   cnt_sync_frames, cnt_bf_filtered, expected_total, expected_key,
                   expected_raw, expected_sync, expected_bf);
        end

        expected_rate = (expected_total != 0) &&
                        (64'd255 * expected_key > 64'(hit_rate_thresh) * expected_total);
        expected_full      = rst_n && fifo_full && !previous_full;
        expected_aging     = rst_n && aging_done;
        expected_spi_error = rst_n && spi_addr_err_event;
        if ({fifo_full_event, aging_event, spi_addr_err, high_hit_rate}
            !== {expected_full, expected_aging, expected_spi_error, expected_rate}) begin
            $fatal(1, "%s at %t: full/aging/SPI/rate=%b/%b/%b/%b expected=%b/%b/%b/%b (threshold=%0d)",
                   phase, $time, fifo_full_event, aging_event, spi_addr_err, high_hit_rate,
                   expected_full, expected_aging, expected_spi_error, expected_rate, hit_rate_thresh);
        end
    endtask

    task automatic reset_dut();
        @(negedge clk);
        rst_n = 1'b0;
        {axis_accept, frame_done, bf_filtered_event, fifo_full, aging_done, spi_addr_err_event} = '1;
        frame_done_type = FRAME_KEY;
        hit_rate_thresh = '0;
        model_total = 0;
        foreach (model_frames[i]) model_frames[i] = 0;
        model_bf = 0;
        previous_full = 0;
        #1ns;
        check_outputs("asynchronous reset with active inputs");
        @(posedge clk);
        #1ns;
        check_outputs("reset held through clock edge");
        @(negedge clk);
        {axis_accept, frame_done, bf_filtered_event, fifo_full, aging_done, spi_addr_err_event} = '0;
        rst_n = 1'b1;
        #1ns;
        check_outputs("reset released");
    endtask

    task automatic step(
        input string phase,
        input bit accepted = 0,
        input bit completed = 0,
        input logic [1:0] frame_type = FRAME_RAW,
        input bit bf_rejected = 0,
        input bit full = 0,
        input bit aged = 0,
        input bit spi_error = 0,
        input logic [7:0] threshold = 0
    );
        @(negedge clk);
        axis_accept        = accepted;
        frame_done         = completed;
        frame_done_type    = frame_type;
        bf_filtered_event  = bf_rejected;
        fifo_full          = full;
        aging_done         = aged;
        spi_addr_err_event = spi_error;
        hit_rate_thresh    = threshold;
        #1ns;
        check_outputs({phase, " before posedge"});

        @(posedge clk);
        model_total += accepted;
        if (completed && frame_type < 2'd3)
            model_frames[frame_type]++;
        model_bf += bf_rejected;
        previous_full = full;
        checked_cycles++;
        #1ns;
        check_outputs(phase);
    endtask

    task automatic test_events_and_thresholds();
        reset_dut();
        step("KEY with zero total", 0, 1, FRAME_KEY);
        step("one hit out of one word", 1, 0, FRAME_RAW, 0, 0, 0, 0, 8'd255);
        step("threshold just below 100 percent", 0, 0, FRAME_RAW, 0, 0, 0, 0, 8'd254);

        reset_dut();
        step("AXIS word accepted", 1);
        step("BF decision while serializer is stalled", 0, 0, FRAME_SYNC, 1);
        repeat (3) step("serializer still stalled", 0, 0, FRAME_KEY);
        step("Bypass RAW and simultaneous AXIS acceptance", 1, 1, FRAME_RAW);
        step("SYNC completion and aging", 1, 1, FRAME_SYNC, 0, 0, 1);
        step("KEY, FIFO full and SPI error", 0, 1, FRAME_KEY, 0, 1, 0, 1, 8'd85);
        step("one third above threshold and full held", 0, 0, FRAME_RAW, 0, 1, 0, 0, 8'd84);
        step("one third below threshold and full held", 0, 0, FRAME_RAW, 0, 1, 0, 0, 8'd86);
        step("FIFO drains");
        step("FIFO refills and reserved type is ignored", 1, 1, 2'b11, 1, 1);
        reset_dut();
        step("first full event after reset", 0, 0, FRAME_RAW, 0, 1);
        step("idle");
    endtask

    task automatic test_wide_hit_rate();
        reset_dut();
        // Установка граничных состояний ускоряет проверку 40-битных произведений.
        force dut.cnt_total_words = 32'hffff_ffff;
        force dut.cnt_key_frames  = 32'h8000_0000;
        model_total = 64'hffff_ffff;
        model_frames[FRAME_KEY] = 64'h8000_0000;
        #1ns;
        release dut.cnt_total_words;
        release dut.cnt_key_frames;
        step("large products, threshold 127", 0, 0, FRAME_RAW, 0, 0, 0, 0, 8'd127);
        step("large products, threshold 128", 0, 0, FRAME_RAW, 0, 0, 0, 0, 8'd128);
    endtask

    task automatic test_saturation();
        reset_dut();
        force dut.cnt_total_words = COUNT_MAX - 32'd1;
        force dut.cnt_key_frames  = COUNT_MAX - 32'd1;
        force dut.cnt_raw_frames  = COUNT_MAX - 32'd1;
        force dut.cnt_sync_frames = COUNT_MAX - 32'd1;
        force dut.cnt_bf_filtered = COUNT_MAX - 32'd1;
        model_total = 64'(COUNT_MAX) - 1;
        foreach (model_frames[i]) model_frames[i] = 64'(COUNT_MAX) - 1;
        model_bf = 64'(COUNT_MAX) - 1;
        #1ns;
        release dut.cnt_total_words;
        release dut.cnt_key_frames;
        release dut.cnt_raw_frames;
        release dut.cnt_sync_frames;
        release dut.cnt_bf_filtered;

        repeat (3) begin
            step("saturating TOTAL/KEY/BF", 1, 1, FRAME_KEY, 1);
            step("saturating RAW", 0, 1, FRAME_RAW);
            step("saturating SYNC", 0, 1, FRAME_SYNC);
        end
        step("threshold equality after saturation", 0, 0, FRAME_RAW, 0, 0, 0, 0, 8'd255);
    endtask

    initial begin
        test_events_and_thresholds();
        test_wide_hit_rate();
        test_saturation();

        reset_dut();
        repeat (1000) begin
            step("random events", 1'($urandom), 1'($urandom), 2'($urandom),
                 1'($urandom), 1'($urandom), 1'($urandom), 1'($urandom), 8'($urandom));
        end

        test_passed = 1'b1;
        $display("PASS tdl_tx_stats (%0d checked cycles)", checked_cycles);
        $finish;
    end

    initial begin
        #1ms;
        $fatal(1, "tdl_tx_stats simulation timeout");
    end
endmodule
