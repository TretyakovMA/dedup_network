`define GREEN_STR(str) ($sformatf("\033[32m%s\033[0m", str))
`define RED_STR(str) ($sformatf("\033[31;1m%s\033[0m", str))

module dedup_tx_top_tb;

    localparam int DATA_WIDTH  = 32;
    localparam int FIFO_DEPTH  = 16;
    localparam int BUS_WIDTH   = 8;
    
    localparam int CLK_PERIOD  = 20;
    localparam int RESET_TIME  = 40;

    
    
    logic clk;
    logic rst_n;

    
    axis_if #(BUS_WIDTH)      m_axis(clk, rst_n);
    axis_if #(DATA_WIDTH)     s_axis(clk, rst_n);
    spi_if                    spi_vif(clk, rst_n);

    virtual axis_if #(BUS_WIDTH)    m_axis_vif = m_axis;
    virtual axis_if #(DATA_WIDTH)   s_axis_vif = s_axis;

   
    

    // Экземпляр тестируемого модуля
    dedup_tx_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH),
        .BUS_WIDTH(BUS_WIDTH)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),

        .s_axis_tdata(s_axis.tdata),
        .s_axis_tvalid(s_axis.tvalid),
        .s_axis_tready(s_axis.tready),
        .s_axis_tlast(s_axis.tlast),

        .m_axis_tdata(m_axis.tdata),
        .m_axis_tvalid(m_axis.tvalid),
        .m_axis_tready(m_axis.tready),
        .m_axis_tlast(m_axis.tlast),

        .spi_sclk(spi_vif.sclk),
        .spi_cs_n(spi_vif.cs_n),
        .spi_mosi(spi_vif.mosi),
        .spi_miso(spi_vif.miso)
    );

    // Генерация тактового сигнала
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    task initialize();
        rst_n           = 0;

        m_axis_vif.tvalid = 0;
        m_axis_vif.tdata  = 0;
        m_axis_vif.tlast  = 0;
        spi_vif.sclk = 0;
        spi_vif.cs_n = 1;
        spi_vif.mosi = 0;

        #(RESET_TIME);
        rst_n = 1;
        @(posedge m_axis_vif.clk); 
    endtask


    task single_write_axis();
        @(posedge m_axis_vif.clk); 
        m_axis_vif.tvalid <= 1;
        m_axis_vif.tdata  <= 32'h12345678;
        m_axis_vif.tlast  <= 1;
        s_axis_vif.tready <= 1;
        @(posedge m_axis_vif.clk); 
        m_axis_vif.tvalid <= 0;
        m_axis_vif.tdata  <= 0;
        m_axis_vif.tlast  <= 0;
    endtask

    

    task automatic single_write_spi(input bit [6:0] addr, input bit [7:0] data);
        // Последний бит команды: 0 — запись, 1 — чтение.
        bit[7:0] write_addr = {addr, 1'b0};
        
        
        $display("\n=== SPI WRITE TRANSACTION START ===");
        $display("Time: %0t", $time);
        $display("Address byte (cmd): 0x%02h (bin: %b)", write_addr, write_addr);
        $display("Data byte: 0x%02h (bin: %b)", data, data);
        
        spi_vif.cs_n <= 0;
        @(posedge clk);
        
        // Отправка адреса
        $display("\n--- Sending ADDRESS BYTE ---");
        for (int i = 7; i >= 0; i--) begin
            spi_vif.mosi <= write_addr[i]; 
            @(posedge clk);
            $display("Time %0t: Bit[%0d] = %b, SCLK falling edge", $time, i, write_addr[i]);
            spi_vif.sclk <= 1;
            @(posedge clk);
            spi_vif.sclk <= 0;
        end
        
        $display("\n--- ADDRESS BYTE SENT, waiting 20ns before DATA BYTE ---");
        
        
        // Отправка данных
        $display("\n--- Sending DATA BYTE ---");
        for (int i = 7; i >= 0; i--) begin
            spi_vif.mosi <= data[i]; 
            @(posedge clk);
            $display("Time %0t: Bit[%0d] = %b, SCLK falling edge", $time, i, data[i]);
            spi_vif.sclk <= 1;
            @(posedge clk);
            spi_vif.sclk <= 0;
        end
        
        spi_vif.cs_n <= 1;
        $display("\nTime %0t: CS deasserted, WRITE COMPLETE\n", $time);
    endtask

    task automatic single_read_spi(input bit [6:0] addr, output bit [7:0] data);
        // Последний бит команды: 0 — запись, 1 — чтение.
        bit[7:0] read_addr = {addr, 1'b1}; 
        
        $display("\n=== SPI READ TRANSACTION START ===");
        $display("Time: %0t", $time);
        $display("Address byte (cmd): 0x%02h (bin: %b)", read_addr, read_addr);
        
        spi_vif.cs_n <= 0;
        @(posedge clk);
        
        // Отправка адреса
        $display("\n--- Sending ADDRESS BYTE ---");
        for (int i = 7; i >= 0; i--) begin
            spi_vif.mosi <= read_addr[i]; 
            @(posedge clk);
            $display("Time %0t: Addr Bit[%0d] = %b", $time, i, read_addr[i]);
            spi_vif.sclk <= 1;
            @(posedge clk);
            spi_vif.sclk <= 0;
        end
        
        $display("Time %0t: Starting DATA BYTE reception", $time);
        
        // Приём данных
        $display("\n--- Receiving DATA BYTE ---");
        data = 8'h00;
        for (int i = 7; i >= 0; i--) begin
            spi_vif.mosi <= 0;
            @(posedge clk);
            spi_vif.sclk <= 1;

            @(negedge clk);
            data[i] = spi_vif.miso;
            $display("Time %0t: Data Bit[%0d] captured = %b (MISO = %b)", 
                     $time, i, data[i], spi_vif.miso);

            @(posedge clk);
            spi_vif.sclk <= 0;
        end
        
        spi_vif.cs_n <= 1;
        $display("\nTime %0t: CS deasserted, READ COMPLETE", $time);
        $display("Captured data: 0x%02h (bin: %b)", data, data);
        
    endtask

    

    task timeout();
        #10000;
        $fatal(`RED_STR("Simulation timeout reached. Test failed."));
    endtask

    task automatic test_top();
        bit[7:0] write_data = $urandom();
        bit[7:0] read_data;
        bit[6:0] addr = 7'b0000001; 
        initialize();

        single_write_spi(addr, write_data);
        @(posedge clk);
        single_read_spi(addr, read_data);

        if(write_data == read_data) begin
            $display(`GREEN_STR("SPI Write/Read Test Passed: Written data = %h, Read data = %h"), write_data, read_data);
        end 
        else begin
            $error(`RED_STR("SPI Write/Read Test Failed: Written data = %h, Read data = %h"), write_data, read_data);
        end
        #1000;
        $finish;
    endtask


    initial begin
        $timeformat(-9, 0, " ns", 5);
        fork
            test_top();
            timeout();
        join
    end
endmodule