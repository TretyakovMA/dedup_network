`timescale 1ns/1ns
`define GREEN_STR(str) ($sformatf("\033[32m%s\033[0m", str))
`define RED_STR(str) ($sformatf("\033[31;1m%s\033[0m", str))

module tdl_sdr_timing_tb_top;

    localparam int CLK_PERIOD = 20;

    logic clk;
    logic rst_n;
    logic timing_active;
    logic [15:0] timing_div;
    logic allow_rise;
    logic sdr_clk;
    logic rise_ce;
    logic fall_ce;

    int error_count = 0;
    int observed_rise_count = 0;
    int observed_fall_count = 0;

    tdl_sdr_timing dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .timing_active (timing_active),
        .timing_div    (timing_div),
        .allow_rise    (allow_rise),
        .sdr_clk       (sdr_clk),
        .rise_ce       (rise_ce),
        .fall_ce       (fall_ce)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    task automatic check_condition(input logic condition, input string message);
        if (condition !== 1'b1) begin
            $error("Time %0t: %s", $time, message);
            error_count = error_count + 1;
        end
    endtask

    task automatic tick(
        input logic expected_clk,
        input logic expected_rise,
        input logic expected_fall
    );
        logic old_clk;
        logic sampled_rise;
        logic sampled_fall;
        begin
            @(posedge clk);
            old_clk = sdr_clk;
            sampled_rise = rise_ce;
            sampled_fall = fall_ce;
            #1;

            check_condition(sdr_clk === expected_clk,
                            "sdr_clk phase after clk edge was incorrect");
            check_condition(sampled_rise === expected_rise,
                            "rise_ce before clk edge was incorrect");
            check_condition(sampled_fall === expected_fall,
                            "fall_ce before clk edge was incorrect");
            check_condition(!(sampled_rise && sampled_fall),
                            "rise_ce and fall_ce were active together");

            if (sampled_rise) begin
                observed_rise_count = observed_rise_count + 1;
                check_condition(!old_clk && sdr_clk,
                                "rise_ce did not correspond to a low-to-high transition");
            end
            if (sampled_fall) begin
                observed_fall_count = observed_fall_count + 1;
                check_condition(old_clk && !sdr_clk,
                                "fall_ce did not correspond to a high-to-low transition");
            end
        end
    endtask

    task automatic reset_dut;
        begin
            @(negedge clk);
            rst_n = 1'b0;
            timing_active = 1'b0;
            allow_rise = 1'b0;
            #1;
            check_condition(!sdr_clk && !rise_ce && !fall_ce,
                            "asynchronous reset did not clear phase and events");
            tick(1'b0, 1'b0, 1'b0);
            tick(1'b0, 1'b0, 1'b0);
            @(negedge clk);
            rst_n = 1'b1;
            #1;
            check_condition(!sdr_clk && !rise_ce && !fall_ce,
                            "reset release changed the idle phase or events");
        end
    endtask

    initial begin : run_tests
        int i;

        rst_n = 1'b0;
        timing_active = 1'b0;
        timing_div = 16'd0;
        allow_rise = 1'b0;

        repeat (2) @(posedge clk);
        #1;
        check_condition(!sdr_clk && !rise_ce && !fall_ce,
                        "initial reset outputs were incorrect");
        @(negedge clk);
        rst_n = 1'b1;
        #1;
        tick(1'b0, 1'b0, 1'b0);
        tick(1'b0, 1'b0, 1'b0);

        // D=0 toggles on every clk edge once transmission is enabled.
        @(negedge clk);
        timing_div = 16'd0;
        timing_active = 1'b1;
        allow_rise = 1'b1;
        tick(1'b1, 1'b1, 1'b0);
        tick(1'b0, 1'b0, 1'b1);
        tick(1'b1, 1'b1, 1'b0);
        tick(1'b0, 1'b0, 1'b1);

        reset_dut();

        // D=1 gives two clk periods for each high and low phase.
        @(negedge clk);
        timing_div = 16'd1;
        timing_active = 1'b1;
        allow_rise = 1'b1;
        tick(1'b0, 1'b0, 1'b0);
        tick(1'b1, 1'b1, 1'b0);
        tick(1'b1, 1'b0, 1'b0);
        tick(1'b0, 1'b0, 1'b1);
        tick(1'b0, 1'b0, 1'b0);
        tick(1'b1, 1'b1, 1'b0);

        reset_dut();

        // A 32-bit word has 32 sampled rises and 32 completed high phases.
        @(negedge clk);
        timing_div = 16'd1;
        timing_active = 1'b1;
        allow_rise = 1'b1;
        observed_rise_count = 0;
        observed_fall_count = 0;
        for (i = 0; i < 32; i = i + 1) begin
            tick(1'b0, 1'b0, 1'b0);
            tick(1'b1, 1'b1, 1'b0);
            tick(1'b1, 1'b0, 1'b0);
            if (i == 31) begin
                @(negedge clk);
                allow_rise = 1'b0;
            end
            tick(1'b0, 1'b0, 1'b1);
        end
        @(negedge clk);
        timing_active = 1'b0;
        tick(1'b0, 1'b0, 1'b0);
        check_condition(observed_rise_count == 32,
                        "32-bit transfer did not produce exactly 32 rises");
        check_condition(observed_fall_count == 32,
                        "32-bit transfer did not complete exactly 32 high phases");

        reset_dut();

        // Verify the inclusive terminal count for a nontrivial divider.
        @(negedge clk);
        timing_div = 16'd24;
        timing_active = 1'b1;
        allow_rise = 1'b1;
        for (i = 0; i < 24; i = i + 1)
            tick(1'b0, 1'b0, 1'b0);
        tick(1'b1, 1'b1, 1'b0);
        for (i = 0; i < 24; i = i + 1)
            tick(1'b1, 1'b0, 1'b0);
        tick(1'b0, 1'b0, 1'b1);

        reset_dut();

        // D=65535 must represent 65536 clk periods without counter overflow.
        @(negedge clk);
        timing_div = 16'hFFFF;
        timing_active = 1'b1;
        allow_rise = 1'b1;
        for (i = 0; i < 65535; i = i + 1)
            tick(1'b0, 1'b0, 1'b0);
        tick(1'b1, 1'b1, 1'b0);
        for (i = 0; i < 65535; i = i + 1)
            tick(1'b1, 1'b0, 1'b0);
        tick(1'b0, 1'b0, 1'b1);

        reset_dut();

        // A low-phase stall clears partial progress; a high phase still ends.
        @(negedge clk);
        timing_div = 16'd2;
        timing_active = 1'b1;
        allow_rise = 1'b1;
        tick(1'b0, 1'b0, 1'b0);
        @(negedge clk);
        allow_rise = 1'b0;
        tick(1'b0, 1'b0, 1'b0);
        @(negedge clk);
        allow_rise = 1'b1;
        tick(1'b0, 1'b0, 1'b0);
        tick(1'b0, 1'b0, 1'b0);
        tick(1'b1, 1'b1, 1'b0);
        @(negedge clk);
        timing_active = 1'b0;
        allow_rise = 1'b0;
        tick(1'b1, 1'b0, 1'b0);
        tick(1'b1, 1'b0, 1'b0);
        tick(1'b0, 1'b0, 1'b1);
        tick(1'b0, 1'b0, 1'b0);

        // Reset asynchronously aborts a high phase without a fall event.
        @(negedge clk);
        timing_div = 16'd3;
        timing_active = 1'b1;
        allow_rise = 1'b1;
        tick(1'b0, 1'b0, 1'b0);
        tick(1'b0, 1'b0, 1'b0);
        tick(1'b0, 1'b0, 1'b0);
        tick(1'b1, 1'b1, 1'b0);
        #2;
        rst_n = 1'b0;
        #1;
        check_condition(!sdr_clk && !rise_ce && !fall_ce,
                        "reset during a high phase generated a transition event");
        tick(1'b0, 1'b0, 1'b0);

        if (error_count == 0) begin
            $display(`GREEN_STR("All SDR timing tests passed."));
            $finish;
        end
        else begin
            $fatal(1, `RED_STR($sformatf("SDR timing test completed with %0d errors.",
                                        error_count)));
        end
    end

    initial begin
        #10000000;
        $fatal(1, "Simulation timeout.");
    end

endmodule
