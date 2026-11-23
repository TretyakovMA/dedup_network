`ifndef TDL_TAB_HASH
`define TDL_TAB_HASH
// Вычисляет и регистрирует четыре табличных хэша слова для Bloom Filter и CMS.
module tdl_tab_hash (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        in_valid,
    output logic        in_ready,
    input  logic [31:0] data_in,
    output logic        out_valid,
    input  logic        out_ready,
    output logic [11:0] h_bf1,
    output logic [11:0] h_bf2,
    output logic [7:0]  h_cms1,
    output logic [7:0]  h_cms2
);
    import tdl_tab_hash_pkg::*;

    logic [11:0] h_bf1_comb;
    logic [11:0] h_bf2_comb;
    logic [7:0]  h_cms1_comb;
    logic [7:0]  h_cms2_comb;

    // Регистр результата может принять новое слово на фронте выдачи предыдущих хэшей.
    assign in_ready = rst_n && (!out_valid || out_ready);

    // Каждый из четырёх хэшей объединяет XOR-ом выборки из собственных таблиц по байтам слова.
    assign h_bf1_comb =
        lookup12(BF1_B0, data_in[7:0]) ^
        lookup12(BF1_B1, data_in[15:8]) ^
        lookup12(BF1_B2, data_in[23:16]) ^
        lookup12(BF1_B3, data_in[31:24]);

    assign h_bf2_comb =
        lookup12(BF2_B0, data_in[7:0]) ^
        lookup12(BF2_B1, data_in[15:8]) ^
        lookup12(BF2_B2, data_in[23:16]) ^
        lookup12(BF2_B3, data_in[31:24]);

    assign h_cms1_comb =
        lookup8(CMS1_B0, data_in[7:0]) ^
        lookup8(CMS1_B1, data_in[15:8]) ^
        lookup8(CMS1_B2, data_in[23:16]) ^
        lookup8(CMS1_B3, data_in[31:24]);

    assign h_cms2_comb =
        lookup8(CMS2_B0, data_in[7:0]) ^
        lookup8(CMS2_B1, data_in[15:8]) ^
        lookup8(CMS2_B2, data_in[23:16]) ^
        lookup8(CMS2_B3, data_in[31:24]);

    // При остановке потребителя все четыре хэша и out_valid сохраняются вместе.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            h_bf1     <= '0;
            h_bf2     <= '0;
            h_cms1    <= '0;
            h_cms2    <= '0;
        end else if (in_ready) begin
            out_valid <= in_valid;
            if (in_valid) begin
                h_bf1  <= h_bf1_comb;
                h_bf2  <= h_bf2_comb;
                h_cms1 <= h_cms1_comb;
                h_cms2 <= h_cms2_comb;
            end
        end
    end

endmodule
`endif
