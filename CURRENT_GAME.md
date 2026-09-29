# Detour: what the game does today

A snapshot of the playable build (updated 2026-09-29), for comparing against *RV There Yet?*.
Everything below is implemented and running unless it's in [Not in the game yet](#not-in-the-game-yet).
The long-term design is in [PLAN.md](PLAN.md).

**In one line:** a road trip for 1–4 players: from a camp, along a generated forest road, past
washed-out bridges, ledges, mud and steep climbs, bears and rattlesnakes, through gas-station
checkpoints, to home, in a heavy 1970s motorhome (real clutch and gearbox) you can climb into,
walk around, winch, push and repair. Play solo or together on a LAN, by IP or through a relay.

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
| **E** | Interact with what you're looking at: open/close the door, sit in a seat (the driver's seat takes the wheel), pick up an item, put a patty on a grill; when you're down: give up and pass out |
| **Left click** | Use the held item (e.g. eat a burger, spray bear spray); when you're down: use your EpiPen |
| **Right click** | Throw the held item (inside the RV: put it down) |
| **Q** / **G** | Drop the held item (inside the RV it's stowed and rides along) |
| **R** | With the winch remote: switch between front and rear winch |
| **L** | Flashlight on/off |
| **1**–**4** / **mouse wheel** | Pick a hotbar slot (small items pocket; big ones need an empty hand) |
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
| **F** | Get up from the driver's seat |
| **Mouse** | Look around the cab (while the mouse is captured) |
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
| **Right stick** | Look around the cab |
| **X** (hold) | Clutch |
| **RB** / **LB** | Shift up / down (with clutch assist) |
| **B** | Handbrake |
| **Y** | Start engine |
| **D-pad up** | Headlights |
| **D-pad down** | Manual ↔ automatic |
| **Menu / Start** | Pause menu |
| **R3** (right stick click) | Back on the wheels |

The H-pattern stick is mouse-only for now; on a controller you shift sequentially.

### Debug scenes (developers)

- **Terrain benchmark** (`src/debug/terrain_bench.tscn`): **1**–**4** presets, **F3** overlay,
  hold **right mouse** + **WASD** to fly, **Q/E** down/up, **Shift** fast.
- **Drive tour** (`src/debug/drive_tour.tscn`): drives itself and saves screenshots.

---

## On foot

- **First person, always**: on foot, in a seat and driving you see through your character's
  eyes; there's no third-person or chase view.
- **Everyone is a pill-shaped person** (primitives for now, a Blender model later): one
  rounded body whose top is the head, dark glasses, a beanie and a vest in the player's
  colour over a white shirt, light trousers, stubby arms and feet. Your own body casts a
  shadow.
- **First-person player** with walking (4.2 m/s), sprinting (7 m/s), crouching and jumping; steps
  up ledges up to 40 cm; collides with the terrain, rocks, trees and the RV's hull.
- **Interaction**: a crosshair and a short "E  …" label for whatever you're looking at within
  reach: an item's name, "Open", "Sit", "Put it here", "Winch hook". The HUD never explains how
  to solve anything: what you're holding shows its name, plus a terse action ("LMB fit", "LMB
  pour", "LMB lay") only while you're aiming at somewhere it would work. Working out where the
  fuel cap is, what the hammer needs, or where the planks went is up to you.
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
  the start; the RV's own kit starts put away in its storage (below).
- **RV storage** (31 places; hold a fitting item, look at the spot, **E**; pick it back up to
  take it out). Stored things ride along:
  - Outside: a **plank rack** down the left side (3 planks), the **spare-tire mount** on the
    back (a spare or a wheel) and two **jerry-can holders** on the rear bumper.
  - Inside: the **tool wall** on the wardrobe (hammer, drill, winch remote), the **top of the
    fridge** (6: food and drinks), the **overhead shelf** over the cab (8: medicine, bear
    spray, tools), the **bed** (6: scrap, oil, first aid, small things, food) and two **cup
    holders** on the dashboard.
  - The RV starts with the hammer and drill on the tool wall, burgers and patties on the
    fridge, a soda in a cup holder, first aid and scrap on the bed, and the EpiPen, antidote
    and bear spray on the shelf; the winch remote lies on the dashboard.

## Time of day and weather

- **Clock**: trips start at **08:00** on day 1; one game hour passes per real minute (a day
  is 24 minutes). The top of the screen shows "Day 1, 14:05 · Rain". Tows cost an hour.
- **Day and night**: the sun rises in the east at 06:00 and sets in the west at 18:00; dawn
  and dusk tint the sky and sunlight orange; nights are dark blue under a faint moon. Use the
  RV's headlights and your **flashlight** (**L** on foot).
- **Weather** comes in 3-hour spells, the same for everyone on a seed (the first morning is
  always fine): clear, cloudy, rain, fog or storms. In Frostpeak Pass wet spells are snow; Red
  Rock Canyon stays dry (clouds instead of rain, no fog).
  - Rain and snow fall around you; clouds dim and grey the sky; fog closes in.
  - Rain wets the ground over a minute or so (it dries slowly afterwards): wet tires grip up
    to 15 % less.
  - Storms bring lightning flashes and gusts that rock the tall RV sideways.

## Health and survival
- **Health** (100). Hurts: **falls** (a ~5 m drop is safe, ~8 m costs a quarter, ~15 m nearly
  everything), **the RV** running into you (it doesn't stop for people: get out of the way),
  **bears**, **snakes** and **eagles**. A red flash shows each hit.
- **Snake venom**: a bite poisons you (the screen tints green): −1.2 health a second for 90 s
  unless you use an **antidote**.
- **Downed**: at 0 health you drop to the ground and can only crawl (0.8 m/s). You bleed out in
  **60 s**. Left click uses an **EpiPen** from your hotbar to get back up with 40 health; a
  teammate can revive you with theirs (E on you). **E** gives up; bleeding out or giving up
  wakes you by the RV with 50 health (+5 min on the trip clock).
- **Food and medicine**: burger +30, soda +10, first-aid kit +60, cooked patty +40 (a raw one
  +5, a burnt one +10; a frozen one can't be eaten).
- **Cooking**: frozen patties go on a grill (E while holding one): **the RV's stove**, the
  **camp fire** and a **grill at each gas station**. They thaw (6 s), cook (14 s) and burn
  (32 s), changing colour; pick them off with E.
- **Wildlife** (placeholder low-poly shapes for now), placed the same way for the same seed,
  more and meaner further along the road; nothing notices you while you're inside the RV:
  - **Rattlesnakes** by the road near obstacles, where you have to get out. They **rattle**
    when you come within 6 m (3.6 m crouching): go round. Closer than 1.6 m they **bite** (8
    and venom).
  - **Bears** in the woods beside obstacles (never near the camp or home). A bear sees you
    within 24 m (12 m crouching), **rears up** as a warning, then **charges** at 6.3 m/s
    (you sprint at 7) and **swipes** for 30. It gives up if you get in the RV, go down, get
    45 m away or lead it 80 m from home.
  - **Eagles** circle over gas stations and the later road. They dive at anyone outside
    holding something small (food, medicine, bear spray), snatch it with a scratch (5) and
    drop it 60–90 m away.
  - **Bear spray** (6 puffs): left click sprays a 7 m cone that sends bears and snakes off
    (and makes an eagle drop what it's carrying). The RV driving at an animal scares it off
    too.
  - The HUD shows what you'd hear: "*rattle rattle*", "*ROAR*", "*SCREECH*" (until
    sounds land). `-- --peaceful` turns wildlife off.

## The trip

Every seed makes a trip (a **Short** trip is ~2.4 km: camp → 2 gas stations → home; Medium and
Long have 5 and 11 stations). The default seed is `DT4-00000-000DG`.

- **Biomes**: every trip starts in **the Pine Woods** and ends in **Frostpeak Pass** (the
  hardest); in between come the **Muddy Bayou** and **Red Rock Canyon** in a seeded order
  (short trips see one of the two). The biome changes near each gas station, blending over
  ~180 m, and the top of the screen says "Entering ..." as you cross.
  - *Pine Woods*: rolling forested hills (the original terrain).
  - *Muddy Bayou*: low and flat, olive-green ground, bayou trees and dead snags, ponds beside
    the road, lots of mud and river fords.
  - *Red Rock Canyon*: terraced mesas with banded red-and-cream cliffs, sand, cacti and
    junipers, more rocks, no deadfall; ledges and climbs.
  - *Frostpeak Pass*: 18 m higher with bigger relief, snow on everything but steep rock, snowy
    firs, frozen lakes; ice, climbs and ledges.

- **The road**: a winding dirt road heading home (east), carved into the hills with cut and
  fill to a gentle grade (≤ 9 %), dirt-coloured so it's obvious where to go, cleared of trees
  and rocks, with the forest crowding its edges. Deep cuts through hillsides leave rocky walls
  either side.
- **The valley**: the road runs along a valley floor 40–58 m either side of it; past that,
  cliffs rise 24–45 m over ~12 m (far too steep to drive or climb) to a craggy crest, so the
  road is the only way to go. The valley is closed off behind the camp and past home, and
  opens out into bays round the side lakes and caves. A washed-out bridge's gully and a ledge's
  raised ground run right across the valley into its walls, so there's no driving round them.
  (Checked in the Rust tests by flood-filling everywhere you could stand from the camp.)
- **Obstacles** get harder towards home, with a quiet stretch now and then:
  - **Mud** (early): a soft dip where the tires grip at 40 % and drag hard. Keep your momentum,
    lay planks, or winch.
  - **Steep climbs** (5–9 m humps, ~25–30 % at their steepest): low gear and momentum, or
    winch.
  - **Washed-out bridges** (from mid-trip): a 3.8–4.4 m gap between two concrete abutments over
    a 2–2.6 m deep trench. The RV can't cross (it noses in, even at speed). What's left of the
    bridge, 4 planks, lies in a heap off in the trees 8–16 m from the road, 12–40 m before it
    (on the side that's easiest to walk to): find them, and lay two across, one under each
    wheel track.
  - **Ledges** (from mid-trip): a sheer 1.1–1.7 m step up the road; the ground either side is
    raised so you can't drive round. A big boulder waits at the top: hook the winch on and
    reel yourself up.
  - **River fords** (bayou, sometimes canyon): a river crosses the road, 0.45–0.75 m deep at
    the road and over 2 m deep either side, so you can't go round. Drive through slowly: water
    drags hard (the dashboard warns "WADING"), and water over the air intake (in the deep bits)
    stalls and damages the engine. You can swim in it.
  - **Ice** (the pass): the road drops ~1.4–2 m into a frozen pond 14–18 m across, and climbs
    out up a ~15 % ramp that's icy at the bottom. Tires get 15 % grip on ice. A plank laid on
    ice gives full grip under that wheel; 4 planks lie off in the trees before each pond and a
    boulder to winch from waits beyond it.
  - Nothing warns you: there are no signs before obstacles.
- **The generator guarantees solvability**: every gap has planks before it and fits a plank;
  every ledge has an anchor within winch reach; every icy pond has planks and an anchor; fords
  are never deeper than 0.8 m; lakes and caves never touch the road; obstacles are ≥ 120 m
  apart; the road's grade outside obstacles stays in limits. Checked for 200 seeds in the
  Rust tests.
- **Lakes**: ponds 12–30 m across beside the road in the bayou (with a dark bed; swim in them)
  and frozen lakes in the pass (walkable, slippery ice).
- **Caves**: in the woods and the canyon, a cave in a clearing off the road on most stretches
  (grey or red rock walls under a slab roof, a timber frame at the mouth, a lantern, a crate
  and a barrel) holding 3–5 random supplies: scrap, planks, food, drinks, a jerry can,
  medicine, bear spray, oil or a spare tire.
- **The start camp**: tent, campfire, bedroll and log pile by the road; the starter items lie
  by the RV.
- **Gas stations** (checkpoints): a shop with a diner sign, a canopy over two pumps, a welding
  bench, barrels and crates. Drive up to one and the game **saves** and **restocks**:
  2 planks, a jerry can, 2 scrap metal, motor oil, 2 burgers, a spare tire, 2 frozen patties,
  a soda, an EpiPen, an antidote and bear spray in front of the shop. There's a grill too.
- **Home**: a house with a fence and a big "HOME" sign. Arrive and the trip ends with a
  summary: time, distance driven, stalls and winch rope reeled in. The save is kept as a
  finished record (listed on the main menu; it can be started again, not continued).
- **Saves** (one per seed, in `user://saves`; solo and when hosting): the trip **autosaves**
  every minute, on reaching a gas station, on leaving to the menu and on quitting (a brief
  "Saved" shows top right). Continuing carries on from exactly where you were: the RV where it
  stood (put back upright), its state (damage, missing parts, wheels and bolts, fuel, oil,
  gearbox), everything stowed in it, **everything lying about the world** (dropped and thrown
  things, laid planks, what's left in caves and at stations, parts that fell off the RV), your
  health and hotbar, and the clock. **Tow to the last checkpoint** still goes back to the last
  gas station. Start over with `-- --new`, the menu, or **Restart this trip**.
- **Top of the screen**: the next stop and how far down the road it is, plus checkpoint notices.

## Damage, repairs and supplies

- **The RV comes apart**: 16 separate parts (hood, grille, both bumpers, six lower skirt
  panels, both wing mirrors, the door step, roof AC, ladder and awning). Knocks above a
  threshold dent the parts nearest the hit; at 0 % a part **falls off** and lies on the ground
  as something you can pick up. Big hits also chip the **frame**, and head-ons hurt the
  **engine**.
- **Wheels**: only real impacts hurt them. A wheel landing faster than 5.5 m/s (a drop of
  about 1.5 m) wears the tire (a **flat** grips badly); from about 2.3 m it shakes a **bolt**
  loose (5 per wheel), from about 3.6 m two. A hard sideways or head-on strike on a wheel
  does the same. Bumps, ruts and normal driving never loosen anything. A wheel on its last
  bolt slowly wobbles loose above ~30 km/h; with no bolts left it **comes off** and rolls away.
- **Engine**: burns **fuel** (60 L tank, 40 L at the start; harder driving burns more),
  slowly uses **oil** (faster when damaged or with the hood gone). Low oil makes it
  **overheat**: less power, then it cooks itself and **seizes**. Out of fuel or seized, it
  won't start.
- **Repairs** (look at the spot, left click):
  - **Hammer + scrap metal** (scrap in your pockets): patch a dented part (+50 %) or rebuild a
    missing one.
  - **Carry a fallen part back** and use it on its spot to refit it (no scrap needed).
  - **Spare tire** (or the wheel that came off) on an empty hub or a flat; then hold left click
    with the **power drill** to screw its 5 bolts in, one at a time.
  - **Motor oil** into the engine bay (front, under the hood). **Jerry can** (20 L) into the
    fuel cap (left side); refill it at a pump.
  - At gas stations: the **pump** fills the RV (parked close) or your jerry can; the
    **welder** restores the frame and looks the engine over.
- **Dashboard line** (driving HUD): fuel, oil, frame, plus warnings for overheating, low fuel
  or oil, wheels needing attention and missing parts.
- **Hotbar**: 4 slots; small items pocket, big ones (planks, tires, jerry cans, RV parts) need
  an empty hand. The RV starts with a hammer, drill and 2 scrap inside.

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
- **Seed codes** like `DT4-00000-000DG`: generator version, trip length and a 40-bit seed in
  Crockford base32, with a typo check. The default seed is fixed; `-- --seed=CODE` picks another.
- **Deterministic everywhere**: the same seed builds bit-identical terrain, trees and props on
  macOS (Apple Silicon), Linux and Windows (x86_64). CI checks this on every push with golden
  hashes. This is the foundation for multiplayer (only the seed needs sending).
- **Four biomes** in bands from west to east (see The trip), over a base of rolling hills
  from domain-warped noise, ridged mountain ranges in some regions, and small bumps. Heights
  0–1310 m in 2 cm steps.
- **Ground colours** per biome: in the woods lush grass, dry grass, dirt, bare rock on steep
  slopes and snow above ~330 m (treeline 320 m); olive bayou; sand and banded red rock; snow
  and grey rock. Ice is pale blue; river and pond beds are dark.

### Streaming
- 128 m × 128 m chunks with a 1 m height grid, generated on background threads around the RV.
- Level of detail: 1 m mesh spacing within 200 m, then 2 m, 4 m and 8 m further out.
- The main thread spends at most ~2 ms per frame adding new chunks, so streaming doesn't stutter.
- Fog hides the edge of the streamed area.

### Scenery (scattered by the generator, the same for everyone on a seed)
- **Trees** per biome: pines (three models, 8–14 m, cheap cones far away) in the woods;
  low-poly bayou trees and dead snags; saguaro cacti and junipers in the canyon; snowy firs
  in the pass. Density follows a forest-noise map and the biome (thick woods, sparse canyon);
  none on steep slopes, above the treeline, in water or on clearings.
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
- **Parking brake**: on automatically when the RV spawns or is reset, and when you get up
  from the driver's seat at a standstill (a manual box also goes to neutral, so it idles
  rather than stalls); it releases when you touch the throttle or let the clutch out in gear.
- **Air drag and rolling resistance.**

### Engine and gearbox
- An old big-block V8:
  - Torque peaks at 520 N·m at 2400 rpm.
  - Idles at 750 rpm, with an idle governor strong enough to creep the RV off in 1st with no
    throttle.
  - Rev limiter at 3800 rpm.
  - Engine braking when you lift off.
- **Stalling**: dump the clutch at low revs, or let the revs fall below ~380 rpm in gear, and
  the engine dies. Press **I** with the clutch down (or in neutral) to crank it for 0.7 s.
- **Clutch**: an analog pedal. It presses in 0.12 s and lets out in 0.55 s, biting mid-travel.
  Slip it with some throttle to pull away smoothly. A key is all-or-nothing, so letting **Q**
  go (when you're not braking) feathers it for you: the pedal waits at the bite point while
  the revs sag and backs off before a stall. So from a standstill: engine on, **Q**, **1**,
  let **Q** go and it pulls away (add **W** to go faster). Letting the clutch out against
  the brakes, or braking to a stop in gear without it, still stalls.
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
- **Driving view**: the driver's eyes in the cab, looking about ±125° left/right. (A chase
  camera exists only for the debug screenshot tours.)
- **Headlights**: two spot lights (70 m reach) that cast shadows on the high preset.

### Spawning and recovery
- At the start, the game looks for a level spot near the world origin that is clear of rocks
  and trees, facing open ground.
- **Backspace** does the same within 60 m of wherever you are, as a stand-in for the planned
  tow truck.

---

## Main menu and playing together

- **Main menu** (the game starts here; `-- --seed=CODE`, `--play` or `--new` skip it):
  - **You**: your name and jacket colour (remembered).
  - **Your trips** (when there are saves): each saved trip, most recent first, with how far
    along it is ("Short trip · past gas station 1 of 2 · 40% of the way · day 1, 14:05 · 12
    min played · 3 min ago"), and **Continue** (solo), **Host** (carry on together) and
    **Delete** (press twice). Finished trips say how long they took and offer **Again**.
    Saves from an older world generator are listed but can't be continued.
  - **Play solo**: a seed code (blank for a new trip) and the trip length (short, medium,
    long). It says "Continue this trip" when there's a save for that seed.
  - **Host a game**: on this network / direct IP (UDP port 24652), or through a relay server
    (type its address; the game gets a 6-letter room code).
  - **Join a game**: games hosted on the local network are listed (the host announces itself
    on UDP port 24653); or type the host's IP, or a room code (uses the relay address).
  - Joining checks the game version and protocol; a mismatch or a full game (4 players) is
    refused with a readable reason.
- **Co-op** (up to 4 players, drop-in: join a trip in progress and appear by the RV):
  - Everyone sees everyone else as their pill-shaped person in their colour with a name tag;
    they crouch, lie down when downed and sit in the seats.
  - **The driver's machine simulates the RV** (no input lag for the driver); everyone else
    follows it smoothly. When nobody drives, the host simulates it. Only one person per seat.
  - Pushing, repairs (hammer, drill, tires, oil, fuel, welder), the winch remotes and the door
    work for everyone and act on the shared RV.
  - **Items are shared**: the host keeps track of every item; picking up, pocketing, dropping,
    throwing, stowing in the RV, laying planks, grilling and eating show for everyone. If two
    people grab the same thing, the first one gets it.
  - **Wildlife and the trip run on the host**: bears, snakes and eagles go for any player;
    arrivals, saves and restocks happen on the host. Downed players can be revived by a
    teammate with an EpiPen (E on them).
  - The top of the screen lists who's playing (and the room code on a relay).
  - The pause menu doesn't pause online. Leaving (menu: **Leave to the main menu**) drops what
    you carried; if the host leaves, everyone goes back to the main menu with a message.

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
  - **Tow to the last checkpoint** (the RV and you go back to the last station; +15 min) and
    **Restart this trip** (host / solo only), and **Main menu** / **Leave to the main menu**.

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
  peer 1, rate limits and a password option. It runs on a Raspberry Pi. The game can host and
  join through one (see above); there's no public relay yet, so you run your own.

---

## Not in the game yet

Planned (see PLAN.md), roughly in the order they're coming:

- **Players**: the roof ladder and roof; a Blender character model (and animation) to
  replace the primitive one, and cosmetics.
- **The trip**: a paper map, route forks and loot detours.
- **More obstacles**: rockslides, cliffs and steps, lava; rivers that wind through the land
  (fords are straight channels today) and caves you drive through.
- **World variety**: a volcanic biome, real models and textures for the new biomes (the
  trees and caves are placeholder shapes), more weather effects (puddles, snow cover building up).
- **Co-op**: proximity voice chat; saving each player's inventory with the trip.
- **Sound**: engine, horn, tires, ambience, music. The game is currently **silent**.
- **Menus and options**: settings (key rebinding, graphics, audio), cosmetics, and the
  diegetic dashboard gauges.
