`ifndef TDL_TX_REG_BRIDGE
`define TDL_TX_REG_BRIDGE
// Преобразует поля CSR в настройки тракта и возвращает статусы, счётчики и события IRQ.
module tdl_tx_reg_bridge (
    input  logic                      clk,
    input  logic                      rst_n,
    input  var tx_regs_pkg::tx_regs__out_t hwif_out,
    output var tx_regs_pkg::tx_regs__in_t  hwif_in,

    input  logic                      word_take,
    input  logic                      fifo_empty,
    input  logic                      fifo_full,
    input  logic                      controller_busy,
    input  logic [2:0]                controller_state,
    input  logic                      policy_ready,

    input  logic [31:0]               cnt_total_words,
    input  logic [31:0]               cnt_key_frames,
    input  logic [31:0]               cnt_raw_frames,
    input  logic [31:0]               cnt_sync_frames,
    input  logic [31:0]               cnt_bf_filtered,
    input  logic                      fifo_full_event,
    input  logic                      aging_event,
    input  logic                      high_hit_rate,
    input  logic                      spi_addr_err,

    output logic                      tx_en,
    output logic                      bypass_en,
    output logic [31:0]               policy_cfg,
    output logic [15:0]               sdr_clk_div,
    output logic [7:0]                hit_rate_thresh
);
    import tdl_tx_pkg::*;

    policy_cfg_t cfg;
    logic config_locked;
    logic [1:0] locked_algo_sel;
    logic [7:0] locked_n_prob;

    assign tx_en           = hwif_out.CTRL_REG.tx_en.value;
    assign bypass_en       = hwif_out.CTRL_REG.bypass_en.value;
    assign sdr_clk_div     = {hwif_out.SDR_CLK_DIV_HI.val.value, hwif_out.SDR_CLK_DIV_LO.val.value};
    assign hit_rate_thresh = hwif_out.HIT_RATE_THRESH_REG.thresh_val.value;
    assign policy_cfg      = cfg;

    // Активная пара ALGO_SEL/N_prob берётся из снимка после первого pop.
    // Настройки обслуживания остаются доступны для обновления по протоколу покоя.
    always_comb begin
        cfg.aging_period  = {hwif_out.AGING_PERIOD_HI.val.value, hwif_out.AGING_PERIOD_LO.val.value};
        cfg.n_prob        = config_locked ? locked_n_prob : hwif_out.SLRU_CFG_REG.slru_thresh.value;
        cfg.reserved      = '0;
        cfg.bf_en         = hwif_out.BF_CTRL_REG.bf_en.value;
        cfg.aging_disable = hwif_out.MODE_REG.aging_disable.value;
        cfg.cu_disable    = hwif_out.MODE_REG.cu_disable.value;
        cfg.algo_sel      = policy_algo_t'(config_locked ? locked_algo_sel : hwif_out.MODE_REG.algo_sel.value);
    end

    // Первый pop фиксирует алгоритм и квоту в том числе при Bypass.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            config_locked   <= 1'b0;
            locked_algo_sel <= '0;
            locked_n_prob   <= '0;
        end else if (word_take && !config_locked) begin
            config_locked   <= 1'b1;
            locked_algo_sel <= hwif_out.MODE_REG.algo_sel.value;
            locked_n_prob   <= hwif_out.SLRU_CFG_REG.slru_thresh.value;
        end
    end

    always_comb begin
        hwif_in.STATUS_REG.in_fifo_empty.next   = fifo_empty;
        hwif_in.STATUS_REG.in_fifo_full.next    = fifo_full;
        hwif_in.STATUS_REG.fsm_state.next       = controller_state;
        hwif_in.STATUS_REG.config_pending.next = 1'b0;
        hwif_in.STATUS_REG.flush_busy.next     = 1'b0;
        hwif_in.STATUS_REG.reset_busy.next     = 1'b0;

        hwif_in.CNT_TOTAL_WORDS.val.next = cnt_total_words;
        hwif_in.CNT_KEY_FRAMES.val.next  = cnt_key_frames;
        hwif_in.CNT_RAW_FRAMES.val.next  = cnt_raw_frames;
        hwif_in.CNT_SYNC_FRAMES.val.next = cnt_sync_frames;
        hwif_in.CNT_BF_FILTERED.val.next = cnt_bf_filtered;

        // Аппаратные источники устанавливают sticky-статусы через hwset.
        hwif_in.INT_STATUS_REG.fifo_overflow.hwset = fifo_full_event;
        hwif_in.INT_STATUS_REG.aging_event.hwset   = aging_event;
        hwif_in.INT_STATUS_REG.high_hit_rate.hwset = high_hit_rate;
        hwif_in.INT_STATUS_REG.spi_addr_err.hwset  = spi_addr_err;

        // Базовый тракт принимает AXI-Stream, поэтому аппаратные входы I²C зафиксированы в нуле.
        hwif_in.INT_STATUS_REG.i2c_nack.hwset      = 1'b0;
        hwif_in.INT_STATUS_REG.i2c_timeout.hwset   = 1'b0;
        hwif_in.INT_STATUS_REG.i2c_bus_err.hwset   = 1'b0;
        hwif_in.I2C_STATUS_REG.busy.next         = 1'b0;
        hwif_in.I2C_STATUS_REG.poll_paused.next  = 1'b0;
        hwif_in.I2C_STATUS_REG.bus_recovery.next = 1'b0;
        hwif_in.I2C_STATUS_REG.reserved.next     = '0;
    end

`ifndef SYNTHESIS
    fixed_config_unchanged: assert property (@(posedge clk) disable iff (!rst_n)
        config_locked && $changed({hwif_out.MODE_REG.algo_sel.value, hwif_out.SLRU_CFG_REG.slru_thresh.value})
        |-> {hwif_out.MODE_REG.algo_sel.value, hwif_out.SLRU_CFG_REG.slru_thresh.value}
            == {locked_algo_sel, locked_n_prob})
        else $warning("tdl_tx_reg_bridge ignored a change to ALGO_SEL/N_prob after the first word_take");

    runtime_config_changed_in_idle: assert property (@(posedge clk) disable iff (!rst_n)
        config_locked && $changed({cfg.aging_period, cfg.bf_en, cfg.aging_disable, cfg.cu_disable})
        |-> !tx_en && fifo_empty && !controller_busy && policy_ready)
        else $error("tdl_tx_reg_bridge policy settings changed outside the idle TX configuration window");
`endif

endmodule
`endif
