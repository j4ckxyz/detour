# Detour: what the game does today

A snapshot of the playable build (updated 2026-09-28), for comparing against *RV There Yet?*.
Everything below is implemented and running unless it's in [Not in the game yet](#not-in-the-game-yet).
The long-term design is in [PLAN.md](PLAN.md).

**In one line:** a single-player sandbox where you walk around, climb into and drive a heavy
1970s motorhome (real clutch and gearbox) across endless procedurally generated pine hills,
and carry stuff about. There are no objectives, trips or other players yet.

---

## Controls

### On foot (keyboard and mouse)

| Key | Action |
|---|---|
| **W A S D** / arrows | Walk |
| **Shift** (hold) | Sprint |
| **Ctrl** (hold) | Crouch |
| **Space** | Jump |
| **Mouse** | Look |
| **E** | Interact with what you're looking at: open/close the door, sit in a seat (the driver's seat takes the wheel), pick up an item |
| **Left click** | Use the held item (e.g. eat a burger) |
| **Right click** | Throw the held item (inside the RV: put it down) |
| **Q** / **G** | Drop the held item (inside the RV it's stowed and rides along) |
| **R** | With the winch remote: switch between front and rear winch |
| **F** | Get up from a seat |
| **Esc** | Pause menu |

Walk through the open side door to get in or out; small ledges and rocks are stepped over.

### Driving (keyboard and mouse)

| Key | Action |
|---|---|
| **W** / **↑** | Throttle |
| **S** / **↓** | Brake. In automatic mode, holding it at a standstill selects reverse, and it then drives backwards |
| **A** / **D**, **←** / **→** | Steer |
| **Space** | Handbrake (rear wheels) |
| **Q** (hold) | Clutch pedal |
| **Q** + **move mouse** | Work the H-pattern gear stick (mouse must be captured) |
| **E** / **mouse wheel up** | Shift up one gear (dips the clutch for you if you aren't holding it) |
| **Z** / **mouse wheel down** | Shift down one gear (same clutch assist) |
| **1**–**5** | Go straight to that gear (clutch assist) |
| **R** | Reverse gear (clutch assist) |
| **T** | Switch manual ↔ automatic gearbox |
| **I** | Start the engine (needs the clutch down or neutral) |
| **L** | Headlights on/off |
| **C** | Switch chase camera ↔ cab (driver's-eye) camera |
| **Mouse** | Look around / orbit the chase camera (while the mouse is captured) |
| **Left click** | Capture the mouse |
| **Backspace** | Put the RV back on its wheels at the nearest clear, level spot |
| **Esc** | Pause menu (resume, update, auto-update toggle, quit); also releases the mouse |
| **F1** | Show/hide the controls help |
| **F3** | Show/hide the performance overlay |
| **F5** / **F6** / **F7** / **F8** | Graphics preset: potato / low / medium / high |

### Controller on foot

Left stick walk, right stick look, **A** jump, **L3** sprint, **R3** crouch, **X** interact,
**RT** use item, **LT** throw, **B** drop, **D-pad right** get up from a seat, **Start** menu.

### Controller driving (Xbox layout; other pads map to the same positions)

| Button | Action |
|---|---|
| **Right trigger** | Throttle |
| **Left trigger** | Brake (reverse in automatic, as above) |
| **Left stick** | Steer |
| **Right stick** | Look / orbit camera |
| **X** (hold) | Clutch |
| **RB** / **LB** | Shift up / down (with clutch assist) |
| **B** | Handbrake |
| **Y** | Start engine |
| **D-pad up** | Headlights |
| **D-pad down** | Manual ↔ automatic |
| **View / Back** | Chase ↔ cab camera |
| **Menu / Start** | Pause menu |
| **R3** (right stick click) | Back on the wheels |

The H-pattern stick is mouse-only for now; on a controller you shift sequentially.

### Debug scenes (developers)

- **Terrain benchmark** (`src/debug/terrain_bench.tscn`): **1**–**4** presets, **F3** overlay,
  hold **right mouse** + **WASD** to fly, **Q/E** down/up, **Shift** fast.
- **Drive tour** (`src/debug/drive_tour.tscn`): drives itself and saves screenshots.

---

## On foot

- **First-person player** with walking (4.2 m/s), sprinting (7 m/s), crouching and jumping; steps
  up ledges up to 40 cm; collides with the terrain, rocks, trees and the RV's hull.
- **Interaction**: a crosshair and an "E  …" prompt for whatever you're looking at within reach
  (doors, seats, items).
- **The RV's side door** opens and closes (animated). Walk through it to get in; walk out to
  leave. The shut door blocks the way.
- **Inside the RV** you walk around its real interior while it drives: the interior is its own
  physics space in the RV's frame, so it's rock-steady however the RV bounces. You feel it
  lean (gravity pulls you to the low side) and brake (you stumble forward a little).
- **Seats**: driver (takes the wheel and the driving cameras; the parking brake goes on when
  you get up at low speed), passenger and two dinette seats (look around from them).
- **Items**: pick up, carry (one at a time; big ones like planks, tires and jerry cans are
  held two-handed and dropped if you sit), drop, throw (heavier things go less far) and use.
  Put something down inside the RV and it stays where you put it and rides along.
  Items in the world: planks, jerry can, scrap metal, spare tire and motor oil by the RV at
  the start; winch remote, first-aid kit and two burgers inside. Burgers heal 30 (eat with
  left click); the other items' uses arrive with their systems (winch, repairs, fuel).
- **Health** is shown (100); nothing hurts you yet.

## Winches, planks and pushing

- **Two winches** (front and rear). At a winch, **E** takes the hook off the drum; carry it up
  to 40 m (the cable pays out as you walk; past 40 m it's yanked out of your hands). Look at a
  tree, rock, stump or log and **left click** to hook on. **E** on an anchored hook unhooks it;
  **E** at the drum while holding the hook puts it back.
- **Winch remote** (on the dashboard): hold **left click** to reel in, **right click** to pay
  out, **R** to pick front/rear. Works on foot or from a seat. The motor pulls up to 60 kN at
  0.5 m/s, slowing as the load rises; the rope only pulls when taut, sags when slack (drawn
  as a cable), and snaps if yanked far past its limit (e.g. driving away at full power).
  The HUD shows rope out and tension.
- **Planks**: while holding one, a green ghost shows where it would go; **left click** lays it
  along your view, resting on the ground at both ends (or continuing from the end of a plank
  you're looking at). A laid plank is solid ground: the RV's wheels and players ride on it.
  **E** picks it back up.
- **Pushing**: walk into the RV to push it (3 kN per person, fading out by a brisk walk).

## The world

### Generation
- **Seed codes** like `DT1-81YPW-3A7TA`: generator version, trip length and a 40-bit seed in
  Crockford base32, with a typo check. The default seed is fixed; `-- --seed=CODE` picks another.
- **Deterministic everywhere**: the same seed builds bit-identical terrain, trees and props on
  macOS (Apple Silicon), Linux and Windows (x86_64). CI checks this on every push with golden
  hashes. This is the foundation for multiplayer (only the seed needs sending).
- **One placeholder biome, "pine hills"**, which goes on forever in every direction:
  rolling hills from domain-warped noise, ridged mountain ranges in some regions, and small
  bumps. Heights 0–1310 m in 2 cm steps.
- **Ground colours** blend lush grass, dry grass, dirt, bare rock on steep slopes and snow
  above ~330 m. The treeline is at 320 m.

### Streaming
- 128 m × 128 m chunks with a 1 m height grid, generated on background threads around the RV.
- Level of detail: 1 m mesh spacing within 200 m, then 2 m, 4 m and 8 m further out.
- The main thread spends at most ~2 ms per frame adding new chunks, so streaming doesn't stutter.
- Fog hides the edge of the streamed area.

### Scenery (scattered by the generator, the same for everyone on a seed)
- **Pine forests**: density follows a forest-noise map; no trees on steep slopes or above the
  treeline. ~80 trees per chunk on average. Three pine models (8, 11, 14 m) near the camera;
  cheap cone stand-ins far away.
- **Rocks**: clusters of 2–5 rocks around a big one, with a 12 % chance of a boulder (2.4–3.8×
  size), plus lone rocks. More rocks on steep, rocky or high ground. 14 scanned rock models
  (CC0, Poly Haven).
- **Forest debris**: tree stumps, fallen logs lying along the slope, clumps of saplings.
- Props lean with the terrain, sit on the ground without floating, and never overlap a trunk.
  ~44 props per chunk.

### Physics of the world
- Within 256 m of the RV, the ground, tree trunks, rocks, stumps and logs are **solid**.
- Saplings aren't solid: the RV drives through them.

---

## The RV

### Model
- A 1970s-style class C motorhome, 7.4 m long, 2.4 m wide and 3.45 m tall, in cream with
  orange/brown/mustard stripes. Built procedurally in Blender (`tools/assets/blender/build_rv.py`).
- Exterior: an over-cab bunk, an awning, a roof AC unit and vent, a roof rack with **two spare
  tires**, a rear ladder, bumpers, a grille, and front and rear **winch drums**.
- Rear wheels are **dual**.
- **Full interior**:
  - Cab: two seats, a dashboard with three gauges, a steering wheel, the gear stick and the
    handbrake lever.
  - Living area: a dinette with table and benches, a kitchen counter with stove and sink,
    upper cabinets, a fridge, a wardrobe, a rear bed and the over-cab mattress.
- Animated parts: the steering wheel turns, the gear stick moves through the gate, and the
  wheels steer, spin and move with the suspension.
- The entry door, ladder, winch drums and spare tires are separate, but they aren't
  interactive yet.

### Handling
- **Mass** 5.5 t, with a high centre of mass (1.05 m), so it leans in corners and can tip on
  rough ground.
- **Suspension**:
  - Each wheel sphere-casts to the ground, so it rolls over edges instead of snagging.
  - 0.45 m of travel and soft springs (about 1 Hz, sized to the weight on each corner).
  - Bump stops, and anti-roll bars on both axles.
- **Tires**:
  - Grip limited by load, with a slip-angle curve (grip peaks around 7° of slip, then slides).
  - Braking, driving and cornering share one grip budget, so flooring it mid-corner makes the
    rear step out.
  - At a crawl the tires hold like static friction: a parked RV holds on a slope and doesn't
    creep.
- **Rear-wheel drive** with visible wheelspin when the tires break loose.
- **Steering**: 34° at a standstill, narrowing to 10° at ~100 km/h. Proper Ackermann geometry
  (the inner wheel turns tighter). Keyboard steering eases in and self-centres.
- **Brakes**: ~0.8 g total, biased 60 % to the front. The handbrake works on the rear.
- **Parking brake**: on automatically when the RV spawns or is reset; it releases when you
  touch the throttle.
- **Air drag and rolling resistance.**

### Engine and gearbox
- An old big-block V8:
  - Torque peaks at 520 N·m at 2400 rpm.
  - Idles at 750 rpm, with an idle governor.
  - Rev limiter at 3800 rpm.
  - Engine braking when you lift off.
- **Stalling**: dump the clutch at low revs, or let the revs fall below ~380 rpm in gear, and
  the engine dies. Press **I** with the clutch down (or in neutral) to crank it for 0.7 s.
- **Clutch**: an analog pedal. It presses in 0.12 s and lets out in 0.55 s, biting mid-travel.
  Slip it with some throttle to pull away smoothly.
- **Manual 5-speed + reverse**:

  | Gear | Top speed (at the rev limiter) |
  |---|---|
  | 1 | ~24 km/h |
  | 2 | ~42 km/h |
  | 3 | ~70 km/h |
  | 4 | ~100 km/h |
  | 5 | ~125 km/h in theory; drag limits it lower |
  | R | ~27 km/h |

- **H-pattern gate** (1-3-5 on top, 2-4-R on the bottom). The stick only slides sideways in
  the neutral lane and only enters a gear when lined up with it. It won't go into gear
  without the clutch; the HUD shows "GRIND" if you try.
- **Automatic mode** (T):
  - A self-engaging clutch that can't stall.
  - Shifts up at 2100–3400 rpm depending on throttle, and down below 1250 rpm.
  - Holds each gear at least 1.2 s and cuts the throttle during a shift.
  - Hold the brake at a standstill to engage reverse.

### Cameras and lights
- **Chase camera**: trails the RV's heading, can be orbited with the mouse or right stick, and
  pulls in if terrain or a rock gets between it and the RV.
- **Cab camera**: sits at the driver's eyes and can look about ±125° left/right.
- **Headlights**: two spot lights (70 m reach) that cast shadows on the high preset.

### Spawning and recovery
- At the start, the game looks for a level spot near the world origin that is clear of rocks
  and trees, facing open ground.
- **Backspace** does the same within 60 m of wherever you are, as a stand-in for the planned
  tow truck.

---

## Interface

- **Driving HUD** (bottom left):
  - Speed, gear and rpm (red near the limiter).
  - Manual/auto, clutch %, handbrake and lights indicators.
  - Warnings for stalled, cranking and grinding.
- **H-pattern diagram** (bottom right) appears while the clutch is down, with a dot where the
  stick is.
- **Controls help** (top, F1) and a **performance overlay** (F3: fps, frame times, streaming
  stats).
- **Pause menu** (Esc / Start):
  - Pauses the game and shows the version.
  - Buttons: **Resume**, **Update now** (becomes **Restart to update**), **Update
    automatically** (on by default, remembered) and **Quit to desktop**.
  - A progress bar and status line appear while an update downloads.

## Updates

Downloaded builds keep themselves current from this repo's GitHub releases:

- **When they check:**
  - Nightly builds follow the `nightly` pre-release; tagged builds follow the latest stable
    release.
  - With auto-update on, the game checks 3 seconds after launch.
  - **Update now** checks on demand.
- **What happens when there's a newer build:**
  1. It downloads in the background (including while paused).
  2. It is checked against the release's SHA-256 checksums.
  3. It is swapped in place, so even if you just quit, the next launch runs the new version.
     A small notice says so, and **Restart to update** starts it right away.
- **How each platform is replaced:**
  - **macOS**: the `.app` bundle.
  - **Linux**: the AppImage file, or the files from the tarball.
  - **Windows**: the files in the install folder. If that folder isn't writable (an
    all-users install), the installer runs silently on restart instead.
- **When updates are off:**
  - Builds run from source or the editor never update themselves.
  - On macOS, an app still in Downloads (App Translocation) asks to be moved to
    Applications first.

## Graphics and performance

- **Presets** (auto-detected, switch with F5–F8):

  | Preset | View distance | Trees drawn to | Props drawn to | Notes |
  |---|---|---|---|---|
  | Potato | 380 m | 160 m | 100 m | |
  | Low | 560 m | 260 m | 150 m | |
  | Medium | 900 m | 450 m | 250 m | |
  | High | 1400 m | 700 m | 350 m | 4-split soft shadows, SSAO (Forward+ only) |

  Each preset also sets the render scale, the upscaler (MetalFX on Macs, FSR elsewhere) and
  shadow quality.
- **Renderers**: macOS uses Godot's Mobile renderer (measured ~2× faster on Apple GPUs);
  other platforms use Forward+. The OpenGL "Compatibility" renderer works for weak GPUs.
- **Smooth motion**: physics runs at 60 Hz and is interpolated for 120 Hz displays.
- **Measured** on the entry-level Apple A18 Pro Mac at 2560×1600, high preset: 104 fps average,
  worst 1 % of frames under 12.6 ms, no hitches (see `docs/perf.md`).

## Platforms and downloads

- **Windows 10/11**: installer or portable zip.
- **macOS 11+**: a universal app for Apple Silicon and Intel.
- **Linux / Steam Deck**: AppImage or tarball.
- Built by GitHub Actions on every push. All builds are unsigned, so first launch needs the
  usual "open anyway" step (see README).
- Command-line options: `-- --seed=CODE`, `-- --preset=potato|low|medium|high`, `-- --automatic`.

## Behind the scenes (built, but not used in gameplay yet)

- **Online relay server** (`server/relay`, Rust): rooms with 6-character codes, the host as
  peer 1, rate limits and a password option. It runs on a Raspberry Pi. An in-game network
  peer for it passes an end-to-end test, but there is no lobby, room-code screen or player
  replication yet, so **the game is single-player only**.
- **3D models already made** for future items: jerry can, oil bottle, spare tire, scrap metal,
  plank, burger, antidote, EpiPen, bear spray, first-aid kit and winch remote.

---

## Not in the game yet

Planned (see PLAN.md), roughly in the order they're coming:

- **Players**: the roof ladder and roof, a visible body (for co-op), a hotbar/inventory.
- **The trip**:
  - A start camp, roads you can see, gas-station checkpoints (refuel, repair, restock,
    revive, save) and home at the end.
  - Trip length choice; a paper map for navigation.
- **Obstacles you solve** (the winch, planks and pushing work already; the obstacles don't
  exist yet):
  - Gaps to bridge, ledges to winch up, fords, mud, rockslides, cliffs and steps, lava, ice.
  - A generator that guarantees every obstacle can be solved, with difficulty rising along
    the trip.
- **Damage and upkeep**:
  - Flat tires and spare-tire swaps.
  - Engine oil leaks and overheating.
  - Body damage patched with scrap metal (welded at stations), parts falling off, and hammer
    repairs.
  - Fuel use and jerry cans.
- **Danger**: health, burgers, snake venom and antidote, downed players revived with an
  EpiPen; bears (bear spray), snakes and eagles.
- **World variety**: more biomes (red rock canyon, swamp, alpine, volcanic), rivers and lakes,
  weather, day/night.
- **Co-op**: up to 4 players online through the relay, LAN or direct IP; proximity voice chat.
- **Sound**: engine, horn, tires, ambience, music. The game is currently **silent**.
- **Menus and options**: a main menu, settings (key rebinding, graphics, audio), cosmetics,
  and the diegetic dashboard gauges.
