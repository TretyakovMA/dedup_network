// этот инетрфейс используется для подключения к 
// модели регистров, сгенерированной peakrdl
interface apb3_intf;
    logic [5:0] PADDR;
    logic       PSEL;
    logic       PENABLE;
    logic       PWRITE;
    logic [7:0] PWDATA;
    logic       PREADY;
    logic [7:0] PRDATA;
    logic       PSLVERR;

    modport slave (
        input  PADDR, PSEL, PENABLE, PWRITE, PWDATA,
        output PREADY, PRDATA, PSLVERR
    );
    
    modport master (
        output PADDR, PSEL, PENABLE, PWRITE, PWDATA,
        input  PREADY, PRDATA, PSLVERR
    );
endinterface