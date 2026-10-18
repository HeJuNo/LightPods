# Hidden flags, state & key routines (BLE layer)

## Runtime flags in `je/p0` (PodManager)

| Field | Meaning |
|---|---|
| `g` (AtomicBoolean) | manager created (`m36237b`) |
| `h` | pod scan running |
| `i` | bootloader (DFU) scan running |
| `j` | "continuous scan" mode – when false, a scan started by `u(ms)` stops itself after `ms` |
| `k` | manager started (cleared by `C()` stop-all) |
| `l` | use service-UUID scan filter (false on Galaxy S6 models) |
| `d` | DFU scanning requested by update screen |
| `b` | **workout running** – suppresses background disconnect and `E()` lights-off |
| `e` | global light intensity (default MAX) |
| `f` | **max connected pods** (−1 = unlimited) |
| `A` | consecutive scan failures (3 → stop + "please restart bluetooth" event; otherwise retry in 3 s) |

## Membership gate on pods
`w8/C12168n.m51268Z` reads `BPMembershipUserPlan.blockedFeatures["CONNECT_PODS"]` and calls
`AbstractC5893a.m26422d(limit)` / `m26421c()` (unlimited). Setting a limit immediately disconnects surplus pods, preferring
ones that are not yet linked. `je.i.q()` refuses new connections once the limit is reached → UI shows "pods limit reached".
This is a pure client-side check.

## Lifecycle
* Process `ON_START`: cancel disconnect job, start scanning.
* `ON_STOP` (no workout running): stop scans, schedule `DisconnectJobService` in **15 min** → disconnect everything.
* Workout events (`ke/C8403m`): 0 = started (cancel job, `b=true`), 3 = ended (re-arm 15 min job if backgrounded), 5 = resume
  scanning, 6 = stop scans and drop pods that are wanted but not READY.
* Task removed / crash events → full teardown (`j()`), sleeps 600 ms.
* BT adapter OFF → stop all; ON → restart. Location provider change → republish state (needed for scanning < Android 12).

## Persisted state (`SharedPreferences "com.blazepod.blazepodcore.PREFERENCE"`)
| Key | Type |
|---|---|
| `key_pod_names` | JSON `Map<Int podId, String name>` |
| `key_pod_names_index` | Int counter for `"Pod %03d"` |
| `key_connect_automatically_pods` | JSON `List<Int podId>` |
| `pod_last_connected_<podId>` | Long epoch ms |

## Published state (LiveData)
* `v`: summary `(readyCount, btAndPermissionsOk, anyUpdatePending, anyBootloaderPods)` (`ke/C8402l`)
* `w`: all visible pods sorted by name; `x`: READY pods; `y`: DFU pods; `z`: ready count.

## Key routines
| Routine | Location |
|---|---|
| Auth computation | `je/e0.handleMessage` (msg 1, READY) |
| Hit filter | `je/C8063i.m36186l` |
| Touch parse | `je/C8071q.onCharacteristicChanged` |
| LED write | `zp/C13422f.mo56372a` |
| Primary-colour resend | `je/C8063i.m36214g` / `m36185k` |
| Shutdown | `je/C8063i.m36216n` → `je/p0.m36246k` |
| Retry policy | `je/e0.handleMessage` msgs 1 (UNKNOWN) and 3 |
