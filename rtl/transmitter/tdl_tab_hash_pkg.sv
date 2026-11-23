`ifndef TDL_TAB_HASH_PKG
`define TDL_TAB_HASH_PKG
// Общие таблицы TinyLFU и функции детерминированной генерации и выборки.
package tdl_tab_hash_pkg;
    localparam logic [31:0] TABLE_SEED = 32'h5444_4C06;
    localparam integer TABLE_VERSION = 2;

    typedef logic [256*12-1:0] hash_table12_t;
    typedef logic [256*8-1:0] hash_table8_t;

    function automatic logic [31:0] mix32(input logic [31:0] value);
        logic [31:0] mixed;
        begin
            mixed = value;
            mixed = mixed ^ (mixed >> 16);
            mixed = mixed * 32'h85EB_CA6B;
            mixed = mixed ^ (mixed >> 13);
            mixed = mixed * 32'hC2B2_AE35;
            mixed = mixed ^ (mixed >> 16);
            mix32 = mixed;
        end
    endfunction

    function automatic hash_table12_t make_table12(
        input integer hash_index,
        input integer byte_index
    );
        logic [31:0] value;
        integer entry;
        begin
            for (entry = 0; entry < 256; entry = entry + 1) begin
                value = TABLE_SEED
                    ^ ((hash_index + 1) * 32'h9E37_79B9)
                    ^ ((byte_index + 1) * 32'h85EB_CA6B)
                    ^ ((entry + 1) * 32'hC2B2_AE35);
                value = mix32(value);
                make_table12[entry*12 +: 12] = value[11:0];
            end
        end
    endfunction

    function automatic hash_table8_t make_table8(
        input integer hash_index,
        input integer byte_index
    );
        logic [31:0] value;
        integer entry;
        begin
            for (entry = 0; entry < 256; entry = entry + 1) begin
                value = TABLE_SEED
                    ^ ((hash_index + 1) * 32'h9E37_79B9)
                    ^ ((byte_index + 1) * 32'h85EB_CA6B)
                    ^ ((entry + 1) * 32'hC2B2_AE35);
                value = mix32(value);
                make_table8[entry*8 +: 8] = value[7:0];
            end
        end
    endfunction

    function automatic logic [11:0] lookup12(
        input hash_table12_t table_data,
        input logic [7:0] index
    );
        lookup12 = table_data[index*12 +: 12];
    endfunction

    function automatic logic [7:0] lookup8(
        input hash_table8_t table_data,
        input logic [7:0] index
    );
        lookup8 = table_data[index*8 +: 8];
    endfunction

    // Эти вызовы вычисляются при elaboration. В тракте данных используются готовые таблицы.
    localparam hash_table12_t BF1_B0 = make_table12(0, 0);
    localparam hash_table12_t BF1_B1 = make_table12(0, 1);
    localparam hash_table12_t BF1_B2 = make_table12(0, 2);
    localparam hash_table12_t BF1_B3 = make_table12(0, 3);
    localparam hash_table12_t BF2_B0 = make_table12(1, 0);
    localparam hash_table12_t BF2_B1 = make_table12(1, 1);
    localparam hash_table12_t BF2_B2 = make_table12(1, 2);
    localparam hash_table12_t BF2_B3 = make_table12(1, 3);
    localparam hash_table8_t CMS1_B0 = make_table8(2, 0);
    localparam hash_table8_t CMS1_B1 = make_table8(2, 1);
    localparam hash_table8_t CMS1_B2 = make_table8(2, 2);
    localparam hash_table8_t CMS1_B3 = make_table8(2, 3);
    localparam hash_table8_t CMS2_B0 = make_table8(3, 0);
    localparam hash_table8_t CMS2_B1 = make_table8(3, 1);
    localparam hash_table8_t CMS2_B2 = make_table8(3, 2);
    localparam hash_table8_t CMS2_B3 = make_table8(3, 3);
endpackage
`endif
