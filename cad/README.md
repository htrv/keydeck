# CAD / 3D-печать keydeck

Корпус Stream Cheap Deck (ESP32-S3) и колпачки с надписями DEV / PROD.

## `case/` — корпус

Готовые STL корпуса здесь не лежат: это чужие модели.

- Основной корпус: [Stream Cheap на Thingiverse](https://www.thingiverse.com/thing:2822140).
- Вариант под ESP32-S3: [MakerWorld 1899311](https://makerworld.com/en/models/1899311-esp32-stream-cheap-deck-ble-usb-macro-keyboard).

В этих моделях нет окон под USB-C и кнопку выключения. На собранном корпусе отверстия сверлили уже после печати. Перед следующей печатью дно лучше поправить заранее.

Удлинитель тактовой кнопки до стенки: `Mini_Push_Switch_Extension_6.stl`, габарит **6 × 6 × 12 мм**, без своей пружины. На принтере эта длина одна, 13 октября 2026, PETG, около 5 минут. Исходник — [Extension shafts](https://www.printables.com/model/612608-extension-shafts-for-pushbutton-switches), размер `_6`.

## Case

The case STLs are not in this repo.

- Main case: [Stream Cheap on Thingiverse](https://www.thingiverse.com/thing:2822140).
- ESP32-S3 variant: [MakerWorld 1899311](https://makerworld.com/en/models/1899311-esp32-stream-cheap-deck-ble-usb-macro-keyboard).

Those models have no holes for USB-C or the power button. On the built case the holes were drilled after printing. Add the openings to the base before the next print.

Power-button shaft: `Mini_Push_Switch_Extension_6.stl`, **6 × 6 × 12 mm**, no spring of its own. Only this length was printed, 13 October 2026, PETG, about 5 minutes. Source: [Extension shafts](https://www.printables.com/model/612608-extension-shafts-for-pushbutton-switches), size `_6`.

## `keycaps/` — колпачки DEV / PROD

| Файл | Что |
|---|---|
| `key-empty.stl` | пустой колпачок |
| `key-dev.stl` / `key-dev.3mf` | колпачок DEV |
| `key-prod.stl` / `key-prod.3mf` | колпачок PROD |
| `PR OD.stl` / `PR OD 04.stl` | буквы PR OD |
| `key-claude-body.stl` / `key-claude-insert.stl` / `key-claude.3mf` | Claude, двухцветный |
| `key-report-body.stl` / `key-report-insert.stl` / `report-bars.svg` | отчёт, двухцветный |

`key-dev.blend` остаётся только в локальном репозитории и на GitHub не попадает. Скачанный `Keycap-base.stl` тоже не выкладывается.

## `print/` — выбор материала

Готовый gcode для Ender-3 V3 KE, слой 0.2, первый слой вставки 0.4 мм. Печать лицом вниз: сначала знак, `M600`, потом корпус. Бери одну папку целиком.

| Папка | Материалы | Что внутри |
|---|---|---|
| `all-petg/` | всё PETG | DEV, PROD, PR OD 04, отчёт (у отчёта два цвета PETG) |
| `1-pla-2-petg/` | 1 — PLA, 2 — PETG | Claude и отчёт: вставка PLA, корпус PETG |
| `all-pla/` | всё PLA | такого набора нет, файлы не нарезаны |
| PETG, затем PLA | сначала PETG, потом PLA | такого набора тоже нет |

В `1-pla-2-petg/` два файла Claude: `key-claude_PLA-PETG_insert-first.gcode` (первый слой 210 °C) и `key-claude_PLA-PETG_230c_insert-first.gcode` (старт 230 °C). Имя со словом PETG у второго было неверным: по заголовку gcode там тоже PLA, затем PETG.

## `print/` — choose a material

Ready gcode for an Ender-3 V3 KE, 0.2 mm layers, 0.4 mm first layer for the insert. Print face down: legend first, `M600`, then the body. Take one folder.

| Folder | Materials | Contents |
|---|---|---|
| `all-petg/` | all PETG | DEV, PROD, PR OD 04, report (the report uses two PETG colors) |
| `1-pla-2-petg/` | 1 PLA, 2 PETG | Claude and report: PLA insert, PETG body |
| `all-pla/` | all PLA | not sliced |
| PETG then PLA | PETG first, then PLA | not sliced |

`1-pla-2-petg/` has two Claude files: `key-claude_PLA-PETG_insert-first.gcode` (210 °C first layer) and `key-claude_PLA-PETG_230c_insert-first.gcode` (230 °C start). The second file used to be named as PETG only; its header is PLA, then PETG.
