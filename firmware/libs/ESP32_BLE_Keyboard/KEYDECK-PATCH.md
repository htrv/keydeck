# Почему эта библиотека лежит в репозитории и что в ней исправлено

Вендорнутая копия `ESP32 BLE Keyboard` (T-vK), потому что:

1. Её **нет в Arduino Library Manager** — ни одна библиотека из индекса не
   предоставляет `BleKeyboard.h`. Ставится только ZIP-ом с GitHub.
2. Версия 0.3.2 **не собирается на esp32 core 3.x** и содержит несколько багов,
   которые ломают работу на ESP32-S3 (там ядро использует NimBLE, а не Bluedroid).
3. Пропатченную копию нельзя держать в `.arduino/user/` — этот путь в
   `.gitignore`, и сборка перестаёт воспроизводиться на другой машине.

- Upstream: <https://github.com/T-vK/ESP32-BLE-Keyboard>
- Коммит: `b7aaf9bb711a04216e4417f1e2a6b0ee0eaeaf66` (2024-03-24)
- `library.properties`: `version=0.3.2`

## Внесённые правки

Все — в `BleKeyboard.cpp`, все помечены в коде комментарием `keydeck patch N/6`.

Проверено на живой плате (ESP32-S3, macOS): устройство спаривается, создаёт
HID-клавиатуру и все 8 кнопок доходят до мака как F13..F20. Патчи 4–6 нашлись
именно при этой отладке (см. ниже), VID/PID отдельно вынесен в скетч.

### 1. `BLEDevice::init` и `setValue(std::string)` (сборка)

| Было (core 2.x) | Стало (core 3.x) |
|---|---|
| `BLEDevice::init(deviceName)` | `BLEDevice::init(deviceName.c_str())` |
| `manufacturer()->setValue(deviceManufacturer)` | `setValue((const uint8_t*)deviceManufacturer.c_str(), deviceManufacturer.length())` |

В core 3.x `BLEDevice::init` принимает `String`, а не `std::string`, и у
`BLECharacteristic` больше нет перегрузки `setValue(std::string)`.

### 2. Security: MITM → Just Works

| Было | Стало |
|---|---|
| `setAuthenticationMode(ESP_LE_AUTH_REQ_SC_MITM_BOND)` | `setCapability(ESP_IO_CAP_NONE)` + `setAuthenticationMode(ESP_LE_AUTH_REQ_SC_BOND)` |

MITM требует ввода или показа кода, а у макро-клавиатуры нет ни дисплея, ни
клавиатуры. macOS не может завершить такое спаривание и бесконечно висит на
«Подключение». После правки в логе macOS: `authReq=00000009`, `Received "Just
Works" pairing request`, `Encryption is now enabled`, `Pairing completed`.

### 3. Падение на подключении (главный баг)

`onConnect()`/`onDisconnect()` в ветке `!USE_NIMBLE` лезли в дескриптор CCCD:

```cpp
BLE2902* desc = (BLE2902*)inputKeyboard->getDescriptorByUUID(BLEUUID((uint16_t)0x2902));
desc->setNotifications(true);   // desc == nullptr
```

На NimBLE ядро **намеренно не создаёт** `BLE2902` — CCCD добавляется стеком
автоматически (см. `BLEHIDDevice.cpp`, там та же логика под `#if
CONFIG_BLUEDROID_ENABLED`). `getDescriptorByUUID(0x2902)` возвращает `nullptr`, и
виртуальный вызов на нём роняет плату **в момент подключения хоста**:
`Guru Meditation Error: LoadProhibited, EXCVADDR 0x2c` → цикл перезагрузки.

Условие заменено на то же, что использует ядро, — `#if CONFIG_BLUEDROID_ENABLED`.
Заодно `advertising->start()` в `onDisconnect()` вынесен из-под `#if`: рекламу надо
возобновлять всегда, иначе после отключения хост не подключится снова.

### 4. Права дескриптора Report Reference (главный баг HOGP)

Ядро выставляет дескриптору `0x2908` права в кодировке **Bluedroid**
(`BLEHIDDevice.cpp:144`):

```cpp
inputReportDescriptor->setAccessPermissions(
    ESP_GATT_PERM_READ_ENCRYPTED | ESP_GATT_PERM_WRITE_ENCRYPTED);
```

Но на ESP32-S3 активен **NimBLE**, а у него те же числа означают другое:

| Флаг | Bluedroid (`ESP_GATT_PERM_*`) | NimBLE (`BLE_ATT_F_*`) |
|---|---|---|
| READ | `0x01` | `0x01` |
| READ_ENCRYPTED | `0x02` | `0x04` |
| READ_AUTHEN | `0x04` | `0x08` |
| WRITE | `0x10` | `0x02` |
| WRITE_ENCRYPTED | `0x20` | `0x20` |

Получается `0x22` = `WRITE | WRITE_ENC`, то есть **без права чтения**. macOS при
настройке HOGP читает этот дескриптор и получает
`BLE_ATT_ERR_READ_NOT_PERMITTED = 0x02`:

```
Reading value for descriptor handle 0x001f
E Stack.GATT LE_GATT_Handle_ReadLongCharacteristicValueResponse
  Received error response for characteristic read: 2 (status=65535)
```

Без Report Reference macOS **не создаёт HID-устройство**: в `hidutil list` нет
устройства с `vid 0xac05`, нажатия никуда не идут.

**Где живёт значение.** Права едут в NimBLE как `ble_gatt_dsc_def.att_flags`
(`BLEService.cpp:599` — `pDsc_a[d].att_flags = pDescriptor->m_permissions`), то
есть байт в байт без всякой трансляции. Поэтому правка и делается у нас, а не в
ядре: `fixReportReferenceDescriptor()` в `begin()` берёт дескриптор через
`getDescriptorByUUID(0x2908)` сразу после `hid->inputReport(...)` — дескриптор к
этому моменту уже создан в `BLEHIDDevice::inputReport()` — и ставит `0x01` (READ,
одинаковый в обеих раскладках).

Две вещи, которые тут легко принять за баг, но багом не являются:

- `BLEDescriptor::setAccessPermissions()` **работает** — она пишет `m_permissions`
  (это `BLEDescriptor.cpp:209`, без `#ifdef`). Пустышка — это одноимённый метод
  `BLECharacteristic`, у него тело целиком под `CONFIG_BLUEDROID_ENABLED`, поэтому
  права самих характеристик на NimBLE действительно не применяются.
- `BLEDescriptor::executeCreate()` на NimBLE пустая (регистрация дескрипторов идёт
  не через неё, а через таблицу `ble_gatt_svc_def`, которую собирает `BLEService`),
  но нам это и не нужно: `m_permissions` читается из объекта позже, при сборке
  таблицы.

После этой правки macOS дескриптор читает — и ловится **следующий** баг (патч 5).

### 5. Краш при чтении дескриптора (LoadProhibited) — следствие патча 4

Как только патч 4 сделал дескриптор читаемым, macOS при подключении его читает —
и плата падает: `Guru Meditation Error: Core panic'ed (LoadProhibited)`,
`EXCVADDR 0x00000000`, бесконечный цикл перезагрузки. Внешне это «устройство
подключилось и сразу отключилось».

Причина — в NimBLE-ветке ядра. При чтении дескриптора
`BLEDescriptor::handleGATTServerEvent` (`BLEDescriptor.cpp:361`) делает:

```cpp
pDescriptor->m_pCallback->onRead(pDescriptor);   // m_pCallback == nullptr
```

без проверки на null. У дескриптора Report Reference колбэк никто не ставит
(`m_pCallback` инициализируется в `nullptr`, `BLEDescriptor.cpp:61`), поэтому
вызов роняет плату. Bluedroid-ветка (`BLEDescriptor.cpp:316`) ту же проверку
делает — поэтому на обычном ESP32 (Bluedroid) бага нет, он только на S3 (NimBLE),
и референсные скетчи под обычный ESP32 на S3 упали бы так же.

Правка (там же, в `fixReportReferenceDescriptor()`): `reportReference->setCallbacks(nullptr)`.
`setCallbacks(nullptr)` подставляет безопасный `&defaultCallbacks` вместо null
(`BLEDescriptor.cpp:150-156`), и чтение дескриптора больше не роняет плату.

### 6. Потолок кодов клавиш в Report Map (`0x65` → `0x73`)

После патчей 4–5 macOS создаёт HID-клавиатуру, но доходит **только первая**
кнопка, остальные игнорируются (а первая на практике ведёт себя как «стрелка
вверх»). Дескриптор отчёта (скопирован из библиотеки, `_hidReportDescriptor`)
объявляет диапазон кодов клавиш:

```
LOGICAL_MAXIMUM  0x65   ; 101
USAGE_MAXIMUM    0x65
```

`0x65` = 101 — это потолок, выше которого хост считает код недействительным.
Но библиотека шлёт F13..F20 как HID usage `0x68..0x6F` (104..111) — всё это
**выше 101**, вне диапазона. Хост такой код отбрасывает (или трактует
произвольно — отсюда «вверх» на первой кнопке).

Правка: поднять оба потолка до `0x73` (115 = F24), тогда F13..F24 попадают в
диапазон. Проверено: после фикса все 8 кнопок доходят до macOS как F13..F20.

ВАЖНО: macOS **кэширует Report Map по спаренному устройству**. После изменения
дескриптора старый мак держит прежнюю карту (видно в `ioreg -c IOHIDDevice` как
`"Max"=101`). Чтобы он перечитал — нужно, чтобы устройство выглядело новым: мы
сменили VID/PID (см. ниже) и делаем чистое спаривание (стереть NVS платы +
«Забыть устройство» на маке; если не помогает — `sudo pkill bluetoothd`, он
сбрасывает кэш дескрипторов).

## VID/PID: не выдавать себя за Apple

Дефолт библиотеки — `vid = 0x05AC` (**это Apple**) и `pid = 0x820A`. С ним macOS
показывает устройство как «яблочное» (`hidutil` → `0xac05`) и применяет особые
правила. В скетче мы ставим свой идентификатор через публичные сеттеры до
`begin()`:

```cpp
bleKeyboard.set_vendor_id(0x303A);   // официальный Espressif VID
bleKeyboard.set_product_id(0x8391);
```

Это и убирает маскировку под Apple, и — как побочный полезный эффект — заставляет
macOS считать устройство новым и перечитать Report Map (см. патч 6). В `hidutil`/
`system_profiler` значения видны с переставленными байтами (`0x3A30` / `0x9183`) —
это порядок представления, не ошибка.

## USE_NIMBLE включать НЕ нужно

В `BleKeyboard.h` первой строкой идёт закомментированный `#define USE_NIMBLE`.
**Оставляй его закомментированным.** Этот флаг переключает библиотеку на внешнюю
`NimBLE-Arduino` со своим API. На ESP32-S3 встроенная библиотека `BLE` ядра и так
работает поверх NimBLE (`BLEDevice.cpp` вызывает `nimble_port_init()`), поэтому
экономия flash/RAM достаётся бесплатно, а внешняя зависимость не нужна.

Собранный `keydeck` занимает ~626 КБ flash (47%).
