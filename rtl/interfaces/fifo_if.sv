interface fifo_if #(
    parameter int WIDTH = 8
) (
    input logic clk, 
    input logic rst_n
);
   
    // Сигнальные линии
    logic [WIDTH-1:0] w_data;
    logic       w_en;
    logic       full;
    logic [WIDTH-1:0] r_data;
    logic       r_en;
    logic       empty;

    // Блок синхронизации для Тестбенча (Драйвер и Монитор)
    clocking cb @(posedge clk);
        default input #1ns output #1ns; 
        output w_data, w_en, r_en;
        input  full, r_data, empty;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1ns; 
        input w_data, w_en, full, r_data, r_en, empty;
    endclocking

    modport rtl (
        input  clk, rst_n,
        input  w_data, w_en, r_en,
        output full, r_data, empty
    );
    
endinterface