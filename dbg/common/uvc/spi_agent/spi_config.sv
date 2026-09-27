`ifndef SPI_CONFIG
`define SPI_CONFIG
class spi_config extends uvm_object;
    `uvm_object_utils(spi_config)

    function new(string name = "spi_config");
        super.new(name);
    endfunction: new

    uvm_active_passive_enum is_active = UVM_ACTIVE;

    bit cpol = 0;
    bit cpha = 0;

    int prer = 2; // деление частоты

    realtime clk_period = 10ns;


    function realtime get_clk_period();
        return clk_period;
    endfunction: get_clk_period

    function realtime get_sclk_period();
        return get_clk_period() * prer;
    endfunction: get_sclk_period

    function realtime get_sclk_half_period();
        return get_sclk_period() / 2;
    endfunction: get_sclk_half_period
endclass
`endif
