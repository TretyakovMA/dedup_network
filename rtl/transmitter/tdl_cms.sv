`ifndef TDL_CMS
`define TDL_CMS
// Count-Min Sketch TinyLFU с двухфазным обновлением счётчиков и периодическим затуханием.
module tdl_cms (
    input  logic       clk,
    input  logic       rst_n,

    input  logic       req_valid,
    output logic       req_ready,
    input  logic [7:0] req_h0,
    input  logic [7:0] req_h1,
    input  logic       req_cu_disable,

    output logic       rsp_valid,
    input  logic       rsp_ready,
    output logic [3:0] rsp_est,
    input  logic       commit,

    input  logic       aging_req,
    output logic       aging_done,
    output logic       busy
);
    typedef enum logic [2:0] {
        ST_INIT,
        ST_IDLE,
        ST_EVAL,
        ST_RESPONSE,
        ST_WAIT_COMMIT,
        ST_AGE_READ,
        ST_AGE_WRITE
    } state_t;

    state_t state;
    logic [7:0] h0_q, h1_q;
    logic cu_disable_q;
    logic [3:0] pending_c0, pending_c1;
    logic [3:0] old_min;
    logic [7:0] sweep_addr;

    logic ram_read, ram_write;
    logic [7:0] ram_addr [0:1];
    logic [3:0] ram_write_data [0:1];
    logic [3:0] ram_read_data [0:1];

    function automatic logic [3:0] sat_inc(input logic [3:0] count);
        return (&count) ? count : count + 1'b1;
    endfunction

    assign req_ready = rst_n && (state == ST_IDLE) && !aging_req;
    assign rsp_valid = rst_n && (state == ST_RESPONSE);
    assign rsp_est   = rsp_valid ? ((pending_c0 < pending_c1) ? pending_c0 : pending_c1) : '0;
    assign busy      = rst_n && (state != ST_IDLE);

    // Conservative Update выбирает ячейки по минимуму до записи новых значений.
    assign old_min = (ram_read_data[0] < ram_read_data[1]) ? ram_read_data[0] : ram_read_data[1];

    always_comb begin
        ram_read          = 1'b0;
        ram_write         = 1'b0;
        ram_addr[0]       = sweep_addr;
        ram_addr[1]       = sweep_addr;
        ram_write_data[0] = '0;
        ram_write_data[1] = '0;

        if (rst_n) begin
            case (state)
                ST_INIT: ram_write = 1'b1;
                ST_IDLE: begin
                    if (req_valid && req_ready) begin
                        ram_read    = 1'b1;
                        ram_addr[0] = req_h0;
                        ram_addr[1] = req_h1;
                    end
                end
                ST_WAIT_COMMIT: begin
                    if (commit) begin
                        ram_write         = 1'b1;
                        ram_addr[0]       = h0_q;
                        ram_addr[1]       = h1_q;
                        ram_write_data[0] = pending_c0;
                        ram_write_data[1] = pending_c1;
                    end
                end
                // Затухание читает и перезаписывает один столбец обоих банков за два такта.
                ST_AGE_READ: ram_read = 1'b1;
                ST_AGE_WRITE: begin
                    ram_write         = 1'b1;
                    ram_write_data[0] = ram_read_data[0] >> 1;
                    ram_write_data[1] = ram_read_data[1] >> 1;
                end
                default: ;
            endcase
        end
    end

    // Два синхронных банка позволяют записать оба счётчика на одном commit.
    for (genvar bank = 0; bank < 2; bank++) begin : gen_bank
        logic [3:0] memory [0:255];

        always_ff @(posedge clk) begin
            if (ram_write)
                memory[ram_addr[bank]] <= ram_write_data[bank];
            else if (ram_read)
                ram_read_data[bank] <= memory[ram_addr[bank]];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= ST_INIT;
            h0_q         <= '0;
            h1_q         <= '0;
            cu_disable_q <= 1'b0;
            pending_c0   <= '0;
            pending_c1   <= '0;
            sweep_addr   <= '0;
            aging_done   <= 1'b0;
        end else begin
            aging_done <= 1'b0;
            case (state)
                ST_INIT: begin
                    if (sweep_addr == 8'hff)
                        state <= ST_IDLE;
                    else
                        sweep_addr <= sweep_addr + 1'b1;
                end
                ST_IDLE: begin
                    if (aging_req) begin
                        sweep_addr <= '0;
                        state      <= ST_AGE_READ;
                    end else if (req_valid) begin
                        h0_q         <= req_h0;
                        h1_q         <= req_h1;
                        cu_disable_q <= req_cu_disable;
                        state        <= ST_EVAL;
                    end
                end
                // Оценка вычисляется по подготовленным значениям. Память обновится на commit.
                ST_EVAL: begin
                    // Оба решения CU используют минимум до обновления.
                    pending_c0 <= (cu_disable_q || ram_read_data[0] == old_min)
                                ? sat_inc(ram_read_data[0]) : ram_read_data[0];
                    pending_c1 <= (cu_disable_q || ram_read_data[1] == old_min)
                                ? sat_inc(ram_read_data[1]) : ram_read_data[1];
                    state <= ST_RESPONSE;
                end
                ST_RESPONSE: begin
                    if (rsp_ready)
                        state <= ST_WAIT_COMMIT;
                end
                ST_WAIT_COMMIT: begin
                    if (commit) begin
                        if (aging_req) begin
                            // Чтение для aging начнётся после подтверждённой записи.
                            sweep_addr <= '0;
                            state      <= ST_AGE_READ;
                        end else begin
                            state <= ST_IDLE;
                        end
                    end
                end
                ST_AGE_READ: state <= ST_AGE_WRITE;
                ST_AGE_WRITE: begin
                    if (sweep_addr == 8'hff) begin
                        aging_done <= 1'b1;
                        state      <= ST_IDLE;
                    end else begin
                        sweep_addr <= sweep_addr + 1'b1;
                        state      <= ST_AGE_READ;
                    end
                end
                default: begin
                    sweep_addr <= '0;
                    state      <= ST_INIT;
                end
            endcase
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (rst_n) begin
            assert (!commit || state == ST_WAIT_COMMIT)
                else $error("tdl_cms commit without a pending response");
            assert (!aging_req || state == ST_IDLE || ((state == ST_WAIT_COMMIT) && commit))
                else $error("tdl_cms aging_req outside idle or commit");
        end
    end
`endif

endmodule
`endif
