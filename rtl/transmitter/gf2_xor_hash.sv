module gf2_xor_hash #(
    parameter integer DATA_WIDTH = 32,            // Разрядность входного слова
    parameter integer HASH_WIDTH = 8,             // Разрядность выходного хэша (8, 12 и т.д.)
    parameter integer SEED       = 32'h0_EDA_DEDA // Уникальное зерно для экземпляра
)(
    input  logic [DATA_WIDTH-1:0] data_in,
    output logic [HASH_WIDTH-1:0] hash_out
);
    typedef logic [DATA_WIDTH-1:0] data_t;

    // Функция вычисляется на этапе синтеза (Elaboration Time).
    function data_t get_bit_mask (input int bit_idx, input int seed_val);
        logic [31:0] val;
        val = seed_val ^ (bit_idx * 32'h9E3779B9); 
        val = val ^ (val << 13);
        val = val ^ (val >> 17);
        val = val ^ (val << 5);
        
        return data_t'(val);
    endfunction

    // Автоматическая генерация XOR-деревьев под требуемую разрядность HASH_WIDTH
    genvar i;
    generate
        for (i = 0; i < HASH_WIDTH; i = i + 1) begin : gen_hash_bits
            // Синтезатор считает маску как STATIC CONSTANT для каждого бита
            localparam data_t BIT_MASK = get_bit_mask(i, SEED);
            
            // Формирование комбинационной XOR-цепочки
            assign hash_out[i] = ^(data_in & BIT_MASK);
        end
    endgenerate

endmodule