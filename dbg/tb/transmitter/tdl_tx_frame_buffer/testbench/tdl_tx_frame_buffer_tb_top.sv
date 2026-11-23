`timescale 1ns/1ns
`define GREEN_STR(str) ($sformatf("\033[32m%s\033[0m", str))
`define RED_STR(str) ($sformatf("\033[31;1m%s\033[0m", str))

module tdl_tx_frame_buffer_tb_top;

    import tdl_tx_pkg::*;

    localparam int CLK_PERIOD = 20;

    typedef struct packed {
        logic [1:0]  desc_type;
        logic [7:0]  desc_key;
        logic [31:0] desc_data;
    } descriptor_t;

    logic clk;
    logic rst_n;

    logic        s_desc_valid;
    logic        s_desc_ready;
    logic [1:0]  s_desc_type;
    logic [7:0]  s_desc_key;
    logic [31:0] s_desc_data;

    logic        m_desc_valid;
    logic        m_desc_ready;
    logic [1:0]  m_desc_type;
    logic [7:0]  m_desc_key;
    logic [31:0] m_desc_data;

    descriptor_t expected_queue[$];
    descriptor_t expected_desc;
    int error_count = 0;
    int push_count = 0;
    int pop_count = 0;

    tdl_tx_frame_buffer #(
        .DATA_WIDTH(32),
        .DICT_SIZE (256)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_desc_valid (s_desc_valid),
        .s_desc_ready (s_desc_ready),
        .s_desc_type  (s_desc_type),
        .s_desc_key   (s_desc_key),
        .s_desc_data  (s_desc_data),
        .m_desc_valid (m_desc_valid),
        .m_desc_ready (m_desc_ready),
        .m_desc_type  (m_desc_type),
        .m_desc_key   (m_desc_key),
        .m_desc_data  (m_desc_data)
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

    always @(posedge clk) begin
        if (!rst_n) begin
            expected_queue.delete();
            push_count = 0;
            pop_count = 0;
        end
        else begin
            check_condition(m_desc_valid === (expected_queue.size() != 0),
                            "m_desc_valid did not match the reference queue");
            check_condition(s_desc_ready ===
                            ((expected_queue.size() == 0) || m_desc_ready),
                            "s_desc_ready did not match buffer occupancy");

            if (expected_queue.size() != 0) begin
                expected_desc = expected_queue[0];
                check_condition(m_desc_type === expected_desc.desc_type,
                                "output descriptor type mismatch");
                check_condition(m_desc_key === expected_desc.desc_key,
                                "output descriptor key mismatch");
                check_condition(m_desc_data === expected_desc.desc_data,
                                "output descriptor data mismatch");
            end

            if (m_desc_valid && m_desc_ready) begin
                check_condition(expected_queue.size() != 0,
                                "pop occurred while the reference queue was empty");
                if (expected_queue.size() != 0)
                    void'(expected_queue.pop_front());
                pop_count = pop_count + 1;
            end

            if (s_desc_valid && s_desc_ready) begin
                expected_desc.desc_type = s_desc_type;
                expected_desc.desc_key  = s_desc_key;
                expected_desc.desc_data = s_desc_data;
                expected_queue.push_back(expected_desc);
                push_count = push_count + 1;
            end

            check_condition(expected_queue.size() <= 1,
                            "reference queue exceeded one descriptor");
            check_condition((push_count >= pop_count) &&
                            ((push_count - pop_count) == expected_queue.size()),
                            "push/pop occupancy invariant failed");
        end
    end

    task automatic drive_cycle(
        input logic        valid,
        input logic [1:0]  desc_type,
        input logic [7:0]  desc_key,
        input logic [31:0] desc_data,
        input logic        ready
    );
        @(negedge clk);
        s_desc_valid = valid;
        s_desc_type  = desc_type;
        s_desc_key   = desc_key;
        s_desc_data  = desc_data;
        m_desc_ready = ready;
        @(posedge clk);
        #1;
    endtask

    task automatic reset_buffer;
        @(negedge clk);
        rst_n = 1'b0;
        s_desc_valid = 1'b0;
        m_desc_ready = 1'b0;
        #1;
        check_condition(!s_desc_ready && !m_desc_valid,
                        "ready/valid were not suppressed during reset");
        repeat (2) @(posedge clk);
        #1;
        check_condition(!m_desc_valid, "reset did not empty the buffer");
        @(negedge clk);
        rst_n = 1'b1;
        #1;
        check_condition(s_desc_ready && !m_desc_valid,
                        "empty buffer was not ready after reset");
    endtask

    task automatic random_traffic(input int descriptor_count);
        int sent;
        int cycles;
        logic pending;

        sent = 0;
        cycles = 0;
        pending = 1'b0;
        while ((sent < descriptor_count) || pending) begin
            @(negedge clk);
            cycles = cycles + 1;
            if (!pending && (sent < descriptor_count) &&
                ($urandom_range(0, 3) != 0)) begin
                s_desc_valid = 1'b1;
                s_desc_type  = $urandom_range(0, 2);
                case ($urandom_range(0, 3))
                    0: s_desc_key = 8'h00;
                    1: s_desc_key = 8'h01;
                    2: s_desc_key = 8'h7F;
                    default: s_desc_key = 8'hFF;
                endcase
                s_desc_data = $urandom;
                pending = 1'b1;
                sent = sent + 1;
            end
            else begin
                s_desc_valid = pending;
            end
            m_desc_ready = $urandom_range(0, 1);

            @(posedge clk);
            if (s_desc_valid && s_desc_ready)
                pending = 1'b0;

            if (cycles >= 2000) begin
                check_condition(1'b0, "random traffic source timed out");
                break;
            end
        end

        drive_cycle(1'b0, FRAME_RAW, 8'h00, 32'h0000_0000, 1'b1);
        repeat (2)
            drive_cycle(1'b0, FRAME_RAW, 8'h00, 32'h0000_0000, 1'b1);
    endtask

    initial begin
        rst_n = 1'b0;
        s_desc_valid = 1'b0;
        s_desc_type = FRAME_RAW;
        s_desc_key = '0;
        s_desc_data = '0;
        m_desc_ready = 1'b0;

        repeat (2) @(posedge clk);
        #1;
        check_condition(!m_desc_valid && !s_desc_ready,
                        "initial reset outputs were incorrect");
        @(negedge clk);
        rst_n = 1'b1;
        #1;
        check_condition(s_desc_ready && !m_desc_valid,
                        "buffer was not empty and ready after initial reset");

        // Accept into an empty buffer while stalled; payload must remain stable.
        drive_cycle(1'b1, FRAME_RAW, 8'h00, 32'h0123_4567, 1'b0);
        repeat (4)
            drive_cycle(1'b0, FRAME_RAW, 8'h00, 32'h0000_0000, 1'b0);
        check_condition(m_desc_valid && m_desc_type == FRAME_RAW &&
                        m_desc_key == 8'h00 && m_desc_data == 32'h0123_4567,
                        "stalled descriptor was not held unchanged");
        drive_cycle(1'b0, FRAME_RAW, 8'h00, 32'h0000_0000, 1'b1);
        check_condition(!m_desc_valid, "descriptor was not removed after pop");

        // Ready on the input side must not create fall-through to the output.
        drive_cycle(1'b1, FRAME_KEY, 8'hFF, 32'h89AB_CDEF, 1'b1);
        check_condition(m_desc_valid && m_desc_type == FRAME_KEY &&
                        m_desc_key == 8'hFF && m_desc_data == 32'h89AB_CDEF,
                        "empty-buffer push incorrectly fell through to output");
        drive_cycle(1'b0, FRAME_RAW, 8'h00, 32'h0000_0000, 1'b1);
        check_condition(!m_desc_valid, "single descriptor was output more than once");

        // Simultaneous pop/push replaces the old descriptor without a bubble.
        drive_cycle(1'b1, FRAME_SYNC, 8'h01, 32'hCAFE_0001, 1'b0);
        drive_cycle(1'b1, FRAME_RAW, 8'h7F, 32'hBEEF_0002, 1'b1);
        check_condition(m_desc_valid && m_desc_type == FRAME_RAW &&
                        m_desc_key == 8'h7F && m_desc_data == 32'hBEEF_0002,
                        "simultaneous replacement lost or corrupted new descriptor");
        drive_cycle(1'b1, FRAME_KEY, 8'h00, 32'hDEAD_0003, 1'b1);
        check_condition(m_desc_valid && m_desc_type == FRAME_KEY &&
                        m_desc_key == 8'h00 && m_desc_data == 32'hDEAD_0003,
                        "back-to-back replacement inserted a bubble");
        drive_cycle(1'b0, FRAME_RAW, 8'h00, 32'h0000_0000, 1'b1);
        check_condition(!m_desc_valid, "replacement sequence did not drain");

        // Reset must discard a pending descriptor and clear the reference model.
        drive_cycle(1'b1, FRAME_SYNC, 8'hFF, 32'hFFFF_FFFF, 1'b0);
        reset_buffer();

        random_traffic(128);
        check_condition(expected_queue.size() == 0,
                        "reference queue was not empty at test completion");
        check_condition(push_count == pop_count,
                        "accepted and emitted descriptor counts differ");
        check_condition(push_count >= 128,
                        "random traffic did not exercise enough descriptors");

        if (error_count == 0) begin
            $display(`GREEN_STR($sformatf("All frame buffer tests passed (%0d descriptors).",
                                          push_count)));
            $finish;
        end
        else begin
            $fatal(1, `RED_STR($sformatf("Frame buffer test completed with %0d errors.",
                                        error_count)));
        end
    end

    initial begin
        #100000;
        $fatal(1, "Simulation timeout.");
    end

endmodule
