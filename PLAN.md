# PLAN.md — Cross-platform co-op RV road-trip game

> Working title: **Detour**. This is a from-scratch, open-source game built on the *RV There Yet?*
> formula (Nuggets Entertainment, 2025): up to 4 friends, one fragile RV, a long drive home.
> We keep the same core loop, add **procedurally generated 3D maps**, and build it to run well on
> low-end Windows PCs, Macs and Linux / Steam Deck. It will be distributed on **GitHub**, and online
> play goes through a **tiny self-hosted relay server** that can run on a Raspberry Pi.

---

## Decisions log

| Date | Decision |
|---|---|
| 2026-09-28 | Engine: **Godot 4.7.x** (4.7.2 pinned). Languages: typed GDScript plus Rust (GDExtension via `godot` crate 0.5.x). |
| 2026-09-28 | Art direction: **cozy, stylized semi-realistic** (close to the original's vibe), built on a shared palette atlas + vertex colours. |
| 2026-09-28 | Player cap: **4**, like the original. |
| 2026-09-28 | Distribution: **GitHub Releases**, with no Steam dependency. Online play uses a **self-hosted relay** (Rust, runs on the Pi or the OptiPlex, no GPU). LAN and direct-IP play also work with no server. |
| 2026-09-28 | **Apple Silicon macOS first.** Build, test and tune there; Windows/Linux builds and the CI matrix are deferred (the design stays cross-platform). |
| 2026-09-28 | macOS uses Godot's **Mobile renderer** (measured ~2× faster than Forward+ at 2560×1600 with the same look) and defaults to the **high** preset on Apple Silicon. See `docs/perf.md`. |

---

## 0. Ground rules

- **Copy the design, not the property.** Game mechanics can't be owned, but the name "RV There Yet?",
  its logo, art, audio, characters, text and map ("Mabutts Valley") are Nuggets Entertainment's.
  Everything we ship is original. Because the repo will be public, **don't name the GitHub repo or
  the game after the original**; see Open questions.
- **Platforms:** Windows 10/11, macOS (Apple Silicon + Intel), Linux (incl. Steam Deck as a non-Steam
  game). One codebase, with a separately tuned build per OS (§9).
- **Performance is a feature.** The original runs on Unreal Engine 5 + Lumen, lists a GTX 970 as its
  minimum, and gets 5–15 fps on Intel iGPUs. Our target is **60 fps on Intel Iris Xe / Apple M1 /
  Steam Deck**, and 30+ fps on ~2015 integrated graphics.
- **The server is cheap by design.** The relay only routes packets and never simulates the world, so a
  Raspberry Pi can serve many rooms (§7).

---

## 1. What we're matching

These points come from the store page, reviews and the community wiki (see Sources).

| Original *RV There Yet?* | Detour |
|---|---|
| 1–4 player online co-op; solo playable | Same |
| One RV, rear-wheel drive, manual 5-speed: hold clutch (Q), drag the mouse to shift | Same, plus an optional automatic gearbox and controller H-pattern/sequential shifting |
| Physics winch on front and rear, hooked to trees, rocks and cliffs, operated with a winch remote | Same |
| Players push and pull the RV and repair it | Same |
| Resources: fuel, engine oil, spare tires, scrap metal, planks (for bridges) | Same |
| Gas stations are checkpoints (12 of them): refuel, weld/repair, restock, revive, save | Same; the number depends on the trip length |
| Hazards: steep cliffs, rockslides, rivers, lava pits | Same, plus mud, ice, weather and night |
| Wildlife: bears (bear spray), snakes (antidote), eagles | Same, with tunable aggression |
| Burgers heal; downed players are revived with an EpiPen | Same |
| Navigation uses a physical paper map, with no HUD markers | Same; a map is generated for each seed |
| Proximity voice chat is central to play | Same, plus muffling between the RV's inside and outside |
| Stylized, semi-realistic "cozy dad-core" look with chunky characters in goofy hats | Our own take on the same vibe |
| One handcrafted map, 5 zones, ~7 h | **Procedural trips**: you choose the length and seed; 5 biome types |
| Steam lobbies and Steam voice | A self-hosted relay with room codes, plus LAN / direct IP |

**Complaints about the original that we fix:** no key remapping and weak controller support at launch;
physics glitches that fling characters; unreliable voice chat; CPU physics stutter; VRAM stutter on
4 GB cards; wildlife that is too aggressive (we add a difficulty option for this).

---

## 2. Tech stack

### Engine: Godot 4.7 (pinned to 4.7.2)

Why Godot:
- It exports natively to Windows, macOS and Linux from one project, with the **native graphics API
  on each OS**: Direct3D 12 (the Windows default since 4.6), Metal on Apple Silicon (with MetalFX
  upscaling), and Vulkan on Linux and Intel Macs (via MoltenVK). An OpenGL 3.3 **Compatibility**
  renderer serves as a fallback for old or weak GPUs.
- **Jolt physics** has been the default since 4.6: it is fast and stable, which suits the vehicle and
  the physical chaos.
- It has built-in multiplayer (`MultiplayerPeer`, RPCs, ENet), and `MultiplayerPeerExtension` lets us
  plug in our own relay transport without changing any gameplay code.
- It has a **headless mode** with no GPU, which a dedicated host on the OptiPlex needs (§7.3).
- It is MIT licensed, so it is fine for an open-source repo, and builds are small (~100 MB). We can
  **compile our own stripped, speed-optimised export templates** for each platform.

Alternatives considered:
- **Unreal 5** is what the original uses. It is heavy on low-end hardware, produces large builds and is
  slow to iterate with, which is exactly the weakness we want to beat.
- **Unity 6** is a closed engine, which is awkward for an open-source project, and it is heavier.
- **Bevy** has no editor, and we would have to assemble physics, netcode and voice ourselves, adding
  months of work.
- **A custom engine** would take years.

### Languages

| Language | Used for | Why |
|---|---|---|
| **Typed GDScript** | Gameplay, UI, netcode glue | Fastest iteration. Static typing is enforced (the `untyped_declaration` warning is treated as an error). |
| **Rust** via [godot-rust](https://godot-rust.github.io/) (`godot` crate, GDExtension) | World generation, terrain meshing and LOD, scatter, roads, paper map, Opus voice codec, and any hot path that profiling flags | **Deterministic floats across CPUs**: Rust never auto-fuses FMA and has no fast-math, so the same code gives bit-identical results on x86_64 and ARM64. That lets every client build the same map from a seed. |
| **Rust** (standalone binary) | **Relay server** (`server/relay`) | A single static binary of a few MB and under 30 MB of RAM. It cross-compiles for the Pi (aarch64) and the OptiPlex (x86_64). |
| Python / shell | Build, export and release tooling | — |

We don't use C#: it would add the .NET runtime and GC hitches for no gain here.

### Libraries (pinned in `Cargo.lock` and `game/addons/`)
- **`godot` 0.5.x** (godot-rust): Rust GDExtension bindings.
- **`rusty_enet`**: ENet 1.3.18 transpiled to pure Rust, used in the relay. Godot bundles ENet 1.3.x,
  so the wire formats should match; the Phase 0 spike proves it. With no C dependency, it
  cross-compiles trivially.
- **Opus** (via the `opus` / `audiopus` crate, built statically) for voice.
- **GdUnit4** for tests; **gdtoolkit** (`gdlint`, `gdformat`) for linting and formatting.
- **Blender** for assets (already installed).
- Crash reports: local log plus a "Copy debug info" button. An optional Sentry DSN can be set at build
  time, and it is off by default.

---

## 3. Repo layout

```
detour/                          # public GitHub repo (name TBD; not "rvthereyet")
├── PLAN.md
├── README.md                    # install, "unsigned app" instructions, hosting a relay
├── game/                        # Godot 4.7 project
│   ├── project.godot
│   ├── export_presets.cfg
│   ├── addons/                  # gdUnit4
│   ├── bin/                     # built GDExtension libs (gitignored) + rvcore.gdextension
│   ├── src/
│   │   ├── autoload/            # Game, Net, Settings, SaveSystem, AudioDirector
│   │   ├── net/                 # relay_peer, transports, snapshots, replication, ownership, voice
│   │   ├── world/               # chunk streamer, LOD, scatter, water, weather, day/night
│   │   ├── setpieces/           # SetPiece base class + authored .tscn per biome
│   │   ├── rv/                  # rv, wheel, drivetrain, gearbox, winch, damage, interior_space
│   │   ├── player/              # controller, interaction, inventory, health, ragdoll
│   │   ├── items/
│   │   ├── wildlife/
│   │   └── ui/                  # menus, room codes, settings, paper-map view, minimal HUD
│   ├── assets/                  # models (.glb), textures, audio, shaders
│   └── tests/                   # GdUnit4
├── native/                      # Rust workspace for the game
│   ├── rvgen/                   # pure deterministic world gen (no Godot dependency)
│   ├── rvcore/                  # GDExtension: exposes rvgen, mesher, packers, Opus
│   └── rvgen-cli/               # headless: seed → PNG heightmap / paper map, hashes
├── server/
│   └── relay/                   # Rust relay server + Dockerfile + systemd unit
├── tools/                       # build_native.py, export.py, release helpers
├── art-src/                     # .blend sources (Git LFS)
└── .github/workflows/
```

Host and simulation logic is kept separate from presentation, so the same game build can run
**headless** as a CI bot or as a dedicated host on the OptiPlex.

---

## 4. Game design

### 4.1 Core loop
Start at a lakeside campsite and study the paper map. Drive until you hit an obstacle, and solve it as
a team (winch, push, lay planks, repair). Reach the next gas station, which is a checkpoint: save,
refuel, repair, revive and restock there. Continue into the next segment and biome, and eventually
arrive **home**. The trip ends with a summary: time, distance, flips, bear incidents and deaths.

### 4.2 The RV
- **Body:** a class-C motorhome of ~5.5 t, rear-wheel drive, with a high centre of mass so it *can*
  tip. The interior has a cab, table, kitchen, bed, bathroom, storage lockers, and a roof ladder with a
  roof rack.
- **Physics:** a Jolt `RigidBody3D` with a **custom wheel model**. Each wheel uses a sphere shape-cast
  (so it doesn't snag on terrain edges), spring/damper suspension and slip-curve tire friction, plus
  anti-roll bars and drag. Grip depends on the surface: asphalt 1.0, gravel 0.8, dirt 0.7, mud 0.4,
  snow/ice 0.35, and wet surfaces ×0.85.
- **Drivetrain:** a torque curve, gears 1–5 plus R and N, and a clutch (key or analog). The engine
  **stalls** if you dump the clutch at low rpm. The gear stick is a physical H-pattern in the cab,
  dragged with the mouse while the clutch is held. Options: an automatic gearbox, and controller
  H-pattern or sequential shifting.
- **Cab controls:** throttle, brake, steering, handbrake, horn, headlights, wipers, and a radio (flavour).
- **Diegetic dashboard:** speed, rpm, fuel, oil warning, engine temperature and damage lights.
- **Damage model (per part):**
  - **Tires (4):** sharp impacts and rocks cause punctures. Fix one by swapping in a spare tire (the
    roof rack holds 2).
  - **Engine:** leaks oil over time and on hard hits. When it runs out of oil it overheats, loses power
    and dies. Engine oil fixes it.
  - **Frame/body ("skeleton"):** takes damage from collision impulses above a threshold. Scrap metal
    patches restore part of it; the **welder at gas stations** repairs it fully.
- **Fuel:** consumption scales with throttle and load. Jerry cans are found in the world; the pumps
  are at gas stations.
- **Winch** (one front, one rear):
  1. A player takes the hook from the drum and carries the cable out; it can extend up to ~40 m.
  2. They attach it to an *anchor*: any tagged tree, rock or stump, or the bolts on set-piece cliffs.
  3. Anyone holding the **Winch Remote** can reel in, reel out or lock the cable.
  - In the simulation the cable is a one-sided distance constraint, so it can go slack. It pulls with
    up to ~60 kN at ~0.5 m/s and **snaps** when badly overloaded.
  - The visual rope is a 24-segment verlet rope that sags when slack. It is visual only, so it has no
    physics cost.
- **Pushing:** hold Use against the RV to add about 3 kN per player at the contact point. This is a
  scripted force, not character mass. It fades out above 5 km/h.
- **Flip recovery:** you can roll the RV back over with the winch. If the team is hopelessly stuck, it
  can use the payphone or radio to **call a tow**: the RV goes back to the last checkpoint at a cost in
  time and resources. This means there are no hard soft-locks.

### 4.3 Players
- The view is first-person. Characters are chunky "dads" with customisable hats, shirts, moustaches and
  sunglasses, unlocked by finishing trips (tracked locally). There is no monetisation.
- **Movement:** walk, sprint (limited by stamina), crouch, jump, and climb the roof ladder. Players sit
  in seats: the driver's seat, the passenger seat and the rear bench.
- **Carrying:** held items use a small hotbar (4 slots). Heavy items (planks, tires, jerry cans) need
  two hands and slow you down. Items can be thrown.
- **Health:** 100 HP. Burgers heal. A snake bite applies poison damage over time until cured with an
  antidote. Falls, bears, lava/fire and deep water (drowning) also hurt.
- **Downed state:** at 0 HP a player is downed and can crawl, with a 60 s bleed-out timer. A teammate
  uses an **EpiPen** to revive them. If the timer runs out, the player spectates until the RV reaches
  the next gas station, then respawns there.
- **Ragdolls:** heavy knocks (bears, getting hit by the RV, falls) trigger a short 2 s ragdoll.

### 4.4 Items (* = our addition, not confirmed in the original)
| Item | Use | Where |
|---|---|---|
| Paper map | Route, stations and points of interest; hold up to read | Glovebox, always |
| Winch Remote | Reel the front or rear winch | In the RV; respawns at stations if lost |
| Engine oil | Top up the engine | Stations, loot |
| Spare tire | Replace a flat | Roof rack (2), stations |
| Scrap metal | Patch body damage | Wrecks, loot |
| Plank | Build bridge spans at gap sockets; lay over mud | Lumber piles near gaps, stations |
| Jerry can | Carries 20 L of fuel | Stations, wrecks |
| Burger | Heals 30 HP | Station diners, coolers |
| Antidote | Cures snake venom | Stations, first-aid boxes |
| EpiPen | Revives a downed player | Stations (rare), first-aid boxes |
| Bear spray | Cone spray that makes a bear flee | Stations, ranger huts |
| Flashlight* | Light at night | RV |

### 4.5 Hazards and wildlife
- **Terrain:** grades too steep to climb (winch needed), cliffs and drop-offs, switchbacks,
  **fords** (above 0.8 m the engine floods and stalls, and the current pushes the RV), mud bogs,
  **gaps** (planks needed), **rockslides** (triggered by the RV and blocking the road; winch or push
  the boulders clear), fallen trees, lava flows and heat zones (engine temperature rises), and ice
  that cracks.
- **Environment:** a day/night cycle (headlights matter) and weather (rain, fog and snow reduce grip
  and visibility).
- **Wildlife** is simulated only on the host. Each animal runs a small state machine
  (idle → wander → alert → chase/attack → flee), and far-away animals update less often. There is no
  navmesh; animals steer over the heightfield and use raycasts to avoid obstacles.
  - **Bear:** charges players and the RV and does heavy damage. Bear spray makes it flee; the horn
    scares it at close range*.
  - **Snake:** hides in tall grass. Its bite poisons you until you take an antidote.
  - **Eagle:** makes dive attacks on exposed cliff paths and may snatch a small held item*.
  - **Ambient animals** (deer, birds) are animated on the GPU and cost no AI time.

### 4.6 Checkpoints, saves and death
Each segment ends at a **gas station** with fuel pumps, a welding bench, limited free restock shelves,
a diner and a payphone. Arriving at a station:
- saves the game automatically on the host;
- respawns dead players;
- restocks supplies.

### 4.7 Lobby options (set by the host)
- **Trip length:** Short, Medium or Long (3, 6 or 12 stations).
- **Tuning:** wildlife aggression (Off / Chill / Normal / Wild), RV fragility, and fuel/oil consumption.
- **Collisions:** whether the RV can hit players.
- **Per player:** manual or automatic gearbox.

### 4.8 Solo play
Everything can be done by one player:
- The Winch Remote works from the driver's seat.
- A bridge gap can be finished by one person making several trips with planks.
- Pushing helps but is never *required*.

The generator's validation assumes a single player (§5.4). Solo play needs no server at all.

---

## 5. Procedural world generation

### 5.1 Trip structure
- A trip goes: start camp → N segments → home. Each segment is **0.8–1.6 km of road** and ends at a
  gas station.
- Expected play time: Short (3 stations) ~45–60 min, Medium (6) ~2–3 h, Long (12) ~6–8 h. Long relies
  on saves across sessions.
- **5 biomes:** Pine Forest, Red Rock Canyon, Riverlands/Swamp, Alpine Pass (snow) and Volcanic
  Badlands. There are also fixed bookends: the lakeside start camp and a suburban "home" finale.
- The seed chooses the biome order. Difficulty rises through the trip, each biome lasts 1–3 segments,
  and biomes blend over ~200 m.
- **Difficulty curve:** each segment gets a points budget that rises from 2 to 8, with a breather after
  each spike. Set-pieces spend those points.

### 5.2 Generation pipeline
Every step is a pure function of the seed, implemented in the `rvgen` Rust crate.
1. **Trip graph:** derive sub-seeds and pick the biome sequence, segment count and segment lengths.
2. **Route:** a meandering walk of control points that heads generally "home", smoothed into a
   spline. It keeps a minimum turn radius of 12 m and never crosses itself. It can include optional
   **branches**: a loot detour, or a fork offering a long easy road or a short hard one.
3. **Set-piece slots:** set-pieces are spaced at least 150 m apart and chosen by biome, budget and
   compatibility tags (§5.3).
4. **Corridor terrain:** land is generated only within **±600 m of the route**. Beyond that, a
   low-poly backdrop ring of distant mountains shows through the fog. The terrain height is a
   per-biome blend of:
   - domain-warped fBm noise;
   - ridged multifractal noise (mountains);
   - terracing (canyons);
   - a few fixed-count thermal-erosion passes on a coarse 4 m grid.
5. **Road carving:** the road follows a smoothed height profile with a maximum grade of about 12%;
   set-pieces break that limit on purpose. Cut and fill shape the shoulders and embankments. The
   surface type (asphalt, gravel, dirt or snowpack) drives tire grip.
6. **Set-piece stamps:** each set-piece's height delta is applied on top (cliff steps, gaps, fords).
7. **Water:** rivers cross the route at ford or bridge set-pieces, and lakes fill basins. Each body of
   water is a flat plane with a flow vector.
8. **Scatter:** trees, rocks, bushes and grass are placed per chunk with Poisson-disk sampling. Density
   depends on biome, slope, height and distance from the road. **Anchor guarantee:** in rough sections
   there is at least one winch-anchorable object within 30 m of every 60 m of road.
9. **Points of interest:** gas stations, wrecks, cabins, campsites and ranger huts with loot tables,
   lumber piles next to gaps, and first-aid boxes.
10. **Encounters:** wildlife regions, rockslide triggers, the weather schedule and the start time of
    day.
11. **Names and the paper map:** procedurally generated silly place names. The top-down map image is
    rendered in Rust and becomes a texture on the in-hand paper map.

### 5.3 Set-piece library (handcrafted pieces joined by procedural terrain)
- **Authoring:** each set-piece is a Godot scene with a `SetPiece` script, which defines:
  - its footprint and its entry/exit **road sockets**;
  - a heightfield stamp;
  - its props, winch anchors and loot;
  - its **required solutions** (`winch`, `planks`, `push`, `repair`);
  - its difficulty cost and biome tags.
- **Count:** 12 set-pieces for the MVP (2 biomes) and 40+ for 1.0.
- **Examples:**
  - Cliff step: winch up a 6 m ledge.
  - Washed-out bridge: a 4 m gap to span with planks.
  - River ford with a current.
  - Rockslide blocking the road.
  - Mud bog.
  - Hairpin descent beside a drop-off.
  - Scree slope.
  - Log bridge.
  - Lava causeway.
  - Frozen lake.
  - Collapsed tunnel.
  - Locked ranch gate.

### 5.4 Solvability validation
- **Static checks at generation time:**
  - road grades and turn radii are within limits;
  - the road has clearance;
  - winch set-pieces have at least 2 anchors within cable range;
  - the required items sit *before* their obstacle and can be reached;
  - no step assumes two players.

  If a segment fails, it is re-rolled locally with a derived sub-seed, and the result is still
  deterministic.
- **Bot drive (nightly CI):** headless Godot drives the route with scripted winch and plank behaviour,
  over 500 seeds for each trip length. Failures are logged with the seed and position.
- A curated list of **Featured Seeds**, all playtested, appears in the menu.

### 5.5 Determinism: only the seed goes over the network
- `rvgen` is pure Rust with no engine calls. It uses integer-hash lattice noise and the **`libm`
  crate** for any trig or exp functions, never the platform's libm. There is no fast-math, and the
  only FMA is explicit `mul_add`.
- Each subsystem has its own RNG (PCG32), seeded with `hash(seed, label, chunk)`. Nothing depends on
  `HashMap` iteration order or on how threads are scheduled.
- Heights are **quantised to u16 in 2 cm steps** (0–1310 m).
- **CI golden test:** fixed seeds are generated on windows-x64, macos-arm64, macos-x64 (cross-built),
  linux-x64 and linux-arm64, and the chunk hashes must match byte for byte.
- **Runtime safety net:** on join, the host sends a hash for each chunk. If a client's chunk doesn't
  match, the host streams that chunk's heights (zstd, ~10 KB) and the mismatch is logged as a bug.
- The `GEN_VERSION` number is bumped on any generator change. It is baked into seed codes and saves.

### 5.6 Chunks, streaming and LOD
- Units are metres with Y up. **Chunks are 128 m × 128 m** with heights every 1 m (129×129).
- Chunks are generated on worker threads, prioritised by distance to players and the RV and by the
  direction of travel. Budget: **under 4 ms per chunk** on one low-end core. The main thread only
  uploads results, time-sliced at **under 2 ms per frame**.
- **LOD rings:** 1 m spacing (<192 m), 2 m (<384 m), 4 m (<768 m) and 8 m beyond, with skirts to hide
  cracks.
- **Collision ring:** a `HeightMapShape3D` exists only within 256 m of any player or the RV on the
  host, or within 256 m of the local player on clients.
- **Props:** one `MultiMeshInstance3D` per chunk per material, with `visibility_range` fade and
  billboard impostors for distant trees. Anchorable props go into a spatial hash.
- An LRU chunk cache has a hard memory cap.
- **Load target:** the first playable area is ready in **under 3 s** on a 4-core CPU.

### 5.7 Seed codes
Seed codes look like `DT1-7KQ2-XM9P`. They encode the generator version, trip length, options and a
40-bit seed in Crockford base32. The menu offers Random, Enter Code and Featured.

---

## 6. Multiplayer and netcode

### 6.1 Topology
- **Logically, one player's game is the host**, and the host is always **Godot peer id 1**. Godot's
  high-level multiplayer (RPCs, authority, `multiplayer.is_server()`) therefore works unchanged,
  whatever the transport.
- **Transports**, which all present a Godot `MultiplayerPeer` so gameplay code never knows which is in
  use:
  1. **Relay (default for online play):** every player, host included, connects *outbound* to the
     self-hosted relay (§7). No one needs to forward ports except whoever runs the relay. Players join
     with a **6-character room code**.
  2. **LAN:** the host runs `ENetMultiplayerPeer` as a server and announces itself with a UDP
     broadcast beacon; players see it in a "LAN games" list.
  3. **Direct IP:** the same as LAN, typed as `host:port`, using UPnP port mapping through Godot's
     `UPNP` class when the router allows it.
- **Solo** uses an `OfflineMultiplayerPeer`, so there is no networking at all.

### 6.2 Authority model
Everyone in a session is a friend, so we favour responsiveness over cheat-proofing.

| Thing | Simulated by | Others see |
|---|---|---|
| Own character | Owning client | Interpolated (~100 ms buffer) |
| **RV** | **Current driver's client**, or the host when the seat is empty | Interpolated / extrapolated |
| Dynamic props near the RV (boulders, loose planks) | The RV's owner (ownership follows the RV) | Interpolated |
| Other props | Host | Interpolated |
| Wildlife | Host | Interpolated at a low rate |
| Game state (inventories, RV damage/fuel, checkpoints, loot taken, bridges built, saves) | Host | Reliable events |

- **Driving has no input lag**, because the driver's machine simulates the RV.
- The host decides ownership handoffs. The new owner starts from the last received state, and the old
  stream blends into the new one over ~150 ms.
- **Forces from other players** go to the RV's owner:
  - Pushers send *push intents* at 20 Hz.
  - Winch state is host state that is replicated to the owner, and the owner simulates the rope.
  - Bear hits reach the owner as impulse events.
- The host checks the game version and protocol version of each joining player and rejects any
  mismatch with a readable message.

### 6.3 Riding inside a moving RV (the hardest problem)
- **The problem:** characters standing on a moving, networked rigid body jitter, slide and get
  launched. This is a documented complaint about the original.
- **The solution: the RV interior gets its own physics space.**
  - A render-disabled `SubViewport` with `own_world_3d = true` (or `PhysicsServer3D.space_create()`)
    holds a **static copy of the interior collision** at the origin.
  - Characters and loose items inside simulate there, in **RV-local coordinates**. Their visuals are
    drawn at `rv.global_transform * local_transform`.
  - **Fake inertia:** the RV's filtered acceleration is applied inside as a force. Braking makes people
    stumble, and a big crash or flip throws them into a ragdoll. That is controllable and never a
    physics explosion.
  - **Doors** are trigger volumes. Passing through one moves the character between spaces, keeping
    their world pose and velocity.
  - **The roof** is part of the interior space too. If the tilt or acceleration gets too high, roof
    riders are thrown off into the world space.
- **Network:** characters inside the RV replicate `(space_id, local_transform)`, so passengers look
  perfectly smooth to everyone regardless of RV interpolation error.

### 6.4 Replication details
- Physics runs at **60 Hz** and **snapshots go out at 30 Hz**. The ENet channels are:
  - 0: control, reliable;
  - 1: game events, reliable and ordered;
  - 2: snapshots, unreliable and sequenced;
  - 3: voice, unreliable.
- High-frequency snapshots are **custom packed binary** (`PackedByteArray`), which avoids Godot's
  Variant encoding overhead:
  - positions are quantised relative to the chunk origin (~2 mm precision);
  - rotations use smallest-three encoding in 32 bits;
  - velocities are stored as half-floats;
  - RV and prop data are sent as a delta against the last acknowledged baseline.
- The interpolation buffer adapts between 60 and 150 ms, and extrapolation is capped at 250 ms. Clocks
  are synced with an NTP-style RTT exchange.
- **Security:** `SceneMultiplayer.allow_object_decoding` stays **false**, and every incoming packet
  is length-checked before it is parsed. That matters because players can point the game at anyone's
  relay.

### 6.5 Joining, saves and reconnects
- **Joining a game in progress:**
  1. The client receives the seed plus a **world delta list**: loot taken, bridges built, obstacles
     cleared, props broken, weather and time of day.
  2. It generates the world locally behind a loading screen.
  3. It spawns at the RV.
- Every generated entity has a **stable ID**, `hash(seed, chunk, index)`, so deltas stay tiny.
- **Saves** are made by the host at each station and on quit, stored in `user://saves/`. A save holds:
  - `GEN_VERSION`, the seed code and the lobby options;
  - the checkpoint index;
  - the RV state;
  - each player's inventory, health and cosmetics, keyed by a random **player UUID** generated on
    first launch;
  - the world delta list.

  Saves are plain files, so they can be copied between machines. A trip can be resumed with any subset
  of the original crew.
- **Disconnects:** a dropped player's character sits idle in the RV, and reconnecting with the same
  UUID restores it.
- **Host migration** is not in 1.0: if the host quits, the session ends and can be resumed from the
  autosave. Alternatively, run a dedicated host on the OptiPlex (§7.3).

### 6.6 Bandwidth budget (per client, 4 players)
| Stream | Size |
|---|---|
| RV state | ~50 B × 30 Hz ≈ 1.5 KB/s |
| 3 remote players | ~24 B × 30 Hz × 3 ≈ 2.2 KB/s |
| Props and wildlife | ≤ 2 KB/s |
| Voice | ~3 KB/s per active speaker |

That is about **15 KB/s down per client**. For the relay, see §7.2.

### 6.7 Testing the netcode
- Run several local instances from the editor ("Customize Run Instances"), plus a local relay binary.
- A **network conditioner is built into the transport layer** (latency, jitter, loss, duplication).
  OS tools also work: clumsy (Windows), Network Link Conditioner (macOS) and `tc netem` (Linux).
- **Nightly soak test in CI:** a relay, a host and 3 headless bot clients drive for 30 min at 150 ms
  latency and 2% loss. The test asserts that game-state hashes never diverge and no client disconnects.
- At each milestone, a cross-OS matrix covers every mix of Windows, Mac, Linux and Deck as host and
  clients, through the Pi relay.

---

## 7. Self-hosted server

### 7.1 Relay server (`server/relay`, Rust): the default
It is a **dumb, game-agnostic packet router**. It never parses game data or simulates anything, so it
needs no GPU, almost no CPU, and rarely has to be updated when the game changes.

- **Transport:** ENet over one UDP port (default **24650**), implemented with `rusty_enet`. It uses the
  same channels and reliability flags the clients send.
- **Protocol** (versioned by `RELAY_PROTO`):
  - `HELLO {relay_proto, action: CREATE|JOIN, room_code?, password?}` is the first reliable message on
    channel 0.
  - For `CREATE`, the relay generates a 6-character Crockford code, and the creator becomes
    **peer 1** (the host).
  - For `JOIN`, the relay assigns a random peer id (> 1), replies `WELCOME {peer_id, room_code,
    peers[]}`, and sends `PEER_JOINED` to everyone else in the room.
  - **Data:** a client sends `[target:i32][payload]` and the relay forwards `[source:i32][payload]`.
    Target 0 means everyone else, and `-n` means everyone except `n`, matching Godot's semantics.
  - When a player leaves, the relay sends `PEER_LEFT`. When the host leaves, the room closes with a
    reason (1.0).
- **Client side:** `RelayMultiplayerPeer` is a `MultiplayerPeerExtension` over Godot's `ENetConnection`.
  To `SceneMultiplayer` it looks like any other peer.
- **Limits** (configurable in `relay.toml` or env vars):
  - max rooms (default 32) and 4 players per room;
  - max packet size (1200 B unreliable, 64 KB reliable);
  - per-peer rate limit (default 300 packets/s and 64 KB/s);
  - a per-IP connection cap and a join-attempt limit (to stop room-code guessing);
  - idle and handshake timeouts;
  - an optional server password.
- **Observability:** structured logs to stdout, and an optional `/health` + `/metrics` HTTP endpoint
  bound to **localhost only** by default.

### 7.2 Hardware sizing
| Box | Role | Expected capacity |
|---|---|---|
| **Raspberry Pi** (4 or 5) | Relay only | CPU is not the limit (~2k packets/s per room is trivial). **Home upload bandwidth is the limit**: each full room uses ~0.6 Mbit/s up, so 20 Mbit/s of upload gives ~25 rooms. RAM under 30 MB. |
| **OptiPlex** | Relay, and/or a **dedicated host** (§7.3) | Relay: same as the Pi. Dedicated host: ~1 CPU core and ~1 GB RAM per active trip, headless with no GPU. |

The relay adds one network hop. Players at the same house as the relay get LAN-level latency; everyone
else gets their normal ping to that house.

### 7.3 Dedicated host mode (optional, Phase 7)
- The **same game build** runs with `--headless -- --dedicated --room <code|new> --save <file>`. It
  uses Godot's dummy renderer, so it needs no GPU.
- It joins the relay (or listens directly) as **peer 1** and runs the host logic: wildlife, props,
  saves, and the RV when nobody is driving.
- **Result:** an always-on trip that friends can drop into at any time, with no player needing to host.
- It is intended for the OptiPlex. The Pi 5 might manage one light trip; test before relying on it.

### 7.4 Deployment
- Releases include `detour-relay` binaries for `linux-x86_64` and `linux-aarch64`, and a
  **multi-arch Docker image** on GHCR (`linux/amd64` + `linux/arm64`).
- **Pi / OptiPlex setup:** use `docker compose up -d`, or the provided **systemd unit**, which runs as
  a non-root `detour` user with `ProtectSystem=strict`, `NoNewPrivileges` and a memory cap.
- **Networking:** forward **one UDP port** (24650) on the router to the relay box. Use a stable name
  (a dynamic DNS such as DuckDNS, or your own domain). Players enter `name:port` once in Settings,
  and it is remembered.
- **Security:** this exposes a service on your home network to the internet. The relay binary must:
  - run with no admin endpoints reachable from outside;
  - never execute or deserialise payloads;
  - apply the limits in §7.1;
  - run as an unprivileged user in its own container or systemd sandbox.

  Only that single UDP port is forwarded. For friends-only use, set a server password.
- **Privacy:** ENet traffic is not encrypted. Phase 7 adds **payload encryption between each client
  and the host** (X25519 key exchange + ChaCha20-Poly1305 in `rvcore`). The relay then only sees
  routing headers and ciphertext, including for voice.

---

## 8. Proximity voice chat

- **Pipeline:**
  1. Capture the microphone with `AudioEffectCapture`.
  2. Encode with **Opus** in `rvcore` at 20 ms frames and ~24 kbit/s.
  3. Send on the unreliable voice channel through the same transport.
  4. Decode on the receiver into an `AudioStreamGenerator` on an `AudioStreamPlayer3D` at the
     speaker's head.
- **Proximity rules:**
  - Outside the RV, volume falls off with distance and cuts out at ~40 m.
  - Inside the RV, everyone hears each other clearly.
  - Between inside and outside, voices get a ~1.2 kHz low-pass and −6 dB unless the door or window is
    open.
  - The engine noise ducks slightly under voices.
- **Options:** voice activity detection or push-to-talk, input device picker, per-player volume and
  mute, and a speaking indicator.
- A 60 ms jitter buffer is used, with Opus packet-loss concealment and FEC.
- **macOS:** the app needs `NSMicrophoneUsageDescription` in `Info.plist` for the permission prompt.

---

## 9. Rendering and performance

### 9.1 Targets
| Tier | Example hardware | Renderer | Output | Target |
|---|---|---|---|---|
| Potato | Intel HD 520/620, GT 730, older Intel Macs | Compatibility (GL 3.3) | 720p at 67% scale | 30+ fps |
| **Low** | **Iris Xe, Radeon 680M / Vega 8, Apple M1, Steam Deck** | Mobile | 1080p at 67–77% + FSR1 / MetalFX spatial (Deck: 800p) | **60 fps** (Deck 40–60) |
| Medium | GTX 1050 Ti / RX 570, M2/M3 | Forward+ (or Mobile on Apple, see §10) | 1080p + FSR2 / MetalFX temporal | 60 fps |
| High | GTX 1660 / RTX 2060+, M-series Pro/Max | Forward+ | 1440p–4K + upscaler | 60–144 fps |

- **Minimum CPU:** a 4-core from ~2015.
- **Minimum RAM:** 4 GB (8 GB to host).
- **Minimum VRAM:** 1 GB.
- **Download size:** under 1 GB.
- The renderer used for each tier is **confirmed by the Phase 0 benchmark, not assumed**.

### 9.2 The art style is part of the performance plan (cozy, stylized semi-realistic)
- **Look:** warm, soft-lit and slightly exaggerated proportions, with realistic-ish forms and
  materials but no photo textures.
- **Props:** most share **one palette texture (a 256² gradient atlas) plus vertex colours**, so they
  use one material, which makes batching and instancing effective. Hero assets (the RV, characters)
  get their own small texture sets.
- **Budgets:** characters ~5k triangles with a 512² texture. The RV has ~25k triangles outside and
  ~20k inside, with LODs.
- **Terrain:** a vertex-colour biome tint plus 3–4 tiled detail textures blended by slope and height.
  The Potato and Low tiers use vertex colours only.
- **Lighting:**
  - One sun/moon directional light with cascaded shadows.
  - Sky-based ambient light, with ambient occlusion baked into prop vertex colours.
  - **No real-time GI needed**, whereas the original relies on Lumen.
  - Headlights are 2 spot lights, which cast shadows on High only.
- **Vegetation:** wind is done in the vertex shader. Grass appears only near the camera, with density
  set by the preset.
- **Fog:** depth and height fog hides the streaming edge and sets the mood.

### 9.3 Quality presets
| Setting | Potato | Low | Medium | High |
|---|---|---|---|---|
| Renderer | Compatibility | Mobile | Forward+ | Forward+ |
| Render scale | 0.67 | 0.67–0.77 | 0.77–1.0 | 1.0 |
| Upscaler | Bilinear | FSR1 / MetalFX spatial | FSR2 / MetalFX temporal | FSR2 / MetalFX temporal or native TAA |
| View distance | 300 m | 500 m | 900 m | 1500 m |
| Shadows | 1 cascade, 30 m, 1k | 2 cascades, 60 m, 2k | 3 cascades, 120 m, 2k | 4 cascades, 200 m, 4k, soft |
| Grass | Off | 30 m, sparse | 60 m | 100 m, dense |
| Tree impostors beyond | 80 m | 150 m | 250 m | 400 m |
| SSAO | Off | Off | Half-res | Full |
| Volumetric fog | Off | Off | Off | On |
| Water | Flat colour | + normal maps | + depth fade | + SSR |
| AA | None | FXAA | From FSR2 | From FSR2 / TAA |

Changing the renderer requires a restart; the settings menu prompts for it.

### 9.4 CPU frame budget
Budget for 16.6 ms, with the host running 4 players on a 4-core CPU from 2015:

| System | Budget |
|---|---|
| Physics (Jolt: RV, characters, interior space, collision ring) | 3.0 ms |
| Gameplay GDScript | 2.0 ms |
| Networking (pack/unpack, interpolation) | 0.5 ms |
| Wildlife AI (update rate drops with distance) | 0.5 ms |
| Streaming uploads (time-sliced) | 1.5 ms |
| Render-thread submission | 5.0 ms |
| Headroom | 3.6 ms |

World generation, Opus and audio run on other threads. Rules for hot code:
- No per-frame allocations in hot GDScript.
- Pools for ropes, particles and decals.
- Far entities are disabled via `process_mode`.

**Profiling tools:** Godot's profiler, plus PIX / Superluminal on Windows, Instruments on macOS, and
`perf` / RenderDoc on Linux.

### 9.5 Memory
- **VRAM budget:** 1 GB on Low and 2.5 GB on High.
- **Textures:** S3TC/BPTC for x86 GPUs, and **ETC2/ASTC** imports so Apple Silicon uses ASTC natively.
- The chunk LRU cache has a hard cap.

### 9.6 Stutter
- **Shaders:** Godot 4.4+ has ubershaders and a pipeline cache. On top of that, a warm-up pass draws
  every material variant off-screen during loading.
- **Colliders:** chunk colliders are created in time slices.
- **Frame pacing:** VSync is on by default, with frame caps of 30/40/60/uncapped.

### 9.7 Auto-detection and dynamic resolution
- **First launch:** we read the GPU name, type and VRAM, CPU cores and RAM. These are checked against a
  lookup table, then a **5 s benchmark flythrough** on a fixed seed picks a preset. The player can
  override it.
- **Dynamic resolution (optional):** a controller adjusts `scaling_3d_scale` between 0.5 and 1.0 based
  on measured GPU frame time.
- **Driver fallback on startup failure:**
  - Windows: D3D12 → Vulkan → OpenGL.
  - Apple Silicon: Metal → OpenGL.
  - Linux and Intel Mac: Vulkan → OpenGL.

---

## 10. Per-platform optimisation and packaging

| | Windows | macOS | Linux / Steam Deck |
|---|---|---|---|
| CPU arch | x86_64 (ARM64 later) | **Universal 2** (arm64 + x86_64) | x86_64 + arm64 |
| Default graphics API | Direct3D 12 | **Metal** (Apple Silicon); Vulkan/MoltenVK (Intel) | Vulkan |
| Fallback | Vulkan → OpenGL 3.3 | OpenGL (Compatibility) | OpenGL 3.3 |
| Upscaler | FSR1 / FSR2 | **MetalFX** (Apple Silicon), FSR | FSR1 / FSR2 |
| Texture formats | S3TC/BPTC | S3TC/BPTC + ETC2/ASTC | S3TC/BPTC |
| Native build of `rvcore` | MSVC (PDBs) | clang + `lipo` → universal dylib | `cargo zigbuild` targeting **glibc 2.28** (runs on old distros) |
| GitHub release asset | `.zip` | `.dmg` (universal) | `.AppImage` + `.tar.gz` |
| Signing | Unsigned by default (SmartScreen: "More info → Run anyway"); free OSS signing via SignPath is optional later | **Ad-hoc signed** (required for arm64); not notarised unless we buy the $99/yr Apple account; README explains "Open Anyway" | None needed |

**Every platform**
- **Custom Godot export templates** are built from the 4.7.2 source with `production=yes`,
  `lto=full` and `optimize=speed`, and with unused modules disabled (list finalised in Phase 0). Stock
  templates are used until then.
- **Rust release profile:** `lto = "fat"` and `codegen-units = 1`. Panics keep unwinding, so
  godot-rust turns a panic in a `#[func]` into a Godot error instead of a crash. CPU targets are
  `x86-64-v2` on x86_64 and `apple-m1` on Apple Silicon. Determinism is verified by the golden hashes.
- **World-gen worker threads** run at macOS `QOS_CLASS_UTILITY`, so they land on efficiency cores
  and leave the performance cores to the main and render threads (+16% fps measured).
- Controller support via Godot joypads (Steam Input also works for non-Steam games on the Deck),
  **full key rebinding**, and UI that can be navigated with a controller.
- **Update check:** on the main menu the game calls the GitHub Releases API (`/releases/latest`) and
  shows "New version available". It can be turned off in Settings.

**Windows**
- Benchmark D3D12 against Vulkan on NVIDIA, AMD and Intel. Keep the faster default for each vendor as a
  per-machine setting.
- Make sure hybrid-GPU laptops pick the discrete GPU; verify this on a real laptop.
- Offer an exclusive fullscreen option for lower latency.

**macOS**
- **Apple GPUs are tile-based, which is what Godot's Mobile renderer is built for.** It may beat
  Forward+ even on Medium, so benchmark both.
- Set `LSApplicationCategoryType = public.app-category.games` to enable **macOS Game Mode**.
- The GDExtension dylib inside the `.app` is ad-hoc signed together with the app.
- Unnotarised download: the README explains **System Settings → Privacy & Security → Open Anyway**, or
  `xattr -dr com.apple.quarantine Detour.app`.
- Render 3D at a scaled resolution on Retina/ProMotion displays, keep the UI at native resolution, and
  support 120 Hz. Memory is unified, so keep VRAM budgets strict.

**Linux / Steam Deck**
- Vulkan on Mesa (RADV/ANV) and NVIDIA, with a Compatibility fallback. Native **Wayland** is
  preferred, with X11 as a fallback.
- **Steam Deck:** add the AppImage as a non-Steam game. The Deck-friendly checklist covers:
  - a 1280×800 layout with text of at least 9 px;
  - controller-first menus and glyphs;
  - the on-screen keyboard for room and seed codes;
  - a 40 Hz mode + FSR;
  - reconnecting to the relay after suspend/resume.
- Document PRIME offload for hybrid laptops. Feral GameMode works through launch options.

---

## 11. Build, CI and release (GitHub)

**CI** (GitHub Actions, free on public repos, including arm64 Linux and macOS runners). The matrix is
`windows-latest`, `macos-latest` (arm64; the x64 slice is cross-built), `ubuntu-latest` and
`ubuntu-24.04-arm`.

**On every push and PR**
1. Rust: `cargo fmt --check`, `clippy -D warnings`, `cargo test` for `native/` and `server/`, and
   **world-gen golden hashes** on every runner.
2. GDScript: `gdformat --check`, `gdlint`, and headless GdUnit4 tests.
3. Build `rvcore` for each target and run a headless Godot export smoke test.
4. **Relay integration test:** start the relay, then run 3 headless Godot clients that create and join
   a room and exchange RPCs.

**Nightly**
- The bot drive over 500 seeds.
- The 4-client soak test through the relay.
- A performance flythrough on a self-hosted low-end runner (the OptiPlex or a Deck). If p95 frame
  time is **>10% worse** than the last green run, the build fails.

**Release** (on a `v*` tag)
- Build and attach game assets for each OS, plus `detour-relay` binaries, a `SHA256SUMS` file and the
  changelog.
- Push the multi-arch relay image to `ghcr.io/<owner>/detour-relay:<version>` and `:latest`.

**Versioning:** semver for the game. The game protocol version, `RELAY_PROTO` and `GEN_VERSION` are
separate integers, so an old relay keeps working with new game versions.

**Licence files:** `LICENSE` (see Open questions), plus `THIRD_PARTY_NOTICES` covering Godot, Jolt,
ENet, Opus and FSR (all permissive).

Development is trunk-based, with feature flags for unfinished content. Binary art goes in Git LFS.

---

## 12. Milestones

Time estimates are rough and assume 2 programmers and 1 artist; a solo developer should expect about
2.5× longer. Each phase has **exit criteria** that must pass before moving on. The riskiest work comes
first on purpose.

**Phase 0 — Foundations and spikes (2 wks)** ← *in progress (Apple Silicon first)*

Status (2026-09-28):
- **Done:** repo, Godot 4.7.2, Rust workspace, `rvgen` with 21 unit tests plus a golden
  determinism test, `rvgen-cli`, and `rvcore` (sync `WorldGen` plus the threaded
  `ChunkBuilder`), loaded and tested in Godot on macOS.
- **Done:** a terrain streamer with LOD and instanced trees, and a benchmark scene; the baseline
  is in `docs/perf.md`.
- **Done:** relay server plus `RelayMultiplayerPeer`, with an end-to-end test on one machine
  (`tests/relay_e2e.gd`). Still to do: a Pi-hosted room with clients on every OS.
- **Deferred:** Windows/Linux builds and the CI matrix.
- **Pulled forward from Phases 1 and 3 (2026-09-28):**
  - The drivable RV (`src/rv/`): shape-cast wheels, spring/damper suspension, slip-limited
    tires, anti-roll bars, drag; engine with torque curve, clutch (stalls when dumped), 5-speed
    H-pattern shifter dragged with the mouse, sequential/number-key shifting with clutch
    assist, automatic gearbox, parking brake, headlights, chase and cab cameras, dev HUD.
    `src/game/playground.tscn` is now the main scene. Still to do for Phase 1: the interior
    physics space, getting in and out, the roof ladder and a live-tuning panel.
  - Deterministic prop scatter (`rvgen::scatter::props`, in the golden test): rock clusters
    and boulders, stumps, logs and saplings, with real models, collision (heightmap, trunks,
    convex rocks) streamed around the RV, and cone stand-ins for distant trees.
  - Tests: `tests/rv_units.gd` (drivetrain, shifter) and `tests/rv_drive.tscn` (spawn, stall,
    pull away, shift, brake, handbrake, automatic, reverse) run headless.
- **Adventure layer (2026-09-28, tracked in RV_THERE_YET_FEATURE_COMPARISON.md §16):** on-foot
  player with the RV interior space (§6.3), seats, items; winches, planks, pushing; and the
  trip (`rvgen::route`, GEN_VERSION 2): a carved road with gap/ledge/mud/climb obstacles and a
  solvability validator, gas-station checkpoints with saves and restocks, camp and home.

- **Playability and polish (2026-09-30, M12):**
  - Manual gearbox made usable: each gear really raises the top speed (the hidden default
    linear damping had been capping it), the starter holds the clutch so a stalled engine always
    restarts, and a big ENGINE OFF / STARTING banner says what state it's in.
  - Survival: venom only ticks when you've been bitten (and never inside the RV); the RV can't
    hurt you by driving into you. Getting into and out of the RV is a walked stride.
  - **Phase 8 audio, mostly landed:** sound effects for the RV, footsteps on every surface,
    items, tools, winch, wildlife, weather and the UI, plus a horn and a Music bus (the
    `sound` branch was merged first). Checked by `tools/audio/check_sounds.py` and `check_mix.py`.
  - **Pulled forward from Phases 7 and 9:** key rebinding (keyboard, mouse and controller),
    cosmetics (hats and glasses, some earned), achievements, and cassette tapes with subtitled
    narrative. Still to do from those phases: proximity voice, localisation, dedicated host mode.

Original scope:
- Set up the repo, pin Godot 4.7.2, and create the Rust workspace. Get `rvcore` loading in Godot on all
  three OSes.
- Build the `rvgen` skeleton: seed codes, RNG, deterministic noise, chunk heightfields, quantisation,
  chunk hashes and golden tests. Add `rvgen-cli` to dump PNGs and hashes.
- **Relay spike:** the Rust relay plus the GDScript `RelayMultiplayerPeer`. Prove that
  `rusty_enet` ↔ Godot ENet wire compatibility holds, and that rooms and RPCs work through the relay.
- Build a greybox benchmark scene: streamed generated terrain, a free-fly camera and an FPS/frame-time
  overlay. Run it on Potato and Low hardware with Forward+, Mobile and Compatibility.
- Set up CI: Rust tests and golden hashes on 4 runners, `rvcore` builds, relay binaries and the Docker
  image.
- ✅ **Exit:** a relay on the Pi hosts a room joined by Mac, Windows and Linux clients; golden hashes
  are equal on every runner; benchmark numbers are in `docs/perf.md`.

**Phase 1 — RV feel, single player (3 wks)**
- The RV rigid body, wheels, suspension, tires and drivetrain; the clutch and mouse H-pattern gearbox,
  plus the automatic option.
- The first-person camera, cab controls and dashboard gauges.
- Getting in and out; walking inside the moving RV (the interior physics space); the roof ladder.
- An in-game live-tuning panel.
- ✅ **Exit:** driving over greybox hills is fun at 60 fps; standing inside at 60 km/h shows **zero
  jitter**; tipping over is possible but rare.

**Phase 2 — Netcode core (3 wks)**
- Transports (relay, LAN with a beacon, direct IP), the room-code UI, player replication and
  interpolation.
- RV driver ownership and handoff, interior-space replication and push intents.
- The network conditioner and desync hashing.
- ✅ **Exit:** 4 players on mixed OSes drive for 30 min through the Pi relay at 150 ms latency / 2% loss
  with no desync and no visible passenger jitter.

**Phase 3 — World gen v1 (4 wks)**
- The trip graph, route spline, corridor heightfield, road carving, and chunks with LOD and the
  collision ring.
- Scatter and instancing, the gas-station template, streaming, seed codes and the first paper map.
- ✅ **Exit:** a 3-station trip loads in under 3 s, streams with under 2 ms of main-thread work per
  frame, and generates identically on every target.

**Phase 4 — Co-op mechanics (4 wks)** → **MVP**
- The winch, items and inventory, carrying and throwing, and plank bridges.
- The damage model and repairs, fuel and oil.
- Gas stations, save/load, joining in progress and world deltas.
- ✅ **Exit:** a complete Short trip can be played in co-op (through the relay) *and* solo. This is the
  first public GitHub pre-release (`v0.1.0`).

**Phase 5 — Danger (3 wks)**
- Health, the downed state with EpiPen revives, and respawn.
- Bears, snakes and eagles.
- Rockslides, fords, mud, lava and ice.
- Weather, day/night and ragdolls.

**Phase 6 — Content and generator depth (5 wks)**
- All 5 biomes and 40+ set-pieces, route branches and the difficulty curve.
- Validation plus the bot drive; trips up to 12 stations.
- Featured seeds, the home finale and the trip summary.

**Phase 7 — Voice, social and server extras (3 wks)**
- Opus proximity voice, inside/outside muffling, push-to-talk/voice activity, and per-player volume.
- Payload encryption, **dedicated host mode**, cosmetics, and relay hardening (password, metrics).

**Phase 8 — Art and audio pass (runs alongside Phases 3–7, artist-led)**
- The final cozy semi-realistic RV, characters, per-biome props and the UI theme.
- Engine audio layered by rpm and load, surface sounds, ambience, weather, music and the horn.

**Phase 9 — Performance and platform hardening (3 wks)**
- Presets, auto-detection, dynamic resolution and custom templates.
- The Deck checklist, macOS polish and Linux packaging.
- Controller support and rebinding, accessibility, localisation and the update check.
- ✅ **Exit:** every target in §9.1 is met on the test hardware, and the performance CI gate is green.

**Phase 10 — 1.0 on GitHub (2+ wks)**
- A public beta through pre-releases and bug burn-down.
- The README and website (GitHub Pages), a trailer, and the `v1.0.0` release.

**Total: ~35–40 weeks** for 1.0; the MVP (`v0.1.0`) arrives after ~16 weeks.

---

## 13. Risks

| Risk | Mitigation |
|---|---|
| The vehicle doesn't *feel* fun | Prototype it first (Phase 1), use a live-tuning panel, and playtest weekly |
| Passengers jitter in the networked RV | The interior physics space plus driver ownership, proven in Phases 1–2 |
| Procedural maps feel bland | Handcrafted set-pieces joined by procedural terrain, a difficulty budget, bot validation and featured seeds |
| Clients generate different worlds | Pure-Rust integer-hash generation, `libm`, quantisation, golden-hash CI, and chunk transfer at runtime |
| `rusty_enet` doesn't interoperate with Godot's ENet | The Phase 0 spike tests it first. Fallback 1: the relay links the C ENet library (`enet-sys`). Fallback 2: the relay is a headless Godot app using `ENetConnection`, which is guaranteed compatible but heavier. |
| Home upload bandwidth limits the relay | ~0.6 Mbit/s per room is measured and documented; LAN and direct IP skip the relay |
| Exposing the home server | A dumb router with strict limits, one UDP port, a sandboxed non-root service, an optional password, and payload encryption |
| Godot misses the frame rate on iGPUs | Benchmark in Phase 0; Mobile and Compatibility renderers, strict art budgets, and dynamic resolution |
| Unsigned apps scare users | A clear README, SHA256 sums, and optional SignPath / Apple notarisation later |
| Scope (5 biomes of art) | The MVP uses 2 biomes; a shared palette-atlas workflow; reused prop kits |
| IP or trademark claims | Original name, art, audio and place names; mechanics only; the repo is not named after the original |

---

## 14. Open questions

1. **Game and repo name.** "Detour" is a placeholder; check for clashes before the repo goes public.
2. **Licence.** The suggestion is **MIT for code** and **CC BY 4.0 for art and audio**. Or would you
   prefer GPL/AGPL so that forks stay open?
3. **Relay address.** Should releases ship with *your* relay pre-filled as the default server, or
   leave it blank so people add their own? A pre-filled address makes it public, and strangers could
   use your bandwidth.
4. **Parity versus additions:** strict item and mechanic parity, or are additions such as the
   flashlight, radio and eagle theft welcome?
5. **Team and timeline:** who is building this? The phase estimates depend on it.
6. **Menu and UI feel:** within the cozy semi-real direction, any brand colours or type preferences?

---

## Sources
- Steam store page: https://store.steampowered.com/app/3949040/RV_There_Yet/
- Wikipedia: https://en.wikipedia.org/wiki/RV_There_Yet%3F
- Game8 review: https://game8.co/articles/reviews/rv-there-yet-review
- SaveGame review: https://savegame.co.uk/rv-there-yet-review-the-chaotic-co-op-road-trip-your-friend-group-needs/
- Community wiki: https://rvthereyet.space/guides/wiki
- System requirements / performance: https://rvthereyet.space/guides/system-requirements
- Godot 4.6 release (Jolt default, D3D12 default on Windows): https://godotengine.org/releases/4.6/
- Godot 4.7 release: https://godotengine.org/releases/4.7/
- Godot MetalFX PR: https://github.com/godotengine/godot/pull/99603
- godot-rust: https://godot-rust.github.io/
- rusty_enet: https://github.com/jabuwu/rusty_enet
