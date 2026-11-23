# tdl_tx_reg_bridge

## Назначение

Соединяет аппаратные структуры `tx_regs` с трактом передатчика. Преобразует поля CSR в сигналы управления, фиксирует выбор алгоритма и квоту SLRU и возвращает в регистры статус, счётчики и источники IRQ.

## Порты

| Порт | Направление | Ширина или тип | Назначение |
| --- | --- | --- | --- |
| `clk`, `rst_n` | Вход | По 1 | Общий такт и активный низкий reset. |
| `hwif_out` | Вход | tx_regs_pkg::tx_regs__out_t | Значения CSR от SPI wrapper. |
| `hwif_in` | Выход | tx_regs_pkg::tx_regs__in_t | Полностью определённые аппаратные поля CSR. |
| `word_take` | Вход | 1 | fifo_rd_en controller, включая захват Bypass. |
| `fifo_empty`, `fifo_full` | Вход | По 1 | Состояние FIFO. |
| `controller_busy` | Вход | 1 | Занятость текущего слова controller. |
| `controller_state` | Вход | 3 | state_code controller. |
| `policy_ready` | Вход | 1 | policy_req_ready фасада, включая обслуживание и cfg_valid. |
| `cnt_total_words`, `cnt_key_frames`, `cnt_raw_frames`, `cnt_sync_frames`, `cnt_bf_filtered` | Вход | По 32 | Выходы stats. |
| `fifo_full_event`, `aging_event`, `high_hit_rate`, `spi_addr_err` | Вход | По 1 | События и условие от stats. |
| `tx_en`, `bypass_en` | Выход | По 1 | CTRL_REG.tx_en/bypass_en.value. |
| `policy_cfg` | Выход | 32 | Активная конфигурация controller и фасада. |
| `sdr_clk_div` | Выход | 16 | Делитель для захвата serializer. |
| `hit_rate_thresh` | Выход | 8 | Порог для stats. |

## Логика работы

### Активные настройки тракта

| Выход | Поля hwif_out |
| --- | --- |
| policy_cfg[1:0] | MODE_REG.algo_sel.value, после первого word_take — сохранённое значение. |
| policy_cfg[2] | MODE_REG.cu_disable.value. |
| policy_cfg[3] | MODE_REG.aging_disable.value. |
| policy_cfg[4] | BF_CTRL_REG.bf_en.value. |
| policy_cfg[7:5] | 0. |
| policy_cfg[15:8] | SLRU_CFG_REG.slru_thresh.value, после первого word_take — сохранённое значение. |
| policy_cfg[31:16] | {AGING_PERIOD_HI.val.value, AGING_PERIOD_LO.val.value}. |
| sdr_clk_div | {SDR_CLK_DIV_HI.val.value, SDR_CLK_DIV_LO.val.value}. |
| hit_rate_thresh | HIT_RATE_THRESH_REG.thresh_val.value. |

Первый `word_take` фиксирует `ALGO_SEL` и `N_prob` до общего сброса, в том числе при первом слове в Bypass. Поздние записи этих полей видны при чтении CSR, но активная пара берётся из сохранённых значений. Допустимость квоты SLRU до захвата слова проверяет фасад. Формат согласован с [tdl_tx_pkg](tdl_tx_pkg.md) и [tdl_tx_policy](tdl_tx_policy.md).

### Смена параметров TinyLFU

После первого извлечения слова настройки `BF_EN`, `CU_DISABLE`, `AGING_DISABLE` и `AGING_PERIOD` меняют в покое по следующей последовательности.

1. Остановить источник AXI-Stream и сохранить `TX_EN=1`, чтобы обработать накопленные слова.
2. Дождаться `IN_FIFO_EMPTY=1` и `FSM_STATE=IDLE` в одном чтении `STATUS_REG`.
3. Подождать `TINYLFU_IDLE_WAIT_CYCLES = 518` периодов `clk` от завершения чтения. За это время политика заканчивает обслуживание последнего подтверждённого слова.
4. Снять `TX_EN`, записать все необходимые поля, снова выставить `TX_EN` и возобновить источник.

Мост передаёт значения CSR сразу. Контроллер сохраняет `policy_cfg` на `word_take`. Значение `policy_ready` характеризует в том числе инициализацию и обслуживание политики. После фиксации алгоритма диагностическое условие RTL требует при изменении полей одновременно `TX_EN=0`, `fifo_empty=1`, `controller_busy=0` и `policy_ready=1`. Смена периода начинает новый отсчёт с первого слова с новым значением.

### Изменение делителя SDR

Сериализатор фиксирует `sdr_clk_div` при приёме дескриптора. Для согласованного обновления двух байтов ПО пишет их при `TX_EN=0`, когда новый дескриптор в сериализатор не принимается. Активный кадр продолжает работу со своим делителем после возобновления TX.

### Возврат статусов и событий

| Группа | Подключение |
| --- | --- |
| STATUS_REG.in_fifo_empty/full.next | fifo_empty/fifo_full. |
| STATUS_REG.fsm_state.next | controller_state. |
| STATUS_REG.config_pending/flush_busy/reset_busy.next | 0 в базовой версии после начальной инициализации. |
| CNT_*.val.next | Соответствующие значения cnt_* от stats. |
| INT_STATUS_REG | События подаются на `hwset` соответствующих IRQ. |
| I2C_STATUS_REG | Все поля 0. |
| I²C IRQ hardware inputs | 0. |

Все поля hwif_in задаются комбинационно. [tx_regs](tx_regs.md) удерживает статусы и даёт приоритет аппаратному событию при одновременном W1C.

## Связанные документы

- [Исходный код](../../../rtl/transmitter/tdl_tx_reg_bridge.sv).
- [Архитектура передатчика](tdl_tx_top.md).
- [tx_regs](tx_regs.md) описывает `hwif_in`, `hwif_out` и W1C.
- [tdl_tx_pkg](tdl_tx_pkg.md) определяет раскладку `policy_cfg` и длительность выдержки.
- [tdl_tx_policy](tdl_tx_policy.md) проверяет допустимость конфигурации перед запросом.
- [Спецификация TDL](../../spec.md), §6.1.1.
