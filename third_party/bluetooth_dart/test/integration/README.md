# Hardware integration test

`nus_echo_test.dart` runs the full GATT loop against a real peripheral:
scan, connect, discover, subscribe, write, notify.

Skipped by default; only runs when `BLE_TEST_DEVICE` is set.

Requires a separate BLE peripheral (btleplug is central-only).

## 1. Build the native library

The test uses the FFI backend, which loads `bluetooth_core`. Build it once (the
test resolves it from `native/bluetooth_core/target/{debug,release}/`):

```sh
cargo build --manifest-path native/bluetooth_core/Cargo.toml
```

## 2. Set up a reference peripheral

### Option A: ESP32 NUS echo (recommended; enables the automated round-trip)

Flash an ESP32 with a Nordic UART Service (NUS) server that **echoes** each write
back as a notification. With the stock ESP32 Arduino core:

```cpp
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLE2902.h>

#define SERVICE_UUID "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define RX_UUID      "6e400002-b5a3-f393-e0a9-e50e24dcca9e" // central writes here
#define TX_UUID      "6e400003-b5a3-f393-e0a9-e50e24dcca9e" // we notify here

BLECharacteristic* txChar;

class RxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    String v = c->getValue();                       // bytes the central wrote
    txChar->setValue((uint8_t*)v.data(), v.length());
    txChar->notify();                               // echo straight back
  }
};

void setup() {
  BLEDevice::init("nus-echo");                      // <-- BLE_TEST_DEVICE name
  BLEServer* server = BLEDevice::createServer();
  BLEService* service = server->createService(SERVICE_UUID);

  BLECharacteristic* rx = service->createCharacteristic(
      RX_UUID,
      BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  rx->setCallbacks(new RxCallbacks());

  txChar = service->createCharacteristic(TX_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  txChar->addDescriptor(new BLE2902());             // CCCD (optional on core 3.x)

  service->start();
  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->start();
}

void loop() { delay(1000); }
```

Notes: on ESP32 Arduino core 2.x `getValue()` returns `std::string` (use
`.c_str()`/`.length()`); core 3.x returns Arduino `String` as above. The
advertised name (`"nus-echo"`) is what you pass as `BLE_TEST_DEVICE`.

### Option B: nRF Connect mobile (no flashing; discover-only)

Install nRF Connect for Mobile (Android/iOS), open the **GATT Server** /
Advertiser, add the NUS service and the RX (write) + TX (notify) characteristics,
and start advertising. nRF Connect does **not** auto-echo, so use it to validate
`scan -> connect -> discover` (run **without** `BLE_TEST_ECHO`). You can still send
a notification by hand from its UI to watch one arrive.

### Option C: `bluer` on Linux (scripted; advanced)

On a Linux box / Raspberry Pi, adapt the `gatt_server` example from the
[`bluer`](https://github.com/bluez/bluer) crate to expose NUS and echo writes.
Fully in-house and reproducible, but more setup than an ESP32.

## 3. Run

`bluetooth_dart` is the working directory below; adjust the path if you run from
the repo root. `-r expanded` streams the progress/GATT-table prints.

**bash / macOS / Linux:**

```sh
BLE_TEST_DEVICE="nus-echo" BLE_TEST_ECHO=1 \
  dart test packages/bluetooth_dart/test/integration/nus_echo_test.dart -r expanded
```

**PowerShell / Windows:**

```powershell
$env:BLE_TEST_DEVICE = "nus-echo"; $env:BLE_TEST_ECHO = "1"
dart test packages/bluetooth_dart/test/integration/nus_echo_test.dart -r expanded
```

Discover-only against any connectable device (e.g. nRF Connect, a heart-rate
strap), omit `BLE_TEST_ECHO`:

```powershell
$env:BLE_TEST_DEVICE = "Polar H10"
dart test packages/bluetooth_dart/test/integration/nus_echo_test.dart -r expanded
```

## Environment variables

| Variable | Required | Default | Meaning |
|---|---|---|---|
| `BLE_TEST_DEVICE` | yes | | Advertised name (substring, case-insensitive) or exact device id to target. Without it the test is skipped. |
| `BLE_TEST_ECHO` | no | off | When `1`/`true`/`yes`, also subscribe + write and assert the bytes are echoed back on the notify characteristic. Requires an echo peripheral (Option A). |
| `BLE_TEST_SERVICE` | no | NUS service `6e400001-...` | Service UUID used for the echo round-trip. |
| `BLE_TEST_WRITE_CHAR` | no | NUS RX `6e400002-...` | Characteristic the central writes to. |
| `BLE_TEST_NOTIFY_CHAR` | no | NUS TX `6e400003-...` | Characteristic the central subscribes to. |
| `BLUETOOTH_CORE_LIB` | no | auto | Explicit path to the built `bluetooth_core` library, if not found automatically. |

## Interpreting the output

- **Success (echo mode):** prints the discovered GATT table, then `Writing ...` /
  `Received ...` with matching bytes.
- **`Native backend not active`:** the native library wasn't found, run the
  `cargo build` in step 1 (or set `BLUETOOTH_CORE_LIB`).
- **`No device matching ... was seen`:** the peripheral isn't advertising, is out of
  range, or the name doesn't match `BLE_TEST_DEVICE`.
- **`connect ... timed out`:** the device isn't connectable (e.g. a beacon), the
  native layer gives up after 20s rather than hanging.
- **`No notification ... within 10s`:** the peripheral isn't echoing, use an echo
  peripheral (Option A) or drop `BLE_TEST_ECHO`.
