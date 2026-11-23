interface spi_irq_check_if(input logic clk, input logic rst_n, input logic irq);
    int unsigned accesses, errors;

    modport monitor(input clk, rst_n, irq, accesses, errors);
endinterface
