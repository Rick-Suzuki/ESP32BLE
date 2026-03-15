#include <Arduino.h>
#include "USB.h"
#include "USBHIDKeyboard.h"

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// -----------------------------------------------------------------------------
// BLE UART-style service UUIDs
// -----------------------------------------------------------------------------
static const char* BLE_DEVICE_NAME        = "PS5 Keyboard Bridge A";
static const char* SERVICE_UUID           = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
static const char* CHARACTERISTIC_UUID_RX = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";
static const char* CHARACTERISTIC_UUID_TX = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";

static const char* DEVICE_ID_UUID         = "6E400004-B5A3-F393-E0A9-E50E24DCCA9E";
static const char* DEVICE_ID_VALUE        = "A";

// -----------------------------------------------------------------------------
// Status output bits
//
// bit 0 = GPIO14
// bit 1 = GPIO13
// bit 2 = GPIO12
// bit 3 = GPIO11
// bit 4 = GPIO10 - app running
// bit 5 = GPIO9  - connected
// bit 6 = GPIO46 - receiving data
// bit 7 = GPIO3  - sending to keyboard
// -----------------------------------------------------------------------------
const int STATUS_BIT0_PIN        = 14;
const int STATUS_BIT1_PIN        = 13;
const int STATUS_BIT2_PIN        = 12;
const int STATUS_BIT3_PIN        = 11;
const int STATUS_APP_RUNNING_PIN = 10;
const int STATUS_CONNECTED_PIN   = 9;
const int STATUS_RX_PIN          = 46;
const int STATUS_TX_PIN          = 3;

uint8_t statusBits = 0;

unsigned long rxPulseUntilMs = 0;
unsigned long txPulseUntilMs = 0;

const unsigned long RX_PULSE_MS = 300;
const unsigned long TX_PULSE_MS = 300;

bool keyboardBusy = false;

// -----------------------------------------------------------------------------
// USB keyboard
// -----------------------------------------------------------------------------
USBHIDKeyboard Keyboard;

// -----------------------------------------------------------------------------
// BLE globals
// -----------------------------------------------------------------------------
BLEServer*         bleServer = nullptr;
BLECharacteristic* txCharacteristic = nullptr;
BLECharacteristic* rxCharacteristic = nullptr;
BLECharacteristic* idCharacteristic = nullptr;

bool bleClientConnected = false;
bool oldBleClientConnected = false;

// -----------------------------------------------------------------------------
// Simple line-based queue
// -----------------------------------------------------------------------------
String rxAccum;
String lineQueue[16];
int queueHead = 0;
int queueTail = 0;

// -----------------------------------------------------------------------------
// Sticky modifiers
// -----------------------------------------------------------------------------
bool modCtrl  = false;
bool modShift = false;
bool modAlt   = false;
bool modGui   = false;

// -----------------------------------------------------------------------------
// Status LED
// -----------------------------------------------------------------------------
#ifndef LED_BUILTIN
#define LED_BUILTIN 2
#endif

const int STATUS_LED_PIN = LED_BUILTIN;

bool ledState = false;
bool ledActivityFlashActive = false;
unsigned long ledActivityUntilMs = 0;

// -----------------------------------------------------------------------------
// Timing used for all normal key presses
// -----------------------------------------------------------------------------
int KEY_DOWN_MS = 20;
int KEY_GAP_MS  = 70;

// -----------------------------------------------------------------------------
// Forward declarations
// -----------------------------------------------------------------------------
void updateStatusLed();
void updateStatusOutputs();
void delayWithLed(unsigned long ms);
void triggerLedActivityFlash();
void triggerRxPulse();
void triggerTxPulse();
void setAppLetter(char appLetter);
void setStatusBit(uint8_t bitIndex, bool on);

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------
bool queueIsEmpty() {
  return queueHead == queueTail;
}

bool queueIsFull() {
  return ((queueTail + 1) % 16) == queueHead;
}

bool enqueueLine(const String& s) {
  if (queueIsFull()) return false;
  lineQueue[queueTail] = s;
  queueTail = (queueTail + 1) % 16;
  return true;
}

bool dequeueLine(String& out) {
  if (queueIsEmpty()) return false;
  out = lineQueue[queueHead];
  queueHead = (queueHead + 1) % 16;
  return true;
}

void delayWithLed(unsigned long ms) {
  unsigned long start = millis();
  while (millis() - start < ms) {
    updateStatusLed();
    updateStatusOutputs();
    delay(1);
  }
}

void triggerLedActivityFlash() {
  ledActivityFlashActive = true;
  ledActivityUntilMs = millis() + 1000;
}

void setStatusBit(uint8_t bitIndex, bool on) {
  if (on) {
    statusBits |= (1 << bitIndex);
  } else {
    statusBits &= ~(1 << bitIndex);
  }
}

void setAppLetter(char appLetter) {
  uint8_t value = 0;

  switch (appLetter) {
    case '0': value = 0; break;
    case '1': value = 1; break;
    case '2': value = 2; break;
    case '3': value = 3; break;

    case '4': value = 4; break;
    case '5': value = 5; break;
    case '6': value = 6; break;
    case '7': value = 7; break;

    case '8': value = 8; break;
    case '9': value = 9; break;
    case 'A': value = 10; break;
    case 'B': value = 11; break;

    case 'C': value = 12; break;
    case 'D': value = 13; break;
    case 'E': value = 14; break;
    case 'F': value = 15; break;

    default:  value = 0; break;
  }

  statusBits &= 0b11110000;
  statusBits |= (value & 0x0F);
}

void triggerRxPulse() {
  rxPulseUntilMs = millis() + RX_PULSE_MS;
}

void triggerTxPulse() {
  txPulseUntilMs = millis() + TX_PULSE_MS;
}

// -----------------------------------------------------------------------------
// Update GPIO status outputs
// -----------------------------------------------------------------------------
void updateStatusOutputs() {
  unsigned long now = millis();

  setStatusBit(4, true);                     // app running
  setStatusBit(5, bleClientConnected);       // connected
  setStatusBit(6, now < rxPulseUntilMs);     // receiving data
  setStatusBit(7, now < txPulseUntilMs);     // sending to keyboard

  digitalWrite(STATUS_BIT0_PIN,        (statusBits & (1 << 0)) ? HIGH : LOW);
  digitalWrite(STATUS_BIT1_PIN,        (statusBits & (1 << 1)) ? HIGH : LOW);
  digitalWrite(STATUS_BIT2_PIN,        (statusBits & (1 << 2)) ? HIGH : LOW);
  digitalWrite(STATUS_BIT3_PIN,        (statusBits & (1 << 3)) ? HIGH : LOW);
  digitalWrite(STATUS_APP_RUNNING_PIN, (statusBits & (1 << 4)) ? HIGH : LOW);
  digitalWrite(STATUS_CONNECTED_PIN,   (statusBits & (1 << 5)) ? HIGH : LOW);
  digitalWrite(STATUS_RX_PIN,          (statusBits & (1 << 6)) ? HIGH : LOW);
  digitalWrite(STATUS_TX_PIN,          (statusBits & (1 << 7)) ? HIGH : LOW);
}

// -----------------------------------------------------------------------------
// Update status LED
// Not connected: ON 10 ms, OFF 990 ms
// Connected:     ON 900 ms, OFF 100 ms
// Activity:      fast blink for 1 second after BLE data received
// -----------------------------------------------------------------------------
void updateStatusLed() {
  unsigned long now = millis();

  //
  // Keep activity flash active while:
  // 1. the 1-second minimum time has not expired, or
  // 2. keyboard sending is still in progress
  //
  if (ledActivityFlashActive) {
    if (!keyboardBusy && now >= ledActivityUntilMs) {
      ledActivityFlashActive = false;
    }
  }

  //
  // Activity flash overrides normal connected pattern
  // Fast blink: 50 ms on, 50 ms off
  //
  if (bleClientConnected && ledActivityFlashActive) {
    unsigned long cycle = now % 100;
    bool shouldBeOn = (cycle < 50);

    if (shouldBeOn != ledState) {
      ledState = shouldBeOn;
      digitalWrite(STATUS_LED_PIN, ledState ? HIGH : LOW);
    }
    return;
  }

  if (bleClientConnected) {
    unsigned long cycle = now % 1000;
    bool shouldBeOn = (cycle < 900);

    if (shouldBeOn != ledState) {
      ledState = shouldBeOn;
      digitalWrite(STATUS_LED_PIN, ledState ? HIGH : LOW);
    }
  } else {
    unsigned long cycle = now % 1000;
    bool shouldBeOn = (cycle < 10);

    if (shouldBeOn != ledState) {
      ledState = shouldBeOn;
      digitalWrite(STATUS_LED_PIN, ledState ? HIGH : LOW);
    }
  }
}
// -----------------------------------------------------------------------------
// Send status back to iPad over BLE notifications
// -----------------------------------------------------------------------------
void bleNotify(const String& msg) {
  if (!bleClientConnected || txCharacteristic == nullptr) return;
  txCharacteristic->setValue(msg.c_str());
  txCharacteristic->notify();
}

// -----------------------------------------------------------------------------
// Runtime timing command: set:20:70
// -----------------------------------------------------------------------------
bool handleSetTimingCommand(String line) {
  line.trim();
  line.toLowerCase();

  if (!line.startsWith("set:")) return false;

  int firstColon = line.indexOf(':');
  int secondColon = line.indexOf(':', firstColon + 1);

  if (firstColon < 0 || secondColon < 0) {
    bleNotify("ERROR: use set:down:gap");
    Serial.println("TIMING SET: ERROR:use set:down:gap");

    return true;
  }

  String downText = line.substring(firstColon + 1, secondColon);
  String gapText  = line.substring(secondColon + 1);

  downText.trim();
  gapText.trim();

  int newDown = downText.toInt();
  int newGap  = gapText.toInt();

  if (newDown < 0 || newDown > 1000 || newGap < 0 || newGap > 3000) {
    bleNotify("ERROR: timing out of range");
    Serial.println("TIMING SET: ERROR:timing out of range");
    return true;
  }

  KEY_DOWN_MS = newDown;
  KEY_GAP_MS  = newGap;

  String msg = "TIMING SET: down=" + String(KEY_DOWN_MS) +
               " gap=" + String(KEY_GAP_MS);
  bleNotify(msg);
  Serial.println(msg);

  return true;
}

// -----------------------------------------------------------------------------
// Modifier helpers
// -----------------------------------------------------------------------------
void pressPendingModifiers() {
  if (modCtrl)  Keyboard.press(KEY_LEFT_CTRL);
  if (modShift) Keyboard.press(KEY_LEFT_SHIFT);
  if (modAlt)   Keyboard.press(KEY_LEFT_ALT);
  if (modGui)   Keyboard.press(KEY_LEFT_GUI);
}

void releasePendingModifiers() {
  if (modCtrl)  Keyboard.release(KEY_LEFT_CTRL);
  if (modShift) Keyboard.release(KEY_LEFT_SHIFT);
  if (modAlt)   Keyboard.release(KEY_LEFT_ALT);
  if (modGui)   Keyboard.release(KEY_LEFT_GUI);
}

void clearPendingModifiers() {
  modCtrl  = false;
  modShift = false;
  modAlt   = false;
  modGui   = false;
}

// -----------------------------------------------------------------------------
// Key send helpers
// -----------------------------------------------------------------------------
void pressKeyTimed(uint8_t key) {
  pressPendingModifiers();

  Keyboard.press(key);
  delayWithLed(KEY_DOWN_MS);

  Keyboard.release(key);
  releasePendingModifiers();
  delayWithLed(KEY_GAP_MS);

  clearPendingModifiers();
}

void pressCtrlComboTimed(char keyChar) {
  Keyboard.press(KEY_LEFT_CTRL);
  Keyboard.press(keyChar);
  delayWithLed(KEY_DOWN_MS);
  Keyboard.releaseAll();
  delayWithLed(KEY_GAP_MS);
}

void pressCmdComboTimed(char keyChar) {
  Keyboard.press(KEY_LEFT_GUI);
  Keyboard.press(keyChar);
  delayWithLed(KEY_DOWN_MS);
  Keyboard.releaseAll();
  delayWithLed(KEY_GAP_MS);
}

// -----------------------------------------------------------------------------
// Type text with inline escapes
// \n  new line
// \t  tab
// \\  backslash
// \"  double quote
// -----------------------------------------------------------------------------
void typeTextSlow(const String& text) {
  for (size_t i = 0; i < text.length(); i++) {
    char c = text[i];

    if (c == '\\' && (i + 1) < text.length()) {
      char next = text[i + 1];

      if (next == 'n') {
        pressKeyTimed(KEY_RETURN);
        i++;
        continue;
      }

      if (next == 't') {
        pressKeyTimed(KEY_TAB);
        i++;
        continue;
      }

      if (next == '\\') {
        pressKeyTimed('\\');
        i++;
        continue;
      }

      if (next == '"') {
        pressKeyTimed('"');
        i++;
        continue;
      }
    }

    pressKeyTimed((uint8_t)c);
  }
}

// -----------------------------------------------------------------------------
// Command / text dispatcher
// -----------------------------------------------------------------------------
void sendCommandOrText(String line) {
  line.trim();
  if (line.length() == 0) return;

  if (handleSetTimingCommand(line)) return;

  if (line == "ct" || line == "ctl" || line == "control") 
  { modCtrl = true;  return; }
  
  if (line == "sh" || line == "shift") 
  { modShift = true; return; }
  
  if (line == "op" || line == "opt" || line == "option" || line == "alt")
  { modAlt = true; return; }
  
  if (line == "cm" || line == "cmd" || line == "command" || line == "win")
  { modGui = true; return; }

  if (line == "off") {
    clearPendingModifiers();
    Keyboard.releaseAll();
    return;
  }

	String line2 = line;
	line2.trim();
	line2.toLowerCase();
	
  if (line2 == "f1")  { pressKeyTimed(KEY_F1);  return; }
  if (line2 == "f2")  { pressKeyTimed(KEY_F2);  return; }
  if (line2 == "f3")  { pressKeyTimed(KEY_F3);  return; }
  if (line2 == "f4")  { pressKeyTimed(KEY_F4);  return; }

  if (line2 == "f5")  { pressKeyTimed(KEY_F5);  return; }
  if (line2 == "f6")  { pressKeyTimed(KEY_F6);  return; }
  if (line2 == "f7")  { pressKeyTimed(KEY_F7);  return; }
  if (line2 == "f8")  { pressKeyTimed(KEY_F8);  return; }
  
  if (line2 == "f9")  { pressKeyTimed(KEY_F9);  return; }
  if (line2 == "f10") { pressKeyTimed(KEY_F10); return; }
  if (line2 == "f11") { pressKeyTimed(KEY_F11); return; }
  if (line2 == "f12") { pressKeyTimed(KEY_F12); return; }
  
  if (line2 == "f13") { pressKeyTimed(KEY_F13); return; }
  if (line2 == "f14") { pressKeyTimed(KEY_F14); return; }
  if (line2 == "f15") { pressKeyTimed(KEY_F15); return; }
  if (line2 == "f16") { pressKeyTimed(KEY_F16); return; }
  
  if (line2 == "f17") { pressKeyTimed(KEY_F17); return; }
  if (line2 == "f18") { pressKeyTimed(KEY_F18); return; }
  if (line2 == "f19") { pressKeyTimed(KEY_F19); return; }
  if (line2 == "f20") { pressKeyTimed(KEY_F20); return; }

  if (line2 == "f21") { pressKeyTimed(KEY_F21); return; }
  if (line2 == "f22") { pressKeyTimed(KEY_F22); return; }
  if (line2 == "f23") { pressKeyTimed(KEY_F23); return; }
  if (line2 == "f24") { pressKeyTimed(KEY_F24); return; }

  if (line2 == "kp0") { pressKeyTimed(KEY_KP_0); return; }
  if (line2 == "kp1") { pressKeyTimed(KEY_KP_1); return; }
  if (line2 == "kp2") { pressKeyTimed(KEY_KP_2); return; }
  if (line2 == "kp3") { pressKeyTimed(KEY_KP_3); return; }
  if (line2 == "kp4") { pressKeyTimed(KEY_KP_4); return; }

  if (line2 == "kp5") { pressKeyTimed(KEY_KP_5); return; }
  if (line2 == "kp6") { pressKeyTimed(KEY_KP_6); return; }
  if (line2 == "kp7") { pressKeyTimed(KEY_KP_7); return; }
  if (line2 == "kp8") { pressKeyTimed(KEY_KP_8); return; }
  if (line2 == "kp9") { pressKeyTimed(KEY_KP_9); return; }

  if (line2 == "kp.") { pressKeyTimed(KEY_KP_DOT); return; }
  if (line2 == "kp+") { pressKeyTimed(KEY_KP_PLUS); return; }
  if (line2 == "kp-") { pressKeyTimed(KEY_KP_MINUS); return; }
  if (line2 == "kp/") { pressKeyTimed(KEY_KP_SLASH); return; }
  if (line2 == "kp*") { pressKeyTimed(KEY_KP_ASTERISK); return; }
  if (line2 == "kpe") { pressKeyTimed(KEY_KP_ENTER); return; }

  if (line2 == "enter" || line == "ret") { pressKeyTimed(KEY_RETURN);    return; }
  if (line2 == "tab"   || line == "t")   { pressKeyTimed(KEY_TAB);       return; }
  if (line2 == "bs"    || line == "b")   { pressKeyTimed(KEY_BACKSPACE); return; }
  if (line2 == "esc"   || line == "e")   { pressKeyTimed(KEY_ESC);       return; }
  if (line2 == "up"    || line == "u")   { pressKeyTimed(KEY_UP_ARROW);  return; }
  if (line2 == "down"  || line == "d")   { pressKeyTimed(KEY_DOWN_ARROW);return; }
  if (line2 == "left"  || line == "l")   { pressKeyTimed(KEY_LEFT_ARROW);return; }
  if (line2 == "right" || line == "r")   { pressKeyTimed(KEY_RIGHT_ARROW);return; }

  if (line2 == "ca") {    pressCtrlComboTimed('a');    return;  }
  if (line2 == "cc") {    pressCtrlComboTimed('c');    return;  }
  if (line2 == "cv") {    pressCtrlComboTimed('v');    return;  }
  if (line2 == "cx") {    pressCtrlComboTimed('x');    return;  }

  if (line2 == "ma") {    pressCmdComboTimed('a');    return;  }
  if (line2 == "mc") {    pressCmdComboTimed('c');    return;  }
  if (line2 == "mv") {    pressCmdComboTimed('v');    return;  }
  if (line2 == "mx") {    pressCmdComboTimed('x');    return;  }

  typeTextSlow(line);
}

// -----------------------------------------------------------------------------
// BLE callbacks
// -----------------------------------------------------------------------------
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override {
    bleClientConnected = true;
  }

  void onDisconnect(BLEServer* pServer) override {
    bleClientConnected = false;
  }
};

class MyRxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) override {
    String value = pCharacteristic->getValue();
    if (value.length() == 0) return;

    triggerLedActivityFlash();
    triggerRxPulse();
    updateStatusOutputs();

    for (int i = 0; i < value.length(); i++) {
      char c = value[i];

      if (c == '\r') continue;

      if (c == '\n') {
        if (rxAccum.length() > 0) {
          bool ok = enqueueLine(rxAccum);
          if (ok) {
            bleNotify("QUEUED: " + rxAccum);
          } else {
            bleNotify("ERROR: queue full");
          }
          rxAccum = "";
        }
      } else {
        rxAccum += c;
      }
    }
  }
};

// -----------------------------------------------------------------------------
// BLE setup
// -----------------------------------------------------------------------------
void setupBLE() {
  BLEDevice::init(BLE_DEVICE_NAME);

  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new MyServerCallbacks());

  BLEService* service = bleServer->createService(SERVICE_UUID);

  txCharacteristic = service->createCharacteristic(
    CHARACTERISTIC_UUID_TX,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  txCharacteristic->addDescriptor(new BLE2902());

  rxCharacteristic = service->createCharacteristic(
    CHARACTERISTIC_UUID_RX,
    BLECharacteristic::PROPERTY_WRITE |
    BLECharacteristic::PROPERTY_WRITE_NR
  );
  rxCharacteristic->setCallbacks(new MyRxCallbacks());

  idCharacteristic = service->createCharacteristic(
    DEVICE_ID_UUID,
    BLECharacteristic::PROPERTY_READ
  );
  idCharacteristic->setValue(DEVICE_ID_VALUE);

  service->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->start();
}

// -----------------------------------------------------------------------------
// Setup
// -----------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  delay(1000);

  pinMode(STATUS_LED_PIN, OUTPUT);
  digitalWrite(STATUS_LED_PIN, LOW);

  pinMode(STATUS_BIT0_PIN, OUTPUT);
  pinMode(STATUS_BIT1_PIN, OUTPUT);
  pinMode(STATUS_BIT2_PIN, OUTPUT);
  pinMode(STATUS_BIT3_PIN, OUTPUT);
  pinMode(STATUS_APP_RUNNING_PIN, OUTPUT);
  pinMode(STATUS_CONNECTED_PIN, OUTPUT);
  pinMode(STATUS_RX_PIN, OUTPUT);
  pinMode(STATUS_TX_PIN, OUTPUT);

  digitalWrite(STATUS_BIT0_PIN, LOW);
  digitalWrite(STATUS_BIT1_PIN, LOW);
  digitalWrite(STATUS_BIT2_PIN, LOW);
  digitalWrite(STATUS_BIT3_PIN, LOW);
  digitalWrite(STATUS_APP_RUNNING_PIN, LOW);
  digitalWrite(STATUS_CONNECTED_PIN, LOW);
  digitalWrite(STATUS_RX_PIN, LOW);
  digitalWrite(STATUS_TX_PIN, LOW);

  setAppLetter(DEVICE_ID_VALUE[0]);

  updateStatusOutputs();

  Keyboard.begin(KeyboardLayout_en_US);
  USB.begin();

  setupBLE();

  Serial.println("ESP32-S3 PS5 keyboard bridge started");
  Serial.print("BLE name: ");
  Serial.println(BLE_DEVICE_NAME);
  Serial.print("BLE device ID: ");
  Serial.println(DEVICE_ID_VALUE);

  delay(500);
}

// -----------------------------------------------------------------------------
// Main loop
// -----------------------------------------------------------------------------
void loop() {
  updateStatusLed();
  updateStatusOutputs();

  if (bleClientConnected && !oldBleClientConnected) {
    oldBleClientConnected = bleClientConnected;
    bleNotify("CONNECTED");
    Serial.println("BLE client connected");
  }

  if (!bleClientConnected && oldBleClientConnected) {
    delayWithLed(200);
    bleServer->startAdvertising();
    oldBleClientConnected = bleClientConnected;
    Serial.println("BLE client disconnected, advertising restarted");
  }

  String line;
  if (dequeueLine(line)) {
    Serial.print("sent: ");
	Serial.print(line);
    Serial.println("");

    keyboardBusy = true;

    triggerTxPulse();
    triggerLedActivityFlash();
    updateStatusOutputs();

    sendCommandOrText(line);

    keyboardBusy = false;

    bleNotify("sent: " + line);
    delayWithLed(40);
}
}
