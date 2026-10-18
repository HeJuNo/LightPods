# BlazePod – BLE Pod Protocol & Connection Logic (Step 1)

Target: `co.blazepod.blazepod` **v6.0.1 (versionCode 462)**, minSdk 29 / targetSdk 35, pulled from an Android test device.
Method: static analysis only (jadx 1.5.6 decompile of `base.apk`). R8-obfuscated Kotlin; names below are the obfuscated
class names in `decompiled/sources/` followed by the role they were identified as.

> **Evidence levels.** Everything here is *observed in decompiled code* unless marked **[inferred]**. Nothing was
> confirmed against live pod traffic yet (see §11 for how to do that).

---

## 1. Component map

| Obfuscated class | Role |
|---|---|
| `de/AbstractC5893a` | Public facade of the in-app "blazepodcore" SDK (init, start/stop, limits, intensity, LiveData getters) |
| `je/p0` (singleton via `je/f0`) | **PodManager** – scanning, pod registry, BT/location receivers, lifecycle |
| `je/e0` | PodManager handler on thread "Pods thread": connection-state machine, auth, bring-up, retries |
| `je/b0` | Hit dispatcher (same thread): fan-out of `(podId, reactionMs)` to registered listeners (`je/c0`) |
| `je/C8063i` (`je.i`) | **Pod model** – link state, intent, light state, firmware, battery, hit filtering |
| `je/C8071q` (`je.q`) | Per-pod **GATT manager** (`BluetoothGattCallback`) + operation queue |
| `je/HandlerC8067m` (`je.m`) | GATT manager message loop on thread "PGM thread" |
| `zp/*` | GATT operations: `b` read, `c` NUS write, `e` enable-notify, `f` light write |
| `je/q0` | UUID constants |
| `je/C8065k` (`je.k`) | `AdvertiseData(advertiseKey, advertiseVersion, advertiseBattery, isAdvertiseCharger)` |
| `je/C8079y`, `je/C8077w` | Scan callbacks: pods / DFU bootloader pods |
| `yp/*` | Enums: detection mode, light-off flag, charger state, light-end reason, LED level table |
| `ie/EnumC7506h`, `ie/EnumC7503e` | Pod colour, light intensity |
| `ge/C6795b` | Blink helper (on/off state machine over a set of pods) |
| `com/blazepod/blazepodcore/repositories/*` | SharedPreferences store (names, auto-connect list, last connected) |
| `com/blazepod/blazepodcore/services/DisconnectJobService` | Delayed "disconnect all" job |
| `no/nordicsemi/android/dfu/*` | Nordic DFU library (firmware update, out of scope here) |

## 2. GATT profile

| Service | Characteristic | Props used | Purpose |
|---|---|---|---|
| `50C928BD-4CB8-4C84-B745-0E58A0280CD6` (also **scan filter**) | `50C9727E-…` | notify | **Touch / hit** events |
| `50C97BFA-4CB8-4C84-B745-0E58A0280CD6` | `50C912A2-…` | write | **LED colour** |
| (same vendor base) | `50C912CF-…` | notify | Light-end reason (parsed, **never subscribed**) |
| | `50C912CD-…` | – | Declared, unused |
| `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` (Nordic UART) | `6E400002-…` RX | write | ASCII commands |
| | `6E400003-…` TX | notify | ASCII responses |
| `180F` Battery | `2A19` | read + notify | Battery % |
| `180A` Device Info | `2A24` model, `2A25` serial, `2A26` firmware | read | Info (`2A27` declared, unused) |

CCCD `2902` is written with `ENABLE_NOTIFICATION_VALUE`.

## 3. Advertising & discovery (`je/p0.A`, `je/C8079y`)

* Scan: `ScanFilter(serviceUuid = 50C928BD-…)`, `SCAN_MODE_LOW_LATENCY`.
* **Samsung Galaxy S6 / S6 edge workaround** (`fr/AbstractC6528a`, 31 models `SM-G920*`/`SM-G925*`): no filter; instead
  accept only results whose scan-record name is `"BlazePod"`.
* Manufacturer-specific data, company ID **2519 (0x09D7)**, exactly 6 bytes:

  | Byte | Meaning |
  |---|---|
  | 0 | bit0 = on charger; bits 1-7 = battery % |
  | 1 | `advertiseVersion` (seeds auth) |
  | 2-5 | `advertiseKey` (4-byte challenge) |

  Presence of this data sets `je.i.M = true` ("secure pod"): only then is the auth handshake sent and charger polling done.
* Pod identity on Android = `BluetoothDevice.hashCode()` (derived from the MAC). Used as key everywhere and in prefs.
* Every sighting re-arms a **30 s visibility timer** (`dr/RunnableC6009k`); on expiry a pod that is not wanted connected is
  marked invisible (`d0(false)`), not deleted.
* Pods in the persisted auto-connect list are connected immediately on first sighting.
* New pods get a sticky name `"Pod %03d"` from an incrementing counter (`key_pod_names_index`).

### DFU / bootloader pods (`je/C8077w`, `p0.B`)
Separate unfiltered scan for local name **`BlazeDfu`**. The bootloader advertises with MAC = original MAC **+1** in the last
octet; the app subtracts 1 to look the original pod name up. 10 s visibility timeout. Only active while the update screen
requests it (`f36773d`).

## 4. Connection state machine

Two orthogonal variables per pod:

* **Link state** `je.i.f`: `DISCONNECTED → CONNECTED → READY`, plus `UNKNOWN` (= error).
* **Intent** `je.i.b`: `NOT_SET`, `CONNECT`, `DISCONNECT_AND_CLOSE`.

GATT callbacks → `je.z` → message 1 on `je.e0`:

| New link state | Intent = CONNECT | Intent ≠ CONNECT |
|---|---|---|
| `CONNECTED` (`status 0, newState 2`) | `discoverServices()` | disconnect + close |
| `READY` (`onServicesDiscovered` OK) | **bring-up** (§6), vibrate 50 ms, persist `pod_last_connected_<id>` | disconnect + close |
| `DISCONNECTED` (`status 0, newState 0`) | battery = -1; if secure pod: scan 300 ms; reconnect after 300 ms | – |
| `UNKNOWN` (`status ≠ 0` or discover failed) | close GATT (on attempt 5 also call hidden `BluetoothGatt.refresh()` to clear cache), recreate GATT manager, after **3 s** retry; up to **10** attempts, then intent = `DISCONNECT_AND_CLOSE` and re-arm visibility timer | same cleanup |

* `READY → anything else` while intent is CONNECT ⇒ "Unexpected pod disconnection!" event to analytics (`InterfaceC5894b.d`).
* Attempt 10 failing with GATT status 19 (remote user terminated) is reported separately (`InterfaceC5894b.a`).
* `connectGatt(context, autoConnect = false, cb)`. Sleeps 400 ms after `close()` and after `connectGatt()`.
* Disconnect: `disconnect()`, sleep 50 ms, `close()`.

### GATT operation queue (`je/C8071q`, `je/HandlerC8067m`)
Strictly one operation in flight. Next op starts on `onCharacteristicRead/Write` or `onDescriptorWrite`. Each op has a
**3003 ms** timeout, after which it is dropped and the queue advances. Messages: 1 CONNECT, 2 DISCOVER, 3 DISCONNECT_AND_CLOSE,
5 DESTROY, 6 QUEUE, 7 OP_COMPLETED, 8 CANCEL_OP.

## 5. Authentication handshake (`je/e0`, READY branch)

Sent first after READY, only for pods that advertised manufacturer data. Written to NUS RX:

```
"sea" (0x73 0x65 0x61) + R[0..3]
```

```
poly = 0xEDB88321 + (version % 50)          // version is a signed byte, Java remainder
crc  = 0xFFFFFFFF
for b in key[0..3]:
    crc ^= b
    repeat 8: crc = (crc >>> 1) ^ (crc & 1 ? poly : 0)
h = ~crc
h += h << 3 ; h ^= h >>> 11 ; h += h << 15  // 32-bit wrap
R = little-endian bytes of h
```

i.e. a reflected CRC-32 with a per-pod perturbed polynomial, followed by a Jenkins one-at-a-time final mix. The pod answers
`rsea=<u16>` on NUS TX (only logged by the app). `tools/AuthReference.java` is a literal port of the decompiled arithmetic
and generates the Swift test vectors.

## 6. Bring-up sequence after READY

1. NUS write `sea…` (if secure pod)
2. Enable notify: Battery `2A19`, Touch `50C9727E`, NUS TX `6E400003`
3. Read battery `2A19`
4. +500 ms: read model `2A24`, firmware `2A26`, serial `2A25` (serial only if `180A` exists) → "Connected to Pod" log/analytics

## 7. LED control (`zp/C13422f`, `yp/EnumC13047k`)

Write to `50C912A2`: **`[G, B, R]`** or **`[G, B, R, 0x01]`** – channel order is green, blue, red; values 0-100.
The 4th byte = "turn off when hit"; only used when firmware ≥ 3.2 (`je.i.i0`). Off = `[0,0,0]`.

| Colour | MAX (R,G,B) | MEDIUM | LOW |
|---|---|---|---|
| RED | 100,0,0 | 35,0,0 | 7,0,0 |
| ORANGE | 100,15,0 | 35,5,0 | 11,2,0 |
| YELLOW | 100,78,0 | 35,27,0 | 7,5,0 |
| GREEN | 0,100,0 | 0,35,0 | 0,7,0 |
| LIGHT_BLUE | 0,100,100 | 0,35,35 | 0,7,7 |
| BLUE | 0,0,100 | 0,0,35 | 0,0,7 |
| PURPLE | 27,0,47 | 16,0,27 | 5,0,9 |
| PINK | 100,0,39 | 35,0,15 | 7,0,3 |

* Intensity is a global setting (`p0.e`, default MAX), synced with the server user setting (`"high"|"medium"|"low"`).
* Default colour BLUE. Auto-assignment order: BLUE, RED, GREEN, PINK, LIGHT_BLUE, ORANGE, YELLOW, PURPLE. RANDOM is resolved
  in the app before sending.
* **Firmware glitch workaround** (`je.i.g` / `je.i.k`): if the previous and new colours are both primaries (R/G/B), differ,
  and the light was switched off < 50 ms ago, the colour is re-sent after 30 ms (max 2×) while still ON with that colour.
* Light API on the pod model: `h0(color)` on, `i0(color, offOnHit)`, `k0(color, ms)` on with auto-off timer, `V()` off.

## 8. Touch / hit events (`je/C8071q.onCharacteristicChanged`, `je.i.l`)

Notify on `50C9727E`, firmware ≥ 3.2:

| Byte | Meaning |
|---|---|
| 0 bits 0-1 | detection: 0 INTERRUPT, 1 POLLING |
| 0 bit 2 | pod turned its light off (NO/YES) |
| 1-4 | UInt32 LE – reaction time measured by pod (ms) |

Firmware < 3.2: payload ignored, hit timed by the phone's stopwatch (started when the light is turned on).

**Hit filter** (phone stopwatch `t`, pod time `p`):
1. light ON, mode INTERRUPT/legacy, `t < 250 ms` → ignore (debounce)
2. light ON, lightOff = NO, POLLING, `p < 200` → ignore
3. offOnHit mode, lightOff = NO, `t < 1000` → ignore
4. POLLING while light OFF → ignore
5. `p > 0 && p > t` → ignore (stale)
6. else **hit** with `reaction = p > 0 ? p : t`; if lightOff = YES mark light OFF locally.

Hits go to `je/b0` (msg 3) and are fanned out to every registered `je/c0` listener (the workout engines in `fe/`, `kp/`).

## 9. Nordic UART commands

| Direction | Payload | Meaning |
|---|---|---|
| → pod | `sea` + 4 B | auth response |
| → pod | `chgs` | charger status poll (every 300 ms while the facade's poller runs, secure pods only) |
| → pod | `tp7` then `xrs` | **shut down pod** (after blinking red 3×, 100 ms on / 200 ms off); pod removed from registry 100 ms later |
| ← pod | `chgs=` + u16 LE @5 | 0 no charger, 1 power/not charging, 2 charging, 3 fully charged, 4 power/no battery |
| ← pod | `rsea=` + u16 | auth result (logged) |
| ← pod | `disf=` + u16 | disconnect/fault reason (posted as event `ke/C8400j` → analytics) |

`tp7`/`xrs` semantics beyond "shutdown" are **[inferred]** from the UI string `pod_confirm_shut_down_*`.

## 10. Device info semantics

* Firmware `2A26` = `"<app>/<bootloader>"`; app part ≥ **3.2** unlocks touch payload + off-on-hit.
* Model `2A24`: `"PodPapa"` → `POD_V1`, `"PodMama"` → `POD_V2` (spaces removed, case-insensitive).
* Battery notifications of 0 are ignored.

## 11. Open questions / validation plan

* Validate the auth and LED byte order on real traffic: enable *Developer options → Bluetooth HCI snoop log*, connect pods in
  the app, then `adb bugreport` and open `btsnoop_hci.log` in Wireshark (filter `btatt`).
* `50C912CF` light-end notifications and `50C912CD` are never used by this app version.
* Exact meaning of `tp7`, `rsea`/`disf` codes not determined.
* iOS: no MAC address → DFU "MAC + 1" mapping cannot be reproduced; use peripheral identifier + serial instead.
