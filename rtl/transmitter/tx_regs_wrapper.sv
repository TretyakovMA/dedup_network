module tx_regs_wrapper (
    apb_if.slave                       s_apb,
    input  tx_regs_pkg::tx_regs__in_t  hwif_in,
    output tx_regs_pkg::tx_regs__out_t hwif_out
);

    // Экземпляр внутреннего интерфейса, ожидаемого PeakRDL
    apb3_intf internal_apb();

    // Трансляция управляющих сигналов из вашего apb_if во внутренний интерфейс
    assign internal_apb.PADDR   = s_apb.paddr[5:0];
    assign internal_apb.PSEL    = s_apb.psel;
    assign internal_apb.PENABLE = s_apb.penable;
    assign internal_apb.PWRITE  = s_apb.pwrite;
    assign internal_apb.PWDATA  = s_apb.pwdata;

    // Трансляция ответных сигналов обратно в ваш apb_if
    assign s_apb.pready  = internal_apb.PREADY;
    assign s_apb.prdata  = internal_apb.PRDATA;
    assign s_apb.pslverr = internal_apb.PSLVERR;

    // Инстанцирование сгенерированного PeakRDL модуля
    tx_regs u_tx_regs (
        .clk      (s_apb.clk),
        .rst      (~s_apb.rst_n), 
        .s_apb    (internal_apb.slave),
        .hwif_in  (hwif_in),
        .hwif_out (hwif_out)
    );

endmodule