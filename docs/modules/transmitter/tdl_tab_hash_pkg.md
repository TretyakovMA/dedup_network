# tdl_tab_hash_pkg

## Назначение

Фиксирует воспроизводимый набор констант для четырёх функций табличного хэширования. Вычисление таблиц выполняется при elaboration. В тракте `tdl_tab_hash` выполняются табличные выборки и XOR.

## Интерфейс пакета

### Константы и типы

| Объявление | Значение и назначение |
| --- | --- |
| TABLE_SEED | `32'h5444_4C06`, фиксирует набор таблиц. |
| TABLE_VERSION | 2, версия набора и правил генерации. |
| hash_table12_t | logic [3071:0], 256 элементов по 12 бит. |
| hash_table8_t | logic [2047:0], 256 элементов по 8 бит. |
| BF1_B0 … BF1_B3 | hash_index=0, byte_index=0…3. |
| BF2_B0 … BF2_B3 | hash_index=1, byte_index=0…3. |
| CMS1_B0 … CMS1_B3 | hash_index=2, byte_index=0…3. |
| CMS2_B0 … CMS2_B3 | hash_index=3, byte_index=0…3. |

### Функции

| Функция | Аргументы | Возвращаемое значение |
| --- | --- | --- |
| mix32 | logic [31:0] value | 32-битный результат последовательности смешивания. |
| make_table12 | integer hash_index, byte_index | Полная таблица hash_table12_t. |
| make_table8 | integer hash_index, byte_index | Полная таблица hash_table8_t. |
| lookup12 | hash_table12_t table_data, logic [7:0] index | logic [11:0], элемент таблицы по index. |
| lookup8 | hash_table8_t table_data, logic [7:0] index | logic [7:0], элемент таблицы по index. |

## Логика работы

### Адресация

Каждый набор содержит четыре таблицы. `B0` адресуется `data_in[7:0]`, `B3` — `data_in[31:24]`. Элемент `entry` лежит в срезе `[entry*W +: W]`, где `W=12` для BF и `W=8` для CMS. Всего пакет определяет 16 таблиц, 40960 бит констант.

### Генерация констант

Для каждой комбинации hash_index, byte_index и entry=0…255 вычисляется

```text
value = TABLE_SEED
      XOR ((hash_index + 1) * 0x9E3779B9)
      XOR ((byte_index + 1) * 0x85EBCA6B)
      XOR ((entry + 1) * 0xC2B2AE35)

value = value XOR (value >> 16)
value = value * 0x85EBCA6B
value = value XOR (value >> 13)
value = value * 0xC2B2AE35
value = value XOR (value >> 16)
```

Арифметика ограничена 32 битами, произведения берутся по модулю 2^32. Сдвиги логические. Для BF сохраняются младшие 12 бит, для CMS — младшие 8 бит результата.

Изменение seed, функции смешивания, порядка адресов или ширины усечения меняет результат хэширования. В работающем передатчике набор таблиц фиксирован.

### Примеры результатов для версии 2

| Входное слово | h_bf1 | h_bf2 | h_cms1 | h_cms2 |
| --- | --- | --- | --- | --- |
| 0x12345678 | 0x164 | 0x693 | 0x8B | 0x71 |
| 0x00000000 | 0xDE8 | 0x36E | 0xA0 | 0xAF |

## Связанные документы

- [Исходный код](../../../rtl/transmitter/tdl_tab_hash_pkg.sv).
- [Архитектура передатчика](tdl_tx_top.md).
- [tdl_tab_hash](tdl_tab_hash.md) читает таблицы при вычислении хэшей.
- [Спецификация TDL](../../spec.md), §8.1.
