/*
 * keydeck_scan — диагностический скетч: находит, к каким GPIO подключены кнопки.
 *
 * Зачем нужен: распиновка неизвестна, а штатный keydeck.ino слушает только
 * захардкоженные KEY_PINS — если кнопки на других пинах, в консоли будет тишина.
 *
 * Как ищет. Для каждого пина быстро делается два чтения:
 *   1) пин в INPUT_PULLUP   -> pu
 *   2) пин в INPUT_PULLDOWN -> pd
 * Комбинация однозначно говорит, что с пином:
 *   pu=HIGH, pd=LOW   -> FLOAT      (висит в воздухе, ничего не подключено)
 *   pu=LOW,  pd=LOW   -> HELD_LOW   (притянут к GND)
 *   pu=HIGH, pd=HIGH  -> HELD_HIGH  (притянут к 3V3)
 * Это ловит нажатие при ЛЮБОЙ полярности: и «кнопка на GND», и «кнопка на 3V3»,
 * а заодно не зависит от того, успели ли мы подключиться к консоли до старта.
 *
 * Переход FLOAT -> HELD_* = нажатие, HELD_* -> FLOAT = отпускание.
 *
 * Пины, которые НЕ трогаем:
 *   19, 20      — native USB D-/D+ (через них идёт Serial и прошивка; дёргать
 *                 их подтяжками во время работы = рвать связь с маком)
 *   26..37      — SPI0/1 flash (26..32) и PSRAM на модулях с octal PSRAM (33..37);
 *                 на неизвестном модуле трогать их опасно
 *
 * Плата: ESP32S3 Dev Module. Библиотеки не нужны.
 */

const uint8_t SCAN_PINS[] = {
    0,  1,  2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12, 13, 14, 15,
    16, 17, 18, 21, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48,
};
const uint8_t NUM_SCAN = sizeof(SCAN_PINS) / sizeof(SCAN_PINS[0]);

const uint16_t DEBOUNCE_MS = 25;
const uint32_t HEARTBEAT_MS = 5000;
const uint16_t SETTLE_US = 300;  // дать подтяжке перезарядить провод

enum PinLevel : uint8_t {
  FLOAT = 0,      // ничего не подключено
  HELD_LOW = 1,   // притянут к GND  (замкнут на GND)
  HELD_HIGH = 2,  // притянут к 3V3  (замкнут на 3V3)
};

struct PinState {
  uint8_t stable;
  uint8_t lastRead;
  uint32_t lastChange;
  bool everActive;
};

PinState pins[NUM_SCAN];

uint8_t orderPin[NUM_SCAN];    // в каком порядке пины срабатывали впервые
uint8_t orderKind[NUM_SCAN];   // и на что они при этом замыкались
uint8_t orderCount = 0;

uint32_t lastHeartbeat = 0;

const char *levelName(uint8_t lvl) {
  switch (lvl) {
    case HELD_LOW: return "GND";
    case HELD_HIGH: return "3V3";
    default: return "float";
  }
}

// Одно «двойное» чтение: с подтяжкой вверх и с подтяжкой вниз.
void samplePin(uint8_t idx, bool &pu, bool &pd) {
  const uint8_t pin = SCAN_PINS[idx];
  pinMode(pin, INPUT_PULLUP);
  delayMicroseconds(SETTLE_US);
  pu = (digitalRead(pin) == HIGH);

  pinMode(pin, INPUT_PULLDOWN);
  delayMicroseconds(SETTLE_US);
  pd = (digitalRead(pin) == HIGH);
}

uint8_t classify(bool pu, bool pd) {
  if (!pu && !pd) return HELD_LOW;
  if (pu && pd) return HELD_HIGH;
  return FLOAT;  // pu=HIGH,pd=LOW — норма; pu=LOW,pd=HIGH — что-то внешнее, считаем float
}

void setup() {
  Serial.begin(115200);
  delay(1500);  // дать USB-CDC переподключиться после сброса

  Serial.println();
  Serial.println("=== keydeck pin scanner (both polarities) ===");
  Serial.printf("scanning %u pins: INPUT_PULLUP vs INPUT_PULLDOWN\n", NUM_SCAN);
  Serial.print("pins:");
  for (uint8_t i = 0; i < NUM_SCAN; i++) Serial.printf(" %u", SCAN_PINS[i]);
  Serial.println();

  for (uint8_t i = 0; i < NUM_SCAN; i++) {
    bool pu, pd;
    samplePin(i, pu, pd);
    const uint8_t s = classify(pu, pd);
    pins[i] = {s, s, millis(), s != FLOAT};
    if (s != FLOAT) {
      orderPin[orderCount] = SCAN_PINS[i];
      orderKind[orderCount] = s;
      orderCount++;
    }
  }

  // Пин, который «замкнут» уже на старте — это либо зажатая кнопка, либо
  // что-то распаянное на плате (LED, чужой сигнал), а не наша кнопка.
  Serial.print("active at boot (may be hardwired, not a button):");
  bool any = false;
  for (uint8_t i = 0; i < NUM_SCAN; i++) {
    if (pins[i].stable != FLOAT) {
      Serial.printf(" %u->%s", SCAN_PINS[i], levelName(pins[i].stable));
      any = true;
    }
  }
  if (!any) Serial.print(" (none)");
  Serial.println();

  Serial.println("Press buttons one by one, in order.");
  Serial.println("---------------------------------------------");
}

void loop() {
  const uint32_t now = millis();

  for (uint8_t i = 0; i < NUM_SCAN; i++) {
    bool pu, pd;
    samplePin(i, pu, pd);
    const uint8_t s = classify(pu, pd);

    if (s != pins[i].lastRead) {
      pins[i].lastRead = s;
      pins[i].lastChange = now;
    }

    if ((now - pins[i].lastChange) >= DEBOUNCE_MS && pins[i].stable != pins[i].lastRead) {
      const uint8_t prev = pins[i].stable;
      pins[i].stable = pins[i].lastRead;

      if (prev == FLOAT && pins[i].stable != FLOAT) {
        if (!pins[i].everActive) {
          pins[i].everActive = true;
          orderPin[orderCount] = SCAN_PINS[i];
          orderKind[orderCount] = pins[i].stable;
          orderCount++;
        }
        Serial.printf("PRESS   GPIO%-2u -> %-3s   (total keys seen: %u)\n",
                      SCAN_PINS[i], levelName(pins[i].stable), orderCount);
      } else if (prev != FLOAT && pins[i].stable == FLOAT) {
        Serial.printf("RELEASE GPIO%-2u (was %s)\n", SCAN_PINS[i], levelName(prev));
      } else {
        Serial.printf("CHANGE  GPIO%-2u %s -> %s\n",
                      SCAN_PINS[i], levelName(prev), levelName(pins[i].stable));
      }
    }
  }

  if (now - lastHeartbeat >= HEARTBEAT_MS) {
    lastHeartbeat = now;
    Serial.print("[alive] active now:");
    bool any = false;
    for (uint8_t i = 0; i < NUM_SCAN; i++) {
      if (pins[i].stable != FLOAT) {
        Serial.printf(" %u->%s", SCAN_PINS[i], levelName(pins[i].stable));
        any = true;
      }
    }
    if (!any) Serial.print(" none");

    Serial.printf("   | order (%u):", orderCount);
    for (uint8_t i = 0; i < orderCount; i++) {
      Serial.printf(" %u(%s)", orderPin[i], levelName(orderKind[i]));
    }
    Serial.println();
  }
}
