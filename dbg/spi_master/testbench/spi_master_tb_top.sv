module spi_master_tb_top;
    logic clk;
    logic rst_n;
    logic start;
    logic [7:0] tx_data;
    logic [7:0] rx_data;
    logic ready;

    logic sclk;
    logic cs_n;
    logic mosi;
    logic miso;

    bit[7:0] miso_data;

    spi_master #(
        .CLK_DIV(2)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .tx_data(tx_data),
        .rx_data(rx_data),
        .ready(ready),
        .sclk(sclk),
        .cs_n(cs_n),
        .mosi(mosi),
        .miso(miso)
    );

    initial begin
        clk = 0;
        forever #(10) clk = ~clk;
    end

    task timeout();
        #10000;
    endtask


    task drive_miso(input logic [7:0] data);
        foreach (data[i]) begin
            miso = data[i];
            @(negedge sclk);
        end
    endtask


    task drive_req(input logic [7:0] data);
        tx_data = data;
        start   = 1;
        wait (ready == 0);
        start = 0;

        wait (ready == 1);
    endtask

    task test();
        $timeformat(-9, 0, " ns", 5);
        rst_n   = 0;
        start   = 0;
        tx_data = 8'h00;
        miso    = 1'b0;

        
        #(20);
        rst_n = 1;

        repeat (2) begin
            miso_data = $urandom;
            tx_data   = $urandom;
            
            $display("Time: %0t, Driving request with tx_data: %b, expecting rx_data: %b", $time, tx_data, miso_data);
            fork
                drive_req(tx_data);
                drive_miso(miso_data);
            join

            $display("Time: %0t, Received rx_data: %b", $time, rx_data);
        end

        #200;
    endtask

    initial begin
        fork
            test();
            timeout();
        join_any
        $finish;
    end
endmodule