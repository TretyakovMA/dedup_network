`ifndef TDL_BLOOM_FILTER
`define TDL_BLOOM_FILTER
// Фильтр Блума TinyLFU с активным и предыдущим поколениями и записью по commit.
module tdl_bloom_filter (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        req_valid,
    output logic        req_ready,
    input  logic [11:0] req_h0,
    input  logic [11:0] req_h1,

    output logic        rsp_valid,
    input  logic        rsp_ready,
    output logic        rsp_seen,
    input  logic        commit,

    input  logic        rotate_req,
    output logic        rotate_done,
    output logic        busy
);
    // Каждый хэш делится на адрес 32-битного слова RAM и номер бита внутри него.
    localparam int HASH_WIDTH = 12;
    localparam int WORD_WIDTH = 32;
    localparam int BIT_INDEX_WIDTH = $clog2(WORD_WIDTH);
    localparam int WORD_ADDR_WIDTH = HASH_WIDTH - BIT_INDEX_WIDTH;
    localparam int WORD_COUNT = 1 << WORD_ADDR_WIDTH;

    typedef enum logic [2:0] {
        ST_INIT,
        ST_IDLE,
        ST_READ_H1,
        ST_CHECK,
        ST_RESPONSE,
        ST_WAIT_COMMIT,
        ST_WRITE_H1,
        ST_ROTATE
    } state_t;

    state_t state;
    logic active_bank;
    logic [WORD_ADDR_WIDTH-1:0] clear_addr, word_h0, word_h1;
    logic [BIT_INDEX_WIDTH-1:0] bit_h0, bit_h1;
    logic same_word;
    logic seen_h0, seen_q;
    logic [WORD_WIDTH-1:0] updated_h0_word;

    logic ram_read;
    logic [1:0] ram_write;
    logic [WORD_ADDR_WIDTH-1:0] ram_addr;
    logic [WORD_ADDR_WIDTH-1:0] req_word_h0;
    logic [WORD_WIDTH-1:0] ram_write_data;
    logic [WORD_WIDTH-1:0] bank_read_data [0:1];
    logic [WORD_WIDTH-1:0] active_read_data, union_read_data;
    logic [WORD_WIDTH-1:0] mask_h0, mask_h1;

    assign req_ready = rst_n && (state == ST_IDLE) && !rotate_req;
    assign rsp_valid = rst_n && (state == ST_RESPONSE);
    assign rsp_seen  = rsp_valid && seen_q;
    assign busy      = (state != ST_IDLE);

    assign same_word        = (word_h0 == word_h1);
    assign mask_h0          = WORD_WIDTH'(1'b1) << bit_h0;
    assign mask_h1          = WORD_WIDTH'(1'b1) << bit_h1;
    assign req_word_h0      = req_h0[HASH_WIDTH-1:BIT_INDEX_WIDTH];
    assign active_read_data = bank_read_data[active_bank];
    // Присутствие обоих хэшей проверяется по объединению active и old.
    assign union_read_data  = bank_read_data[0] | bank_read_data[1];

    // На чтении оба поколения используют один адрес слова. Записи идут в active.
    always_comb begin
        ram_read       = 1'b0;
        ram_write      = '0;
        ram_addr       = '0;
        ram_write_data = '0;

        if (rst_n) begin
            case (state)
                ST_INIT: begin
                    ram_write = 2'b11;
                    ram_addr  = clear_addr;
                end
                ST_IDLE: begin
                    if (req_valid && req_ready) begin
                        ram_read = 1'b1;
                        ram_addr = req_word_h0;
                    end
                end
                ST_READ_H1: begin
                    ram_read = 1'b1;
                    ram_addr = word_h1;
                end
                // Принятый ответ сохраняет адреса до записи в active. Для двух слов RAM нужны два фронта.
                ST_WAIT_COMMIT: begin
                    if (commit) begin
                        ram_write[active_bank] = 1'b1;
                        ram_addr            = word_h0;
                        ram_write_data      = updated_h0_word;
                    end
                end
                ST_WRITE_H1: begin
                    ram_write[active_bank] = 1'b1;
                    ram_addr            = word_h1;
                    ram_write_data      = active_read_data | mask_h1;
                end
                ST_ROTATE: begin
                    ram_write[!active_bank] = 1'b1;
                    ram_addr             = clear_addr;
                end
                default: ;
            endcase
        end
    end

    // Массивы очищаются через порт записи, чтобы сохранить синхронный шаблон RAM.
    for (genvar bank = 0; bank < 2; bank++) begin : gen_bank
        logic [WORD_WIDTH-1:0] memory [0:WORD_COUNT-1];

        always_ff @(posedge clk) begin
            if (ram_write[bank])
                memory[ram_addr] <= ram_write_data;
            else if (ram_read)
                bank_read_data[bank] <= memory[ram_addr];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_INIT;
            active_bank     <= 1'b0;
            clear_addr      <= '0;
            word_h0         <= '0;
            word_h1         <= '0;
            bit_h0          <= '0;
            bit_h1          <= '0;
            seen_h0         <= 1'b0;
            seen_q          <= 1'b0;
            updated_h0_word <= '0;
            rotate_done     <= 1'b0;
        end else begin
            rotate_done <= 1'b0;
            case (state)
                ST_INIT, ST_ROTATE: begin
                    if (clear_addr == WORD_ADDR_WIDTH'(WORD_COUNT - 1)) begin
                        if (state == ST_ROTATE) begin
                            // Только полностью очищенный старый банк становится новым active.
                            active_bank <= !active_bank;
                            rotate_done <= 1'b1;
                        end
                        state <= ST_IDLE;
                    end else begin
                        clear_addr <= clear_addr + 1'b1;
                    end
                end
                ST_IDLE: begin
                    if (rotate_req) begin
                        clear_addr <= '0;
                        state      <= ST_ROTATE;
                    end else if (req_valid) begin
                        {word_h0, bit_h0} <= req_h0;
                        {word_h1, bit_h1} <= req_h1;
                        state             <= ST_READ_H1;
                    end
                end
                ST_READ_H1: begin
                    seen_h0 <= union_read_data[bit_h0];
                    // Хэши в одном слове RAM объединяются в одну запись.
                    updated_h0_word <= active_read_data | mask_h0 | (same_word ? mask_h1 : '0);
                    state           <= ST_CHECK;
                end
                ST_CHECK: begin
                    seen_q <= seen_h0 && union_read_data[bit_h1];
                    state  <= ST_RESPONSE;
                end
                ST_RESPONSE: begin
                    if (rsp_ready)
                        state <= ST_WAIT_COMMIT;
                end
                ST_WAIT_COMMIT: begin
                    if (commit)
                        state <= same_word ? ST_IDLE : ST_WRITE_H1;
                end
                ST_WRITE_H1: state <= ST_IDLE;
                default:     state <= ST_INIT;
            endcase
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n) begin
            assert (!commit || state == ST_WAIT_COMMIT)
                else $error("tdl_bloom_filter commit without a pending response");
            assert (!rotate_req || state == ST_IDLE)
                else $error("tdl_bloom_filter rotate_req while busy");
        end
    end
`endif

endmodule
`endif
