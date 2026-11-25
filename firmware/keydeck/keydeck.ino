/*
 * keydeck — ESP32-S3 BLE macro keypad, 8 keys + power + LED + RGB.
 *
 * Скетч шлёт F13..F20; действия — в приложении на маке.
 *
 * Питание (кнопка POWER, без фиксации):
 *   долгое нажатие — deep sleep («выкл»), пробуждение только POWER;
 *   короткое — переключить авто-сон (idle 2ч). Режим в NVS.
 * Восемь макро-кнопок сон/пробуждение не трогают.
 *
 * Индикация:
 *   LED GPIO7 — «устройство вкл» (горит, пока не sleep).
 *   RGB GPIO48 (WS2812 на плате): радуга при старте; режим —
 *     янтарный = без авто-сна, бирюзовый = авто-сон 2ч;
 *     перед deep sleep — чёрный (гасим).
 *
 * Распиновка доп. железа:
 *   POWER  GPIO 5  — тактовая кнопка на GND
 *   LED    GPIO 7  — анод через 220Ω, катод GND
 *   BAT_ADC GPIO 8 — середина делителя с B+ аккумулятора (см. ниже)
 *
 * Батарея в BLE (Battery Service 0x180F):
 *   Без делителя macOS всегда видит 100% (дефолт библиотеки).
 *   Делитель 1:1 с B+ (до LDO/платы):
 *     B+ --[100k]--+--[100k]-- GND
 *                  |
 *                GPIO8
 *   BAT_DIVIDER_RATIO = 2.0. LiPo 3.3…4.2 В → 0…100%.
 *
 * ВАЖНО при прошивке:
 *   USB Mode / USB CDC On Boot — как в build.sh (hwcdc + cdc).
 */

#include <BleKeyboard.h>
#include <Preferences.h>
#include <esp_sleep.h>
#include <driver/rtc_io.h>
#include <math.h>

// ── 8 клавиш ─────────────────────────────────────────────────────────────────
const uint8_t NUM_KEYS = 8;
// Пример по порядку: кнопка 1..8 слева направо, сверху вниз.
// На собранной плате провода припаяны раньше, и массив потом подгонялся
// под фактические пины. В репозитории оставлен прямой порядок, не эта пайка.
const uint8_t KEY_PINS[NUM_KEYS] = {1, 2, 3, 4, 13, 12, 11, 10};

const uint8_t KEY_CODES[NUM_KEYS] = {
    KEY_F13, KEY_F14, KEY_F15, KEY_F16,
    KEY_F17, KEY_F18, KEY_F19, KEY_F20,
};

// ── Питание / индикация ──────────────────────────────────────────────────────
const uint8_t POWER_PIN = 5;
const uint8_t LED_PIN = 7;
const uint8_t RGB_PIN = 48;  // onboard WS2812
const uint8_t BAT_ADC_PIN = 8;

/// Во сколько раз делитель уменьшает напряжение B+ (равные резисторы → 2.0).
const float BAT_DIVIDER_RATIO = 2.0f;
/// Ниже этого на пине (мВ) считаем «делителя нет» — не шлём фейковый %.
const uint16_t BAT_SENSE_MIN_MV = 200;
const uint32_t BAT_UPDATE_MS = 30000UL;

const uint16_t DEBOUNCE_MS = 30;
const uint16_t POWER_LONG_MS = 1500;
const uint32_t IDLE_SLEEP_MS = 2UL * 60UL * 60UL * 1000UL;

const uint16_t KEYDECK_VID = 0x303A;
const uint16_t KEYDECK_PID = 0x8391;

BleKeyboard bleKeyboard("keydeck", "Evgeniy", 100);
Preferences prefs;

struct KeyState {
  bool stable;
  bool lastRead;
  uint32_t lastChange;
};

KeyState keys[NUM_KEYS];
KeyState powerBtn;
uint32_t lastActivityMs = 0;
uint32_t powerDownSinceMs = 0;
uint32_t lastBatteryMs = 0;
bool powerArmed = false;
bool idleSleepEnabled = true;
bool batterySenseOk = false;
uint8_t lastBatteryPct = 100;

/// LiPo 1S: напряжение → % (кусочно-линейно).
static uint8_t voltageToPercent(float vbat) {
  static const float table[][2] = {
      {4.20f, 100}, {4.10f, 90}, {4.00f, 75}, {3.90f, 60},
      {3.80f, 45},  {3.70f, 30}, {3.60f, 15}, {3.50f, 5},
      {3.30f, 0},
  };
  if (vbat >= table[0][0]) {
    return 100;
  }
  const size_t n = sizeof(table) / sizeof(table[0]);
  if (vbat <= table[n - 1][0]) {
    return 0;
  }
  for (size_t i = 0; i + 1 < n; i++) {
    const float v0 = table[i][0];
    const float v1 = table[i + 1][0];
    if (vbat <= v0 && vbat >= v1) {
      const float t = (vbat - v1) / (v0 - v1);
      const float p = table[i + 1][1] + t * (table[i][1] - table[i + 1][1]);
      if (p <= 0) {
        return 0;
      }
      if (p >= 100) {
        return 100;
      }
      return (uint8_t)(p + 0.5f);
    }
  }
  return 0;
}

/// Среднее на пине (мВ) и пересчёт в B+ (В). NaN если делителя нет.
static float readBatteryVolts(uint16_t *outPinMv) {
  uint32_t sumMv = 0;
  const uint8_t samples = 16;
  for (uint8_t i = 0; i < samples; i++) {
    sumMv += analogReadMilliVolts(BAT_ADC_PIN);
    delayMicroseconds(200);
  }
  const uint16_t pinMv = sumMv / samples;
  if (outPinMv) {
    *outPinMv = pinMv;
  }
  if (pinMv < BAT_SENSE_MIN_MV) {
    return NAN;
  }
  return (pinMv / 1000.0f) * BAT_DIVIDER_RATIO;
}

static void updateBatteryBle(bool force) {
  uint16_t pinMv = 0;
  const float v = readBatteryVolts(&pinMv);
  if (isnan(v)) {
    if (batterySenseOk || force) {
      Serial.printf("battery: no sense (GPIO%u=%u mV) — проверь B+/GND/середину\n",
                    BAT_ADC_PIN, pinMv);
    }
    batterySenseOk = false;
    return;
  }
  batterySenseOk = true;
  uint8_t pct = voltageToPercent(v);
  // Не дёргать хост на ±1% от шума ADC.
  if (!force && pct == lastBatteryPct) {
    return;
  }
  if (!force && (pct + 1 == lastBatteryPct || lastBatteryPct + 1 == pct)) {
    return;
  }
  lastBatteryPct = pct;
  bleKeyboard.setBatteryLevel(pct);
  Serial.printf("battery: %.2f V → %u%%\n", v, pct);
}

static void ledSet(bool on) { digitalWrite(LED_PIN, on ? HIGH : LOW); }

static void rgbSet(uint8_t r, uint8_t g, uint8_t b) {
  // ESP32 core: rgbLedWrite принимает R,G,B и шлёт GRB для WS2812.
  rgbLedWrite(RGB_PIN, r, g, b);
}

static void rgbOff() { rgbSet(0, 0, 0); }

/// Режим: янтарный = без авто-сна; бирюзовый = авто-сон 2ч.
static void rgbShowMode(bool sleepOn) {
  if (sleepOn) {
    rgbSet(0, 40, 48);   // бирюза
  } else {
    rgbSet(48, 22, 0);   // янтарь
  }
}

static void rgbPulseMode(bool sleepOn) {
  rgbOff();
  delay(60);
  rgbShowMode(sleepOn);
  delay(220);
  rgbOff();
  delay(80);
  rgbShowMode(sleepOn);
  delay(220);
  // После сигнала — тусклый «статус», чтобы не жрать батарею.
  if (sleepOn) {
    rgbSet(0, 6, 8);
  } else {
    rgbSet(8, 4, 0);
  }
}

/// Радуга при старте, потом цвет режима.
static void rgbBootShow(bool sleepOn) {
  static const uint8_t palette[][3] = {
      {48, 0, 0},   {48, 24, 0}, {48, 48, 0}, {0, 48, 0},
      {0, 40, 48},  {0, 0, 48},  {32, 0, 48}, {48, 0, 32},
  };
  for (uint8_t i = 0; i < 8; i++) {
    rgbSet(palette[i][0], palette[i][1], palette[i][2]);
    delay(90);
  }
  rgbPulseMode(sleepOn);
}

static void blinkTimes(uint8_t times) {
  for (uint8_t i = 0; i < times; i++) {
    ledSet(true);
    delay(120);
    ledSet(false);
    delay(140);
  }
  ledSet(true);
}

static void loadPrefs() {
  prefs.begin("keydeck", false);
  idleSleepEnabled = prefs.getBool("idleSleep", true);
}

static void saveIdleSleep(bool enabled) {
  idleSleepEnabled = enabled;
  prefs.putBool("idleSleep", enabled);
}

/// Deep sleep: будит только POWER. RGB гасим до сна.
static void enterPowerOff(const char *reason) {
  Serial.printf("power off (%s) — deep sleep, wake on POWER gpio %u\n",
                reason, POWER_PIN);
  Serial.flush();

  ledSet(false);
  rgbOff();
  delay(5);  // WS2812 успеть принять «чёрный»
  rgbOff();

  bleKeyboard.end();
  BLEDevice::deinit(false);

  Serial.println("waiting for POWER release...");
  Serial.flush();
  const uint32_t waitStart = millis();
  while (digitalRead(POWER_PIN) == LOW) {
    if ((millis() - waitStart) > 30000UL) {
      break;
    }
    delay(10);
  }
  delay(80);

  // Ещё раз погасить после ожидания (на случай шума на линии).
  rgbOff();

  for (uint8_t i = 0; i < NUM_KEYS; i++) {
    rtc_gpio_deinit((gpio_num_t)KEY_PINS[i]);
  }

  const gpio_num_t pwr = (gpio_num_t)POWER_PIN;
  rtc_gpio_init(pwr);
  rtc_gpio_set_direction(pwr, RTC_GPIO_MODE_INPUT_ONLY);
  rtc_gpio_pullup_en(pwr);
  rtc_gpio_pulldown_dis(pwr);

  esp_sleep_pd_config(ESP_PD_DOMAIN_RTC_PERIPH, ESP_PD_OPTION_ON);
  esp_sleep_enable_ext1_wakeup(1ULL << POWER_PIN, ESP_EXT1_WAKEUP_ANY_LOW);
  esp_deep_sleep_start();
}

static void handlePowerButton(uint32_t now) {
  const bool raw = (digitalRead(POWER_PIN) == LOW);

  if (raw != powerBtn.lastRead) {
    powerBtn.lastRead = raw;
    powerBtn.lastChange = now;
  }

  if ((now - powerBtn.lastChange) < DEBOUNCE_MS) {
    return;
  }

  if (powerBtn.stable != powerBtn.lastRead) {
    powerBtn.stable = powerBtn.lastRead;
    if (powerBtn.stable) {
      powerDownSinceMs = now;
      if (!powerArmed) {
        return;
      }
    } else {
      if (!powerArmed) {
        powerArmed = true;
        Serial.println("power armed");
        return;
      }
      const uint32_t held = now - powerDownSinceMs;
      lastActivityMs = now;
      if (held >= POWER_LONG_MS) {
        enterPowerOff("long press");
        return;
      }
      saveIdleSleep(!idleSleepEnabled);
      Serial.printf("idle sleep %s\n", idleSleepEnabled ? "ON (2h)" : "OFF");
      blinkTimes(idleSleepEnabled ? 2 : 1);
      rgbPulseMode(idleSleepEnabled);
    }
  } else if (powerBtn.stable && powerArmed &&
             (now - powerDownSinceMs) >= POWER_LONG_MS) {
    enterPowerOff("long press");
  }
}

void setup() {
  Serial.begin(115200);
  delay(200);

  pinMode(LED_PIN, OUTPUT);
  ledSet(false);
  rgbOff();

  loadPrefs();

  const esp_sleep_wakeup_cause_t cause = esp_sleep_get_wakeup_cause();
  if (cause == ESP_SLEEP_WAKEUP_EXT1) {
    Serial.println("keydeck: wake from power button");
  } else {
    Serial.println("keydeck: boot");
  }

  rtc_gpio_deinit((gpio_num_t)POWER_PIN);
  pinMode(POWER_PIN, INPUT_PULLUP);
  powerBtn = {false, false, 0};
  powerArmed = (digitalRead(POWER_PIN) != LOW);

  for (uint8_t i = 0; i < NUM_KEYS; i++) {
    rtc_gpio_deinit((gpio_num_t)KEY_PINS[i]);
    pinMode(KEY_PINS[i], INPUT_PULLUP);
    keys[i] = {false, false, 0};
  }

  // Радуга сразу при включении, пока BLE поднимается.
  rgbBootShow(idleSleepEnabled);

  analogSetPinAttenuation(BAT_ADC_PIN, ADC_11db);
  pinMode(BAT_ADC_PIN, INPUT);

  bleKeyboard.set_vendor_id(KEYDECK_VID);
  bleKeyboard.set_product_id(KEYDECK_PID);
  bleKeyboard.begin();

  lastActivityMs = millis();
  lastBatteryMs = millis();
  updateBatteryBle(/*force=*/true);
  ledSet(true);
  Serial.printf("keydeck: BLE up, idleSleep=%s, POWER=%u LED=%u RGB=%u BAT_ADC=%u\n",
                idleSleepEnabled ? "on" : "off", POWER_PIN, LED_PIN, RGB_PIN,
                BAT_ADC_PIN);
  blinkTimes(idleSleepEnabled ? 2 : 1);
}

void loop() {
  const uint32_t now = millis();

  static bool wasConnected = false;
  const bool connected = bleKeyboard.isConnected();
  if (connected != wasConnected) {
    wasConnected = connected;
    Serial.println(connected ? "host connected" : "host disconnected");
    // Короткий акцент при BLE: зелёный / красный.
    if (connected) {
      rgbSet(0, 36, 0);
      delay(120);
      if (idleSleepEnabled) {
        rgbSet(0, 6, 8);
      } else {
        rgbSet(8, 4, 0);
      }
      updateBatteryBle(/*force=*/true);
    } else {
      rgbSet(40, 0, 0);
      delay(120);
      if (idleSleepEnabled) {
        rgbSet(0, 6, 8);
      } else {
        rgbSet(8, 4, 0);
      }
    }
  }

  if ((now - lastBatteryMs) >= BAT_UPDATE_MS) {
    lastBatteryMs = now;
    updateBatteryBle(/*force=*/false);
  }

  handlePowerButton(now);

  for (uint8_t i = 0; i < NUM_KEYS; i++) {
    const bool raw = (digitalRead(KEY_PINS[i]) == LOW);

    if (raw != keys[i].lastRead) {
      keys[i].lastRead = raw;
      keys[i].lastChange = now;
    }

    if ((now - keys[i].lastChange) >= DEBOUNCE_MS && keys[i].stable != keys[i].lastRead) {
      keys[i].stable = keys[i].lastRead;

      if (keys[i].stable) {
        lastActivityMs = now;
        if (bleKeyboard.isConnected()) {
          bleKeyboard.write(KEY_CODES[i]);
          Serial.printf("key %u -> F%u\n", i, 13 + i);
        } else {
          Serial.printf("key %u -> F%u (not connected)\n", i, 13 + i);
        }
      }
    }
  }

  if (idleSleepEnabled && (now - lastActivityMs) >= IDLE_SLEEP_MS) {
    enterPowerOff("idle 2h");
  }

  delay(5);
}
