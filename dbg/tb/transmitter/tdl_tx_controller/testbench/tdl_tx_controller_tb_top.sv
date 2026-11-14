`define GREEN_STR(str) ($sformatf("\033[32m%s\033[0m", str))
`define RED_STR(str) ($sformatf("\033[31;1m%s\033[0m", str))
`timescale 1ns/1ns

module tdl_tx_controller_tb_top;

    localparam int CLK_PERIOD = 20;
    localparam logic [7:0] HDR_RAW = 8'hA1;
    localparam logic [7:0] HDR_KEY = 8'hB2;

    logic clk;
    logic rst_n;

    logic fifo_empty;
    logic [31:0] fifo_rdata;
    logic fifo_rd_en;

    logic dict_hit;
    logic [7:0] dict_key;
    logic force_sync;

    logic sdr_data;
    logic sdr_clk;
    logic sdr_ready;

    int error_count = 0;

    tdl_tx_controller #(
        .DATA_WIDTH(32),
        .KEY_WIDTH (8),
        .HDR_RAW   (HDR_RAW),
        .HDR_KEY   (HDR_KEY)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .fifo_empty(fifo_empty),
        .fifo_rdata(fifo_rdata),
        .fifo_rd_en(fifo_rd_en),
        .dict_hit  (dict_hit),
        .dict_key  (dict_key),
        .force_sync(force_sync),
        .sdr_data  (sdr_data),
        .sdr_clk   (sdr_clk),
        .sdr_ready (sdr_ready)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    task automatic initialize;
        rst_n = 1'b0;
        fifo_empty = 1'b1;
        fifo_rdata = '0;
        dict_hit = 1'b0;
        dict_key = '0;
        force_sync = 1'b0;
        sdr_ready = 1'b0;

        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        @(negedge clk);
    endtask

    task automatic send_raw(input logic [31:0] payload);
        logic [39:0] expected_frame;

        expected_frame = {HDR_RAW, payload};
        fifo_rdata = payload;
        fifo_empty = 1'b0;
        sdr_ready = 1'b1;

        for (int bit_index = 0; bit_index < 40; bit_index++) begin
            @(posedge sdr_clk);
            if (sdr_data !== expected_frame[39-bit_index]) begin
                $error(
                    "Time %0t: RAW bit %0d mismatch: expected %b, got %b",
                    $time, bit_index, expected_frame[39-bit_index], sdr_data
                );
                error_count++;
            end
            else begin
                $display("Time %0t: RAW bit %0d transmitted correctly: %b", $time, bit_index, sdr_data);
            end

            if (fifo_rd_en !== (bit_index == 39)) begin
                $error(
                    "FIFO read enable at RAW bit %0d: expected %b, got %b",
                    bit_index, (bit_index == 39), fifo_rd_en
                );
                error_count++;
            end

            @(negedge sdr_clk);
            #1;
            if (fifo_rd_en !== (bit_index == 38)) begin
                $error(
                    "FIFO read enable after RAW bit %0d: expected %b, got %b",
                    bit_index, (bit_index == 38), fifo_rd_en
                );
                error_count++;
            end
        end

        sdr_ready = 1'b0;
        fifo_empty = 1'b1;

        if (fifo_rd_en !== 1'b0) begin
            $error("FIFO read enable remained asserted after RAW frame");
            error_count++;
        end
    endtask

    task automatic send_key(input logic [7:0] key);
        logic [15:0] expected_frame;

        expected_frame = {HDR_KEY, key};
        fifo_rdata = 'h0;
        dict_key = key;
        dict_hit = 1'b1;
        fifo_empty = 1'b0;
        sdr_ready = 1'b1;

        for (int bit_index = 0; bit_index < 16; bit_index++) begin
            @(posedge sdr_clk);
            if (sdr_data !== expected_frame[15-bit_index]) begin
                $error(
                    "Time %0t: KEY bit %0d mismatch: expected %b, got %b",
                    $time, bit_index, expected_frame[15-bit_index], sdr_data
                );
                error_count++;
            end
            else begin
                $display("Time %0t: KEY bit %0d transmitted correctly: %b", $time, bit_index, sdr_data);
            end

            if (fifo_rd_en !== (bit_index == 15)) begin
                $error(
                    "FIFO read enable at KEY bit %0d: expected %b, got %b",
                    bit_index, (bit_index == 15), fifo_rd_en
                );
                error_count++;
            end

            @(negedge sdr_clk);
            #1;
            if (fifo_rd_en !== (bit_index == 14)) begin
                $error(
                    "FIFO read enable after KEY bit %0d: expected %b, got %b",
                    bit_index, (bit_index == 14), fifo_rd_en
                );
                error_count++;
            end
        end

        sdr_ready = 1'b0;
        fifo_empty = 1'b1;
        dict_hit = 1'b0;

        if (fifo_rd_en !== 1'b0) begin
            $error("FIFO read enable remained asserted after KEY frame");
            error_count++;
        end
    endtask

    initial begin
        $timeformat(-9, 0, " ns", 5);
        initialize();

        send_raw(32'h1234_5678);
        send_raw(32'hA5C3_0F81);
        send_key(8'h5A);

        #100;
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "Simulation timeout.");
    end

    final begin
        if (error_count == 0) begin
            $display(`GREEN_STR("All tests passed successfully."));
        end 
        else begin
            $display(`RED_STR("Test completed with %0d errors."), error_count);
        end
    end

endmodule
