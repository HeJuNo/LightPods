# Drill engines

Step 2 of the analysis: how the original app (Android 6.0.1) runs its trainings ("activities"), and how LightPods
reproduces them in `BlazePodDrills`.

## Where the drills come from

Named drills such as *Color Catch*, *Plank Focus Challenge* or *Fast Feet* are **not in the APK**. They are
downloaded from BlazePod's server. Each one is an *engine* plus a set of *settings*, rendered from a
generic settings schema that ships in the app (`assets/EngineSettings-V2.json`). The training hub on
blazepod.com lists the public setup for each drill (all three: 1 player, 4 pods, 30 s).

| Engine (`fe.e`) | Model | Runtime | LightPods |
|---|---|---|---|
| `random` | `he.f` | `g8.l` | ✅ `RandomStation` |
| `focus` (+ `homeBase` variation) | `he.c` / `he.d` | `g8.d` | ✅ `FocusStation` |
| `allAtOnce` | `he.a` / `he.b` | `g8.a` | – |
| `homeBase` | `he.e` | `g8.h` | – |
| `sequence` | `he.g` / `he.h` | `g8.n` | – |

Shared base runtime: `kp.m` (cycles, timers, pod-disconnect handling). Event model: `fe.h` (HIT, TIMEOUT, MISS, STRIKE).

## Settings (`EngineSettings-V2.json`)

| Setting | Key | Range / values | Engines |
|---|---|---|---|
| Stations | `stations` | 1–20 | all |
| Pods (per station) | `pods` | 1–24 (focus 3–24) | all |
| Players (per station) | `players` | 1–24 | random |
| Colours per player | `colorsPerPlayer` | 1–7 | random, focus |
| Competition mode | `competitionMode` | regular, firstToHit | random |
| Lights out | `lightsOutType` | hit, timeout, hitOrTimeout (focus: hit, hitOrTimeout) | random, focus |
| Lights out time | `lightsOut` | 0.5–10 s, step 0.25 | |
| Light delay | `lightDelayTimeType` | none, fixed (0.5–10 s), random (from 0.5–9.5 / to 1–10 s, step 0.5) | random, focus |
| Duration | `activityLengthType` | time (10–3600 s, step 5), hitCount (1–100), timeOrHitCount | random, focus |
| Cycles | `cycles` | 1–20 | all |
| Rest between cycles | `delayCycles` | 5–60 s, step 5 | all |
| Distracting pods | `distractingPods` | 1–24, fewer than pods | focus |
| Distracting colours | `distractingColorsCount` | 1–7 | focus |
| Strike out | `strikeOutType` / `strikeOut` | no / yes, 1–100 | focus |

Pods are assigned to stations in connection order: station *s* gets pods `s·n … s·n+n−1` (`ee.a`).

## Random engine (`g8.l`)

* **Regular:** every player gets a different random pod in one of their colours. With *lights out = hit* the
  pod turns itself off on touch (4th LED byte); a timeout counts as *timeout* (`timeout` mode) or *miss*
  (`hitOrTimeout`). After a hit or timeout the player's pod goes dark for the light delay (none = 10 ms), then
  a free random pod lights up. With no delay the same pod never comes twice in a row.
* **First to hit:** all players are lit at once (off-on-hit disabled). The first hit scores, everybody
  else gets a miss, all pods go dark, delay, next round.
* Hits only count when lights out includes *hit*.

## Focus engine (`g8.d`)

One target pod in the player's colour (never the same pod twice in a row) plus *N* distracting pods, each in
a random distracting colour. Hitting the target scores, then all pods go dark for the delay. Hitting a
distracting pod is a *strike*; the pod stays lit. With strike-out enabled, the cycle ends when the limit is
reached. Off-on-hit is never used.

## Cycles and timing (`kp.m`)

* Time-based cycles end after the duration. A *5 seconds left* event fires for cycles longer than 6 s.
* Hit-count cycles end when a player reaches the count.
* Between cycles: rest of `delayCycles` seconds, with a countdown in the last 3 s (the original whistles 3.3 s before).
* A disconnecting pod ends the activity in the original. LightPods shows a warning and continues.

## Differences in LightPods

* Stations run in step: a station that reaches its hit count waits for the others before the shared rest. In the original, each station counts cycles independently.
* *Color Catch* is modelled as a Random drill with one colour per player (the public "Color Catch
  Competition" variants are multi-player colour duels). *Plank Focus Challenge* is a Focus drill with
  1 distracting pod. *Fast Feet* is a Random drill on 4 pods in a line. The server-side settings of these
  drills could not be read, so these presets are best guesses and can be changed.
