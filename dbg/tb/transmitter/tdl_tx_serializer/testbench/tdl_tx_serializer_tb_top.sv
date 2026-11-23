`timescale 1ns/1ns
`define GREEN_STR(str) ($sformatf("\033[32m%s\033[0m", str))
`define RED_STR(str) ($sformatf("\033[31;1m%s\033[0m", str))

module tdl_tx_serializer_tb_top;

    localparam int CLK_PERIOD = 20;
    localparam int DICT_SIZE  = 4;

    localparam logic [1:0] FRAME_RAW  = 2'b00;
    localparam logic [1:0] FRAME_KEY  = 2'b01;
    localparam logic [1:0] FRAME_SYNC = 2'b10;

    logic clk;
    logic rst_n;
    logic tx_en;
    logic [15:0] sdr_clk_div;
    logic busy;
    logic frame_done;
    logic [1:0] frame_done_type;
    logic desc_valid;
    logic desc_ready;
    logic [1:0] desc_type;
    logic [7:0] desc_key;
    logic [31:0] desc_data;
    logic sdr_data;
    logic sdr_clk;
    logic sdr_ready;

    int error_count = 0;

    tdl_tx_serializer #(
        .DATA_WIDTH(32),
        .DICT_SIZE (DICT_SIZE)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .tx_en            (tx_en),
        .sdr_clk_div      (sdr_clk_div),
        .busy             (busy),
        .frame_done       (frame_done),
        .frame_done_type  (frame_done_type),
        .desc_valid       (desc_valid),
        .desc_ready       (desc_ready),
        .desc_type        (desc_type),
        .desc_key         (desc_key),
        .desc_data        (desc_data),
        .sdr_data         (sdr_data),
        .sdr_clk          (sdr_clk),
        .sdr_ready        (sdr_ready)
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

    task automatic reset_dut;
        begin
            @(negedge clk);
            rst_n      = 1'b0;
            tx_en      = 1'b0;
            desc_valid = 1'b0;
            sdr_ready  = 1'b0;
            #1;
            check_condition(!busy && !desc_ready && !frame_done &&
                            !sdr_clk && !sdr_data,
                            "reset did not clear serializer outputs");
            repeat (2) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;
            tx_en = 1'b1;
            #1;
            check_condition(desc_ready, "idle serializer was not ready after reset");
        end
    endtask

    task automatic transmit_and_check(
        input logic [1:0] frame_type,
        input logic [7:0] key,
        input logic [31:0] data,
        input logic [15:0] divider,
        input logic stall_initially,
        input logic inject_stall
    );
        logic [7:0] expected_bytes [0:5];
        int byte_count;
        int captured_bits;
        int cycle_count;
        int last_edge_cycle;
        int edge_delta;
        logic stall_injected;
        logic previous_sdr_clk;
        logic [1:0] live_type;
        logic [7:0] live_key;
        logic [31:0] live_data;
        logic [15:0] live_divider;
        begin
            for (int i = 0; i < 6; i = i + 1)
                expected_bytes[i] = 8'h00;

            case (frame_type)
                FRAME_RAW: begin
                    byte_count = 5;
                    expected_bytes[0] = 8'hA1;
                    expected_bytes[1] = data[31:24];
                    expected_bytes[2] = data[23:16];
                    expected_bytes[3] = data[15:8];
                    expected_bytes[4] = data[7:0];
                end
                FRAME_KEY: begin
                    byte_count = 2;
                    expected_bytes[0] = 8'hB2;
                    expected_bytes[1] = key;
                end
                FRAME_SYNC: begin
                    byte_count = 6;
                    expected_bytes[0] = 8'hC3;
                    expected_bytes[1] = key;
                    expected_bytes[2] = data[31:24];
                    expected_bytes[3] = data[23:16];
                    expected_bytes[4] = data[15:8];
                    expected_bytes[5] = data[7:0];
                end
                default: begin
                    byte_count = 0;
                    check_condition(1'b0, "test requested an unsupported frame type");
                end
            endcase

            @(negedge clk);
            desc_type   = frame_type;
            desc_key    = key;
            desc_data   = data;
            sdr_clk_div = divider;
            desc_valid  = 1'b1;
            sdr_ready   = !stall_initially;
            #1;
            check_condition(desc_ready, "descriptor was not ready in enabled IDLE");

            @(posedge clk);
            #1;
            check_condition(busy, "serializer did not accept the descriptor");
            check_condition(!desc_ready, "serializer remained ready while busy");
            check_condition(sdr_data === 1'b1,
                            "serializer did not present the first header bit");

            @(negedge clk);
            desc_valid = 1'b0;

            // Change live inputs after handshake; the active frame must use its snapshot.
            live_type    = ~frame_type;
            live_key     = ~key;
            live_data    = ~data;
            live_divider = divider + 16'd3;
            desc_type    = live_type;
            desc_key     = live_key;
            desc_data    = live_data;
            sdr_clk_div  = live_divider;

            if (stall_initially) begin
                repeat (4) begin
                    @(posedge clk);
                    #1;
                    check_condition(busy && !sdr_clk && !frame_done,
                                    "serializer advanced before sdr_ready");
                end
                @(negedge clk);
                sdr_ready = 1'b1;
            end

            captured_bits = 0;
            cycle_count = 0;
            last_edge_cycle = 0;
            stall_injected = 1'b0;
            previous_sdr_clk = 1'b0;

            while (!frame_done && (cycle_count < 2000)) begin
                @(posedge clk);
                #1;
                cycle_count = cycle_count + 1;

                if (sdr_clk && !previous_sdr_clk) begin
                    if (captured_bits < byte_count * 8) begin
                        check_condition(
                            sdr_data ===
                                expected_bytes[captured_bits / 8][7-(captured_bits % 8)],
                            $sformatf("frame %b bit %0d was incorrect",
                                      frame_type, captured_bits)
                        );
                    end
                    else begin
                        check_condition(1'b0, "serializer emitted too many bits");
                    end
                    captured_bits = captured_bits + 1;
                    edge_delta = cycle_count - last_edge_cycle;
                    check_condition(edge_delta >= (int'(divider) + 1),
                                    "SDR rising edges were faster than the configured divider");
                    last_edge_cycle = cycle_count;
                end
                else if (!sdr_clk && previous_sdr_clk) begin
                    edge_delta = cycle_count - last_edge_cycle;
                    check_condition(edge_delta == (int'(divider) + 1),
                                    "SDR high phase did not match the captured divider");
                    last_edge_cycle = cycle_count;
                end

                previous_sdr_clk = sdr_clk;

                if (inject_stall && !stall_injected &&
                    (captured_bits == 8) && !sdr_clk) begin
                    stall_injected = 1'b1;
                    @(negedge clk);
                    sdr_ready = 1'b0;
                    tx_en = 1'b0;
                    repeat (4) begin
                        @(posedge clk);
                        #1;
                        check_condition(!sdr_clk && busy && !frame_done,
                                        "serializer did not hold position during low-phase stall");
                    end
                    @(negedge clk);
                    tx_en = 1'b1;
                    sdr_ready = 1'b1;
                end
            end

            check_condition(cycle_count < 2000, "frame transmission timed out");
            check_condition(captured_bits == byte_count * 8,
                            "serializer emitted an incorrect number of bits");
            check_condition(frame_done, "frame_done was not asserted at frame completion");
            check_condition(frame_done_type === frame_type,
                            "frame_done_type did not match the transmitted frame");
            check_condition(!busy && !sdr_clk,
                            "serializer did not return idle after the final falling edge");

            @(posedge clk);
            #1;
            check_condition(!frame_done, "frame_done lasted longer than one clk cycle");
        end
    endtask

    initial begin : run_tests
        rst_n = 1'b0;
        tx_en = 1'b0;
        sdr_clk_div = 16'd0;
        desc_valid = 1'b0;
        desc_type = FRAME_RAW;
        desc_key = 8'd0;
        desc_data = 32'd0;
        sdr_ready = 1'b0;

        reset_dut();

        @(negedge clk);
        tx_en = 1'b0;
        #1;
        check_condition(!desc_ready, "tx_en=0 did not block descriptor acceptance");
        @(negedge clk);
        tx_en = 1'b1;

        transmit_and_check(FRAME_RAW, 8'h00, 32'h12_34_56_78,
                           16'd0, 1'b1, 1'b0);
        transmit_and_check(FRAME_KEY, 8'h03, 32'hA5_C3_0F_81,
                           16'd2, 1'b0, 1'b0);
        transmit_and_check(FRAME_SYNC, 8'h02, 32'hDE_AD_BE_EF,
                           16'd1, 1'b0, 1'b1);

        if (error_count == 0) begin
            $display(`GREEN_STR("All serializer tests passed."));
            $finish;
        end
        else begin
            $fatal(1, `RED_STR($sformatf("Serializer test completed with %0d errors.",
                                        error_count)));
        end
    end

    initial begin
        #100000;
        $fatal(1, "Simulation timeout.");
    end

endmodule
