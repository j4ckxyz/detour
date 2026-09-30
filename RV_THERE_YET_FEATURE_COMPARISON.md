# Detour vs. RV There Yet? — full feature and gameplay gap analysis

**Comparison date:** 28 September 2026  
**Your build baseline:** `CURRENT_GAME.md`, snapshot updated 28 September 2026  
**Reference game:** *RV There Yet?* by Nuggets Entertainment, including the current three-map version available as of 28 September 2026.

---

## 1. Executive summary

Your current game already has a strong implementation of the **vehicle-driving foundation** of *RV There Yet?*: a detailed 1970s motorhome, manual clutch and H-pattern gearbox, automatic gearbox, physically simulated suspension, tire grip, RWD, steering geometry, headlights, recovery, chase/cab cameras, procedural terrain, deterministic generation, scenery collision and controller support.

The important distinction is that *RV There Yet?* is not fundamentally an endless driving sandbox. Its gameplay loop is a **finite cooperative journey**:

1. Start a trip with up to four players.
2. Everyone exists as an on-foot first-person character.
3. Players get into and out of one shared RV.
4. Drive through a deliberately authored route.
5. Stop at checkpoints/gas stations.
6. Explore the surroundings on foot.
7. Find, carry, store and use tools/resources.
8. Solve physical obstacles with the winches, planks, pushing and environmental interaction.
9. Keep the RV repaired and supplied.
10. Keep players alive using food/medical items and dealing with wildlife/hazards.
11. Reach the end of the map and Route 65.

The current build of **Detour has almost none of that second layer yet**. It has the vehicle and an endlessly generated world, but not the trip/game structure that makes the reference game a cooperative problem-solving adventure.

Your own snapshot explicitly describes the present build as a single-player sandbox with no objectives, trips or other players yet. fileciteturn0file0L7-L8

The most important missing systems, in order, are:

1. **On-foot first-person player character**
2. **Getting in/out of the RV and shared-player interaction**
3. **Finite trip/route with an actual objective and end condition**
4. **Interactive world objects and item pickup/carry/drop**
5. **Winch system**
6. **Checkpoint/gas-station/save structure**
7. **RV damage, repair and maintenance**
8. **Obstacle/puzzle generation and authored traversal**
9. **Co-op networking/player replication**
10. **Inventory/storage system**
11. **Player health/survival and medical systems**
12. **Wildlife and environmental hazards**
13. **Multiple authored biomes/maps**
14. **Fuel/resource economy**
15. **Food/cooking/consumables**
16. **Day/night/weather/atmosphere**
17. **Sound, music and environmental audio**
18. **Character cosmetics**
19. **Narrative/cassettes/exploration collectibles**
20. **Menus, settings, key rebinding and accessibility**
21. **Achievements/progression**
22. **Small reference-game interactions and polish**

The exact order is an implementation-priority judgement based on how much each system changes the fundamental gameplay loop. It is **not** a ranking of the two games.

---

# 2. What your game already has

## 2.1 Core vehicle

Your RV implementation is already substantially beyond a basic prototype.

Implemented:

- 1970s-style class C motorhome.
- 7.4 m long.
- 2.4 m wide.
- 3.45 m tall.
- 5.5-ton mass.
- High centre of mass.
- Visible suspension movement.
- Four individually simulated wheel contacts.
- 0.45 m suspension travel.
- Soft springs.
- Bump stops.
- Anti-roll bars.
- Load-dependent tire grip.
- Slip-angle tire model.
- Shared tire grip budget between acceleration, braking and cornering.
- Rear-wheel drive.
- Visible wheelspin.
- Ackermann steering.
- Speed-dependent steering angle.
- Keyboard steering easing/self-centering.
- Front-biased braking.
- Rear-wheel handbrake.
- Automatic parking brake on spawn/reset.
- Air drag and rolling resistance.
- Big-block V8 simulation.
- Torque curve.
- Idle governor.
- Rev limiter.
- Engine braking.
- Engine stalling.
- Analog clutch.
- Manual five-speed gearbox.
- Reverse.
- Physical H-pattern gate.
- Gear grinding if clutch is not used.
- Automatic gearbox.
- Automatic clutch.
- Automatic shifting logic.
- Reverse selection in automatic mode.
- Engine starting conditions.
- Gear/rpm/speed HUD.

The reference game also uses a five-speed manual rear-wheel-drive RV and a physical-feeling driving model, so this is one of the areas where your implementation is already closely aligned with the reference. The reference RV is explicitly described as a shared physics-driven vehicle whose handling depends on terrain, momentum and player input. citeturn0search1

## 2.2 RV visual model/interior

Your RV already contains:

- Over-cab bunk.
- Awning.
- Roof AC.
- Roof vent.
- Roof rack.
- Two spare tires.
- Rear ladder.
- Bumpers.
- Grille.
- Front and rear winch drums as visual components.
- Dual rear wheels.
- Two cab seats.
- Dashboard.
- Three gauges.
- Steering wheel.
- Gear stick.
- Handbrake.
- Dinette.
- Table.
- Benches.
- Kitchen.
- Stove.
- Sink.
- Cabinets.
- Fridge.
- Wardrobe.
- Rear bed.
- Over-cab mattress.

Animated:

- Steering wheel.
- Gear stick.
- Wheels.
- Suspension.

Not interactive yet:

- Entry door.
- Ladder.
- Winch drums.
- Spare tires.

This is important because the reference game makes the RV itself an interaction space rather than merely a vehicle. Its storage, repair equipment, doors, interior and external components become part of the gameplay.

## 2.3 World generation

Your current world has:

- Seed codes.
- Versioned deterministic generation.
- 40-bit seed.
- Cross-platform deterministic terrain.
- CI golden-hash checks.
- Endless generation.
- Pine-hill biome.
- Domain-warped rolling hills.
- Ridged mountain ranges.
- Smaller terrain bumps.
- Elevation from 0–1310 m.
- 2 cm height precision.
- Grass.
- Dry grass.
- Dirt.
- Bare rock.
- Snow above approximately 330 m.
- Treeline around 320 m.
- 128 × 128 m terrain chunks.
- Background chunk generation.
- Multiple terrain LOD levels.
- Fog to conceal streaming boundaries.

This is technically impressive infrastructure, but it serves a different purpose from the reference game's authored route system.

The reference game is built around reaching checkpoints and ultimately completing a route to Route 65, rather than driving indefinitely through an infinite procedural landscape. The official Steam description explicitly defines the core objective as getting the RV through the back country and finding the exit to Route 65. citeturn6view0

## 2.4 Scenery

Already implemented:

- Pine forests.
- Forest-density noise.
- Terrain-aware tree placement.
- Multiple tree models.
- Distant tree stand-ins.
- Rocks.
- Boulder variants.
- Rock clustering.
- Forest debris.
- Stumps.
- Fallen logs.
- Saplings.
- Terrain-aligned props.
- Collision for major scenery.
- Non-solid saplings.

This gives you a strong foundation for later obstacle generation.

## 2.5 Cameras

Implemented:

- Third-person/chase camera.
- Driver's-eye cab camera.
- Orbiting chase camera.
- Mouse camera control.
- Controller right-stick camera control.
- Chase-camera terrain/rock obstruction handling.
- Driver-eye looking limits.

However, the reference game's player experience depends heavily on **first-person on-foot interaction**. Your cab camera is not a substitute for this because the player cannot currently leave the RV and physically inhabit the world.

## 2.6 Controls

Your current vehicle controls are already broad:

Keyboard:

- W / Up — throttle.
- S / Down — brake/reverse.
- A/D or Left/Right — steering.
- Space — handbrake.
- Q — clutch.
- Q + mouse — H-pattern.
- E / wheel up — upshift.
- Z / wheel down — downshift.
- 1–5 — direct gear.
- R — reverse.
- T — manual/automatic.
- I — engine start.
- L — headlights.
- C — chase/cab camera.
- Mouse — look/orbit.
- Left click — capture mouse.
- Backspace — recovery.
- Esc — pause.
- F1 — controls.
- F3 — performance.
- F5–F8 — graphics presets.

Controller:

- Right trigger — throttle.
- Left trigger — brake/reverse.
- Left stick — steering.
- Right stick — camera.
- X — clutch.
- RB/LB — gear shift.
- B — handbrake.
- Y — engine.
- D-pad up — lights.
- D-pad down — manual/automatic.
- View — camera.
- Start — pause.
- R3 — recovery.

The H-pattern being mouse-only is a difference from a more complete controller implementation. Your own note explicitly says controller shifting is sequential rather than H-pattern. fileciteturn0file0L41-L59

---

# 3. What the real game is actually trying to do

The reference game's central fantasy is:

> Four people trying to get one badly abused RV home.

The RV is effectively the shared "character".

The important design consequence is that the game creates situations where:

- one player drives;
- another player gets out and scouts;
- another carries tools;
- someone operates the winch;
- someone repairs the RV;
- players physically move around the RV;
- players can become injured;
- players can rescue each other;
- the group must decide how to solve an obstacle.

The official Steam description directly emphasises one RV shared by up to four players, winching, proximity chat, maintaining the RV and helping each other. citeturn6view0

Therefore, reproducing the **vehicle physics alone does not reproduce the core game**.

---

# 4. Missing features — ranked by gameplay importance

## PRIORITY 1 — On-foot first-person player character

### Reference

Players are actual human characters who can:

- leave the RV;
- walk around the world;
- walk around the RV;
- enter the RV;
- stand on/around the vehicle;
- carry objects;
- use tools;
- interact with other players;
- interact with world objects;
- revive teammates;
- become exposed to environmental dangers.

The Steam store categorises the game as first-person, and the game is fundamentally built around first-person physical interaction. citeturn6view0

### Your current status

**Missing.**

Your own plan says:

- on-foot first-person characters;
- getting in/out of the RV;
- walking inside it while it moves;
- roof ladder;
- seats;
- item pickup/carry/throw.

These are explicitly listed as not yet implemented. fileciteturn0file0L268-L275

### Important gameplay requirement

The player should not merely have an optional first-person camera.

The character should be a real physical player entity.

That means:

- capsule/body collision;
- gravity;
- ground detection;
- slopes;
- jumping if appropriate;
- crouching if appropriate;
- walking/running;
- interaction ray;
- item-holding position;
- animation;
- camera attached to head/eyes;
- first-person arms/hands or suitable representation;
- being affected by moving RV;
- falling from RV;
- collision with RV/world;
- entering/exiting vehicle.

### Why this is #1

Almost every other missing gameplay system depends on this.

Without a player, you cannot properly implement:

- winch controller;
- item pickup;
- repairs;
- inventory;
- checkpoints;
- wildlife;
- medical items;
- planks;
- pushing;
- walking inside the moving RV;
- proximity voice;
- cosmetics.

---

# PRIORITY 2 — Getting in/out of the RV and physically occupying it

### Reference

The RV is not just driven from a fixed camera.

Players can:

- enter;
- leave;
- move around inside;
- occupy seats;
- walk through the living area;
- access storage;
- reach repair equipment;
- climb/access exterior areas;
- interact with the vehicle while it moves.

### Your current status

**Missing.**

Your RV has the interior geometry, but the doors, ladder and other parts are not interactive yet. fileciteturn0file0L114-L122

### Required systems

- Door interaction.
- Entry/exit animation or transition.
- Driver seat.
- Passenger seats.
- Interior collision.
- Seat occupancy.
- Player attachment to moving vehicle.
- Player movement while RV is moving.
- Falling/ejection behaviour.
- Ladder climbing.
- Roof access.
- Interior interactables.
- Vehicle-relative physics for passengers.

### Critical edge case

A player must be able to walk inside the RV while it is moving.

This is one of the mechanics that makes the reference game distinctive.

---

# PRIORITY 3 — Replace the endless sandbox with a finite trip/game objective

### Reference

The game has an actual objective:

**Get the RV home and reach Route 65.**

The first map, Mabutts Valley, contains a sequence of checkpoints and culminates in an end/credits condition. Current achievement data records 16 numbered Mabutts Valley checkpoints plus the final completion achievement. citeturn3search0

There are now three maps:

1. Mabutts Valley.
2. Mt. Yurbuttsk.
3. St. Búttin Bay.

The third map launched on 10 September 2026. citeturn8search0turn8search2

### Your current status

**Missing.**

Your current description explicitly says:

- no objectives;
- no trips;
- endless procedural world.

fileciteturn0file0L7-L8

### Required

At minimum:

- Start point.
- Route.
- Destination.
- Progress.
- Checkpoints.
- End condition.
- Win state.
- Failure/recovery state.
- Trip length/difficulty.
- Save/checkpoint progression.

### Important design consideration

You do **not** necessarily need to abandon procedural generation.

A good Detour equivalent could use:

- a deterministic seed;
- finite generated route;
- guaranteed obstacle solvability;
- generated checkpoint locations;
- generated destination;
- deterministic terrain;
- authored obstacle templates.

That would preserve one of your strongest technical features while creating the finite gameplay loop.

---

# PRIORITY 4 — Interactive objects and item manipulation

### Reference

Players can physically interact with objects around the world.

The basic interaction loop is:

**find → pick up → carry → store/use → discard/throw/reposition**

Items are a major part of solving problems.

### Your current status

**Missing.**

You have several future item models already made, but they are not gameplay systems. Your snapshot lists:

- jerry can;
- oil bottle;
- spare tire;
- scrap metal;
- plank;
- burger;
- antidote;
- EpiPen;
- bear spray;
- first-aid kit;
- winch remote.

fileciteturn0file0L257-L265

### Required

- Interaction prompt.
- Pickup.
- Held-object state.
- Carrying.
- Dropping.
- Throwing.
- Object collision.
- Object placement.
- Item ownership/network replication.
- Storage.
- Consumable use.
- Tool use.

This is one of the largest missing foundations.

---

# PRIORITY 5 — Winch system

### Reference

The winch is one of the defining mechanics.

The official game description specifically advertises a physics-based winch at both the front and rear of the RV. citeturn6view0

The RV has two mechanical winches, and the game uses them to solve terrain problems that the vehicle cannot simply drive through. The winch can be used for pulling, climbing and more unusual physics solutions. citeturn0search1

### Your current status

**Not functional.**

Your RV has front/rear winch drums visually, but the plan says the winch system is not implemented. fileciteturn0file0L109-L122

### Required

- Front winch.
- Rear winch.
- Winch cable.
- Cable physics.
- Cable attachment.
- Attachment target validation.
- Winch controller.
- Reel in.
- Reel out.
- Cable tension.
- Cable break/failure.
- Vehicle force application.
- Anchoring to suitable objects.
- Player physically attaching the cable.
- Network synchronisation.
- Two-winches-at-once behaviour.

### Why it is so important

The reference game does not use the winch as a decorative vehicle feature.

It is one of the primary ways players solve obstacles.

---

# PRIORITY 6 — Checkpoints / gas stations / save structure

### Reference

Gas stations function as checkpoints and contain supplies/tools. The reference game has a sequence of checkpoints across its maps. citeturn0search8turn3search0

A checkpoint changes the strategic loop:

**drive → obstacle → damage → supplies → repair → checkpoint → continue**

### Your current status

**Missing.**

Your plan describes:

- gas-station checkpoints;
- refuel;
- repair;
- restock;
- revive;
- save.

fileciteturn0file0L276-L279

### Required

- Checkpoint trigger.
- Checkpoint activation.
- Persistent progress.
- Respawn/reload point.
- Gas station structure.
- Repair area.
- Item spawning.
- Fuel supply.
- Save.
- Player revive/reset.
- Map progression.

---

# PRIORITY 7 — RV damage and repair

### Reference

The RV has several distinct damage systems.

The reference game separates:

- body/exterior damage;
- tire/wheel damage;
- engine damage;
- frame damage.

Body panels act partly as protection. Mechanical damage can eventually destroy the RV. citeturn0search1

Repair uses different tools/resources:

- Repair Hammer + Scrap Metal → body.
- Power Drill → wheel bolts/tires.
- Motor Oil → engine.
- Welding Machine → frame.

citeturn4search1

### Your current status

**Missing.**

Your current RV has physical handling damage only in the sense of physics consequences such as tipping/wheelspin; it does not yet have the reference game's repair economy.

Your planned system explicitly includes:

- flat tires;
- spare-tire swaps;
- oil leaks;
- overheating;
- body damage;
- scrap-metal repair;
- parts falling off;
- hammer repairs;
- fuel use.

fileciteturn0file0L287-L292

### Recommended damage model

Separate:

**Body**
- doors;
- bumpers;
- mirrors;
- panels;
- ladder;
- external components.

**Wheels**
- loose bolts;
- damaged tire;
- missing wheel.

**Engine**
- overheating;
- oil damage;
- engine condition.

**Frame**
- severe structural damage.

Then make damage physically meaningful rather than merely visual.

---

# PRIORITY 8 — Authored physical obstacles and problem-solving

### Reference

The route deliberately creates problems for the RV.

Examples include:

- mud;
- ice;
- water;
- steep sections;
- gaps;
- cliffs;
- bridges;
- caves;
- rock obstacles;
- environmental hazards;
- narrow passages;
- sections requiring planks;
- sections requiring winches.

The key design principle is:

**The player should have to work out how to get the RV through.**

### Your current status

**Mostly missing.**

Your procedural terrain currently creates hills, rocks, trees, stumps and logs, but it does not have the reference game's designed obstacle/puzzle structure.

Your plan explicitly lists:

- winch obstacles;
- pushing;
- planks;
- fords;
- mud;
- rockslides;
- cliffs;
- steps;
- lava;
- ice;
- guaranteed-solvable obstacle generation.

fileciteturn0file0L280-L286

### Recommended architecture

Do not rely purely on random obstacles.

Use a generator made from **obstacle templates**:

```text
ObstacleTemplate
├── entrance conditions
├── terrain requirements
├── required tools
├── possible solutions
├── difficulty
├── failure consequences
└── guaranteed solution
```

Examples:

```text
mud trench
├── drive slowly
├── winch
└── push

broken bridge
├── plank
├── winch
└── alternate route

steep ledge
├── momentum
├── winch
└── plank/ramp
```

This fits your deterministic procedural architecture particularly well.

---

# PRIORITY 9 — Multiplayer / co-op

### Reference

The defining multiplayer structure is:

**one shared RV + up to four players.**

Steam explicitly lists online co-op, and the official game description says players drive one RV together with up to four players. citeturn6view0

### Your current status

You have infrastructure, but not gameplay.

Your relay server already exists:

- Rust.
- Room codes.
- Host/peer model.
- Rate limits.
- Password option.
- Raspberry Pi deployment.
- End-to-end networking test.

But your own note confirms:

- no lobby;
- no room-code screen;
- no player replication;
- therefore single-player only.

fileciteturn0file0L257-L262

### Required

- Lobby.
- Host/join.
- Player spawning.
- Player replication.
- RV state replication.
- Item replication.
- World-object state replication.
- Winch replication.
- Damage replication.
- Checkpoint state.
- Player death/revive.
- Disconnect handling.
- Host migration or clear host-failure behaviour.
- Session password.
- LAN/direct connection if desired.
- Voice proximity.

### Your current relay architecture is a useful head start

Your deterministic seed approach is particularly compatible with this.

Instead of synchronising the entire world:

```text
server/session
    seed
    map
    checkpoint
    player states
    changed objects
    RV state
    item state
```

The deterministic terrain generator can reconstruct most static terrain locally.

---

# PRIORITY 10 — Inventory and RV storage

### Reference

The RV is effectively a mobile equipment depot.

The reference RV has:

- 30 main storage spaces;
- 12 small-item spaces;
- 12 medium-item spaces;
- 6 large roof spaces;
- tool storage;
- spare-tire storage;
- drink holders;
- plank storage.

citeturn0search1

### Your current status

**Missing.**

### Required

- Player inventory.
- RV inventory.
- Item size/category.
- Storage slots.
- Physical storage locations.
- Item dropping.
- Item persistence.
- Network replication.
- Tool storage.
- Spare tire storage.
- Plank storage.
- Consumable storage.

The physical storage layout is important because it makes the RV feel like a real shared vehicle rather than an abstract inventory screen.

---

# PRIORITY 11 — Player health, survival and revival

### Reference

Players themselves can become injured and require assistance.

Important items include:

- burgers/food;
- antidotes;
- EpiPens;
- first-aid/medical equipment;
- bear spray.

The official Steam description specifically calls out burgers, antidotes and EpiPens as survival supplies. citeturn6view0

The achievement system also confirms substantial EpiPen usage as a real gameplay system. citeturn3search0

### Your current status

**Missing.**

Your plan explicitly includes:

- health;
- burgers;
- snake venom;
- antidote;
- downed players;
- EpiPen revival.

fileciteturn0file0L293-L294

### Required

- Player health.
- Downed state.
- Death.
- Revive.
- Medical item interaction.
- Damage types.
- Poison/venom.
- Food/hunger if retained.
- Respawn/checkpoint behaviour.

---

# PRIORITY 12 — Wildlife and environmental danger

### Reference

The game has dangerous wildlife.

Known examples include:

- bears;
- snakes;
- eagles;
- snow leopards;
- other map-specific creatures.

Mabutts Valley is explicitly described as containing aggressive wildlife such as bears and snakes. citeturn1search0

Achievements also directly confirm wildlife-related gameplay, including bears, snakes/survival systems, a snow leopard and a monster in Mt. Yurbuttsk. citeturn3search0

### Your current status

**Missing.**

Your plan lists:

- bears;
- snakes;
- eagles;
- bear spray;
- snake venom;
- antidote.

fileciteturn0file0L293-L294

### Important

Wildlife should not just be enemies.

They should create:

- route choices;
- distractions;
- panic;
- risk while outside the RV;
- resource consumption;
- co-op rescue situations.

---

# PRIORITY 13 — Multiple authored maps / biomes

### Reference

As of 28 September 2026 there are three maps:

### Map 1 — Mabutts Valley

Features include:

- forests;
- caves;
- swamps;
- aggressive wildlife;
- mines;
- many checkpoints;
- varied off-road obstacles;
- Route 65 completion.

Mabutts Valley is the original map. citeturn1search0

### Map 2 — Mt. Yurbuttsk

Features include:

- mountainous terrain;
- snow;
- ice;
- winter hazards;
- snow chains;
- snowballs;
- snow leopard;
- ice-related obstacles;
- inner-tube/tractor-tube activities;
- map-specific narrative/audio;
- checkpoints.

The achievement set confirms map-specific snow chains, ice cubes, snow leopard, ice monster and tractor-tube mechanics. citeturn3search0

### Map 3 — St. Búttin Bay

Released 10 September 2026.

The official update lists:

- new map;
- new animals;
- new items;
- new tools;
- new narrative;
- new music;
- coconut drinks;
- beach paddles;
- additional map-specific content.

citeturn8search0turn8search2

The current achievement/guide material shows that St. Búttin Bay has at least 22 checkpoint progression markers, multiple cassettes, cosmetics and a distinct route structure. citeturn8search3

### Your current status

**Missing as authored gameplay.**

You currently have one endless procedural biome: pine hills. fileciteturn0file0L77-L81

You already have the technical ability to generate terrain, so the major task is building different biome/obstacle/prop rules and finite route structures.

---

# PRIORITY 14 — Fuel and resource economy

### Reference

The RV needs resources to complete a journey.

Relevant systems include:

- fuel;
- spare parts;
- repair resources;
- consumables;
- checkpoint restocking.

### Your current status

**Missing.**

Your plan specifically calls out fuel use and jerry cans. fileciteturn0file0L287-L292

### Required

- Fuel capacity.
- Fuel consumption.
- Refuelling.
- Jerry cans.
- Fuel stations.
- Empty/full containers.
- Fuel failure state.
- Resource scarcity.

This creates an actual reason to care about checkpoints.

---

# PRIORITY 15 — Food, cooking and consumables

### Reference

Food and consumables are part of the game's survival/comedy loop.

The Steam page explicitly lists grilling frozen meat patties and using burgers. citeturn6view0

The game also includes cigarettes and drinks as physical items/interactions. citeturn6view0

### Your current status

**Missing.**

You have a burger model, but not the gameplay system. fileciteturn0file0L263-L265

### Required

- Food pickup.
- Food inventory.
- Grill.
- Cooking state.
- Eating.
- Hunger/health effect if implemented.
- Drinks.
- Cigarettes.
- Consumable effects.

This is lower priority than the basic player/item/obstacle systems because it can be added once interaction is working.

---

# PRIORITY 16 — Day/night, weather and environmental conditions

### Reference

The reference game uses map-specific environmental conditions rather than one uniform procedural landscape.

Mt. Yurbuttsk particularly adds winter conditions and ice/snow gameplay. Map 3 adds a substantially different environment.

### Your current status

**Mostly missing.**

Your current world has terrain-dependent ground colours and snow at elevation, but not a full weather/day-night system. fileciteturn0file0L77-L81

Your plan lists:

- weather;
- day/night;
- rivers;
- lakes;
- multiple biomes.

fileciteturn0file0L295-L296

### Required

- Time of day.
- Sun movement.
- Night lighting.
- Fog/weather.
- Rain.
- Snow.
- Storms.
- Wetness.
- Ice.
- Mud.
- Water interaction.

---

# PRIORITY 17 — Sound and music

### Reference

Sound is a major part of the finished experience.

Steam lists full audio, and the game has:

- engine audio;
- environmental ambience;
- music;
- voice/proximity chat;
- map-specific tapes/audio;
- interaction sounds.

The current Steam listing also shows full audio and subtitles. citeturn6view0

The third-map update explicitly added new music and narrative/audio content. citeturn8search0

### Your current status

**Currently silent.**

Your own file explicitly states this. fileciteturn0file0L297-L298

### Required

Vehicle:

- engine idle;
- acceleration;
- gear shifts;
- clutch;
- tire noise;
- suspension;
- impacts;
- body damage;
- horn;
- winch.

World:

- wind;
- forest;
- water;
- animals;
- rain;
- ambience.

Player:

- footsteps;
- item interactions;
- voice/proximity chat.

Music:

- background music;
- map-specific music;
- cassette/tape system.

---

# PRIORITY 18 — Character cosmetics

### Reference

Character clothing/accessories are an explicit game feature. Steam lists hats, and the game has collectible cosmetics across maps. citeturn6view0turn3search0

### Your current status

**Missing.**

Your plan lists cosmetics. fileciteturn0file0L299-L300

### Required

- Character model.
- Head.
- Body.
- Hats.
- Glasses/accessories.
- Cosmetic inventory.
- Unlocks.
- Persistence.

This should come after the actual character exists.

---

# PRIORITY 19 — Narrative and collectible audio

### Reference

The maps contain environmental narrative and collectible cassette/tape content.

The achievement system includes separate achievements for listening to all tapes in Mabutts Valley and Mt. Yurbuttsk. citeturn3search0

The current third-map guide also documents a separate cassette/audio collection for St. Búttin Bay. citeturn8search3

### Your current status

**Missing.**

### Required

- Tape/cassette objects.
- Audio playback.
- Collection tracking.
- Map-specific narrative.
- Optional environmental storytelling.
- Completion tracking.

This is not needed for the core prototype but greatly increases the feeling of a finished adventure.

---

# PRIORITY 20 — Main menu, settings and controls configuration

### Reference

The finished game has a proper game frontend rather than launching directly into a sandbox.

Relevant systems include:

- main menu;
- host/join;
- options;
- graphics settings;
- audio settings;
- key rebinding;
- voice settings;
- controller support;
- session configuration.

The reference game added rebindable keyboard/mouse controls in a post-launch patch. citeturn1search1

### Your current status

You have:

- pause menu;
- resume;
- update;
- automatic updates;
- quit;
- controls help;
- performance overlay;
- graphics presets.

fileciteturn0file0L189-L203

But you do not yet have the full game frontend.

### Missing

- Main menu.
- New game.
- Continue.
- Map selection.
- Host game.
- Join game.
- Settings.
- Key rebinding.
- Controller configuration.
- Audio.
- Voice.
- Accessibility.
- Save selection.
- Character/cosmetic selection.

---

# PRIORITY 21 — Achievements / progression

The current reference game has **96 Steam achievements**. citeturn6view0

They cover:

- checkpoint progression;
- completing maps;
- repairs/resources;
- winch use;
- medical items;
- cosmetics;
- tapes;
- map-specific mechanics;
- unusual physics events;
- hidden challenges.

Examples include:

- use 20 EpiPens;
- use 100 scraps;
- throw exploding nitroglycerin;
- connect 50 planks;
- use turbo fuel;
- reel in 1 km of winch rope;
- find map cosmetics;
- listen to tapes;
- use snow chains;
- use tractor tube;
- complete map checkpoints.

citeturn3search0

### Your current status

**Missing.**

### Priority

Moderate-to-low.

Achievements should not be built before the underlying systems exist.

---

# PRIORITY 22 — Small interactions and polish

These are important for completeness but should come late.

Potential examples:

- Horn.
- Working dashboard gauges.
- Working doors.
- Working fridge/cabinets.
- Working stove.
- Working sink.
- Physical drinks.
- Cigarettes.
- Grill animation.
- Spare tire mounting.
- Ladder interaction.
- Individual body panels.
- Small props.
- Vehicle mirrors.
- More environmental props.
- Destruction/debris.
- Cosmetic persistence.
- Tutorial prompts.
- Better pause/settings UI.
- Additional accessibility settings.
- Localization.
- Achievements.
- Controller rebinding.
- Steam Cloud.

---

# 5. Controls comparison

## Vehicle controls

Your current vehicle control model is already broadly comparable.

| Function | Detour | RV There Yet? | Gap |
|---|---|---|---|
| Throttle | Yes | Yes | None |
| Brake | Yes | Yes | None |
| Steering | Yes | Yes | None |
| Handbrake | Yes | Yes | Minor control differences |
| Clutch | Yes | Yes | None |
| Manual gearbox | Yes | Yes | None |
| H-pattern | Yes | Yes | Controller implementation differs |
| Automatic gearbox | Yes | Yes | None |
| Engine start | Yes | Yes | None |
| Headlights | Yes | Yes | None |
| Cab camera | Yes | Yes | Different overall player model |
| Chase camera | Yes | Not core equivalent | Your sandbox has more camera emphasis |
| Mouse look | Yes | Yes | None |
| Controller | Yes | Yes | Need complete player/action mapping |
| Key rebinding | No | Yes | Missing |
| Interaction key | No | Yes | Missing |
| Item use | No | Yes | Missing |
| Pick up/drop | No | Yes | Missing |
| Winch controls | No | Yes | Missing |
| Revive | No | Yes | Missing |
| Inventory | No | Yes | Missing |

Your current vehicle controls are therefore not the major problem. The missing controls are predominantly **player/world-interaction controls**.

---

# 6. RV feature comparison

| RV feature | Detour | Reference |
|---|---:|---:|
| Large class-C RV | Yes | Yes |
| Detailed exterior | Yes | Yes |
| Detailed interior | Yes | Yes |
| 5-speed manual | Yes | Yes |
| Reverse | Yes | Yes |
| Clutch | Yes | Yes |
| H-pattern | Yes | Yes |
| Automatic gearbox | Yes | Yes |
| RWD | Yes | Yes |
| Suspension | Yes | Yes |
| Tire grip | Yes | Yes |
| Wheelspin | Yes | Yes |
| Steering geometry | Yes | Yes |
| High centre of mass | Yes | Yes |
| Tipping | Yes | Yes |
| Headlights | Yes | Yes |
| Working winch | No | Yes |
| Winch controller | No | Yes |
| Damage | Partial physics only | Yes |
| Body destruction | No | Yes |
| Tire damage | No | Yes |
| Wheel removal | No | Yes |
| Engine damage | No | Yes |
| Frame damage | No | Yes |
| Repairs | No | Yes |
| Fuel | No | Yes |
| Spare tire gameplay | No | Yes |
| Physical storage | No | Yes |
| Interactive doors | No | Yes |
| Interactive ladder | No | Yes |
| Player seats | No | Yes |
| Walking inside while moving | No | Yes |
| Pushable RV | No | Yes |
| Multi-player shared RV | No | Yes |

This is why the RV itself should not be your main development concern now. It is already one of the strongest parts of the project.

---

# 7. World comparison

| World feature | Detour | Reference |
|---|---:|---:|
| Procedural terrain | Yes | Not the primary structure |
| Deterministic seed | Yes | Not central |
| Endless world | Yes | No |
| Finite route | No | Yes |
| Checkpoints | No | Yes |
| Gas stations | No | Yes |
| Multiple maps | No | Yes |
| Multiple biomes | No | Yes |
| Forests | Yes | Yes |
| Rocks | Yes | Yes |
| Logs/stumps | Yes | Yes |
| Caves | No | Yes |
| Swamps | No | Yes |
| Rivers/lakes | No | Yes |
| Mud | No | Yes |
| Ice | No | Yes |
| Snow | Terrain colour only | Yes |
| Bridges/puzzles | No | Yes |
| Mines | No | Yes |
| Wildlife | No | Yes |
| Weather | No | Yes |
| Day/night | No | Yes |
| Map-specific hazards | No | Yes |
| Narrative locations | No | Yes |
| Collectibles | No | Yes |

---

# 8. Item/system comparison

## Reference items and systems to implement

### Repair

- Scrap Metal.
- Repair Hammer.
- Power Drill.
- Motor Oil.
- Welding Machine.
- Spare tires.

The reference uses different repair methods for body, tires, engine and frame. citeturn4search1

### Survival

- Burger/food.
- Antidote.
- EpiPen.
- Bear Spray.
- First-aid/medical items.

### Vehicle/problem solving

- Winch Controller.
- Winch cable.
- Planks.
- Jerry cans/fuel.
- Spare tires.

### Map-specific

- Snow chains.
- Snowballs.
- Inner/tractor tubes.
- Jet Fuel/turbo fuel.
- Nitroglycerin.
- Map 3-specific beach/coconut/paddle items.

Jet Fuel, for example, is a map-specific consumable that temporarily increases RV acceleration and speed substantially. citeturn2search3

### Cosmetic

- Hats.
- Glasses/accessories.
- Map-specific cosmetics.

---

# 9. Map-by-map target feature set

## Map 1 — Mabutts Valley equivalent

Your equivalent should eventually contain:

- Start area.
- Forest.
- Swamp.
- Caves.
- Mines.
- Bears.
- Snakes.
- Eagles.
- Mud/water.
- Rocks.
- Bridges.
- Cliffs.
- Checkpoints.
- Gas stations.
- Repair stations.
- Supplies.
- Plank sections.
- Winch sections.
- Narrative/cassettes.
- Cosmetics.
- Final route to Route 65.

The achievement structure confirms at least 16 checkpoints plus the map completion state. citeturn3search0

## Map 2 — Mt. Yurbuttsk equivalent

Target:

- High mountain terrain.
- Snow.
- Ice.
- Snow chains.
- Snowball mechanics.
- Snow leopard.
- Ice-related obstacles.
- Inner/tractor tube.
- Mountain traversal.
- Additional narrative.
- Map cosmetics.
- Map-specific audio.
- Checkpoints.
- Final completion.

The reference's achievement list confirms these systems exist as actual gameplay, rather than merely environmental decoration. citeturn3search0

## Map 3 — St. Búttin Bay equivalent

Target:

- Beach/coastal environment.
- Islands/boats or equivalent traversal.
- Water crossings.
- New wildlife.
- New tools.
- New items.
- Coconut drinks.
- Beach paddles.
- New narrative.
- New music.
- New checkpoint route.
- Cosmetics.
- Tapes.
- Map-specific puzzles.

The official 10 September 2026 update confirms the new map and its new animals/items/tools/narrative/music and beach-specific items. citeturn8search0

---

# 10. The first-person requirement

This deserves special emphasis.

Your current game has a **driver's-eye camera**, but that does not fulfil the reference game's player-character model.

The target architecture should be:

```text
Player
├── Character body
├── First-person camera
├── Hands / held-item socket
├── Interaction ray
├── Inventory
├── Health
├── Movement
├── Vehicle interaction
├── Item interaction
└── Network identity
```

Then:

```text
Player
   ↓
enters RV
   ↓
occupies seat
   ↓
drives
   ↓
stops
   ↓
gets out
   ↓
walks to obstacle
   ↓
gets item/tool
   ↓
solves obstacle
   ↓
returns to RV
   ↓
continues driving
```

That loop is much closer to the actual structure of *RV There Yet?* than simply adding more terrain.

---

# 11. Recommended development order

If the goal is to make Detour increasingly resemble the reference game, I would implement in roughly this order:

## Phase 1 — Player foundation

1. First-person player controller.
2. Player collision.
3. Walking/running.
4. Interaction ray.
5. Pickup/drop.
6. Held objects.
7. Player animation/visual body.

## Phase 2 — RV interaction

8. Enter/exit RV.
9. Driver seat.
10. Passenger seats.
11. Interior collision.
12. Walking inside moving RV.
13. Doors.
14. Ladder.
15. Roof access.

## Phase 3 — Core physical problem solving

16. Winch.
17. Winch controller.
18. Cable physics.
19. Attachments.
20. Pushing RV.
21. Planks.
22. Object placement.

## Phase 4 — Game structure

23. Finite route.
24. Start location.
25. Checkpoints.
26. Gas stations.
27. Save/reload.
28. Destination.
29. Win state.
30. Failure state.

## Phase 5 — RV survival

31. Body damage.
32. Tire damage.
33. Engine damage.
34. Frame damage.
35. Repair hammer.
36. Scrap.
37. Drill.
38. Motor oil.
39. Welding.
40. Spare tires.
41. Fuel.
42. Jerry cans.

## Phase 6 — Inventory

43. Player inventory.
44. RV storage.
45. Tool storage.
46. Physical item placement.
47. Consumables.
48. Plank storage.
49. Spare tire storage.

## Phase 7 — Multiplayer

50. Lobby.
51. Player replication.
52. Shared RV.
53. Item replication.
54. Winch replication.
55. Damage replication.
56. Checkpoint synchronisation.
57. Revive.
58. Disconnect/reconnect.
59. Proximity voice.

## Phase 8 — Survival

60. Health.
61. Downed state.
62. EpiPen.
63. Food.
64. Antidote.
65. Wildlife.
66. Bear spray.
67. Environmental hazards.

## Phase 9 — World/game variety

68. Authored obstacle templates.
69. Biomes.
70. Water.
71. Mud.
72. Ice.
73. Caves.
74. Swamps.
75. Mountains.
76. Weather.
77. Day/night.
78. Map-specific hazards.

## Phase 10 — Content/polish

79. Audio.
80. Music.
81. Cassettes.
82. Narrative.
83. Cosmetics.
84. Main menu.
85. Settings.
86. Key rebinding.
87. Achievements.
88. Localization.
89. Accessibility.
90. Additional small interactions.

---

# 12. What I would NOT prioritise yet

Several things in your current project are technically useful but should not distract from the gameplay gap.

## Do not prioritise more procedural scenery yet

You already have:

- trees;
- rocks;
- stumps;
- logs;
- terrain;
- streaming;
- LOD;
- deterministic generation.

Adding another 20 rock variants will not move the game substantially closer to the reference until players can leave the RV and interact with them.

## Do not prioritise more vehicle physics yet

Your current handling is already detailed:

- suspension;
- tire slip;
- load;
- RWD;
- Ackermann;
- clutch;
- gearbox;
- engine;
- tipping.

The next useful vehicle work is **gameplay interaction**, especially damage, winching and repair.

## Do not prioritise endless-world scale

The reference game is fundamentally about navigating a designed journey.

A smaller finite route with excellent obstacles is more valuable to the intended gameplay than an enormous infinite map with nothing to accomplish.

## Do not prioritise graphics before interaction

Your current renderer/performance work is already strong.

The reference experience depends much more on:

- physical interaction;
- co-op;
- obstacles;
- items;
- repairs;
- survival;
- route progression.

---

# 13. What makes your project technically interesting compared with the reference

There are also areas where Detour currently has a technical direction that is arguably different from the reference rather than simply behind it.

## Deterministic procedural world

Your world is explicitly designed to be deterministic across:

- macOS Apple Silicon;
- Linux;
- Windows x86_64.

The same seed produces bit-identical terrain, trees and props, and CI checks golden hashes. fileciteturn0file0L71-L76

That is an excellent foundation for multiplayer.

## Infinite world streaming

Your 128 m chunks and background generation provide a technically clean basis for an effectively unlimited world. fileciteturn0file0L83-L87

The reference game's finite maps mean this is not required to reproduce it, but it gives Detour an opportunity to combine:

**RV There Yet? gameplay + deterministic procedural generation**

rather than simply recreating its authored maps.

## Built-in update system

Your automatic update system is already more developed than many small open-source prototypes:

- release checking;
- background download;
- SHA-256 verification;
- platform-specific replacement;
- restart-to-update;
- auto-update toggle.

fileciteturn0file0L205-L227

This should be kept, but it is not part of the gameplay gap.

---

# 14. The most important architectural change

The current architecture can be thought of as:

```text
WORLD
  ↓
RV
  ↓
DRIVE FOREVER
```

The target architecture should become:

```text
GAME SESSION
    ↓
TRIP
    ↓
MAP
    ↓
CHECKPOINT
    ↓
OBSTACLE
    ↓
PLAYER INTERACTION
    ↓
ITEM / TOOL
    ↓
RV PHYSICS
    ↓
DAMAGE / SURVIVAL
    ↓
NEXT CHECKPOINT
    ↓
DESTINATION
```

For multiplayer:

```text
                 SESSION
                    |
        +-----------+-----------+
        |           |           |
      Player      Player      Player
        |           |           |
        +-----------+-----------+
                    |
                 ONE RV
                    |
          +---------+---------+
          |         |         |
       Physics    Damage    Inventory
          |         |         |
          +---------+---------+
                    |
                 WORLD
                    |
               CHECKPOINTS
                    |
                 OBJECTIVE
```

This is the fundamental shift needed.

---

# 15. Minimal "vertical slice" target

Before implementing three complete maps, I would aim for one tiny but complete route.

For example:

```text
START CAMP
   ↓
forest road
   ↓
mud hole
   ↓
broken bridge
   ↓
winch section
   ↓
small gas station
   ↓
final hill
   ↓
FINISH
```

With:

- 1–4 players.
- First-person character.
- Enter/exit RV.
- Driver/passenger seats.
- Pickup/drop.
- One winch.
- Planks.
- One damage type.
- One repair item.
- One checkpoint.
- One save.
- One consumable.
- One wildlife threat.
- One final objective.

If this is fun, the rest of the game becomes a content problem.

If this is not fun, adding three biomes will not fix it.

---

# 16. Feature status summary

Legend:

- **DONE** = clearly implemented in the current snapshot.
- **PARTIAL** = infrastructure/visual representation exists but the actual gameplay system is missing.
- **MISSING** = not implemented.
- **PLANNED** = explicitly identified in your own plan.
- ✅ **DONE (Mn)** = implemented since this comparison, in milestone *n* (see CURRENT_GAME.md).

| System | Status |
|---|---|
| RV model | DONE |
| RV interior | DONE |
| Manual gearbox | DONE |
| H-pattern | DONE |
| Clutch | DONE |
| Automatic gearbox | DONE |
| Engine simulation | DONE |
| Suspension | DONE |
| Tire model | DONE |
| Steering | DONE |
| Brakes | DONE |
| Handbrake | DONE |
| Headlights | DONE |
| Chase camera | DONE |
| Cab camera | DONE |
| Controller driving | DONE |
| Procedural terrain | DONE |
| Deterministic seeds | DONE |
| Infinite streaming | DONE |
| Trees | DONE |
| Rocks | DONE |
| Stumps/logs | DONE |
| Terrain collision | DONE |
| Recovery | DONE |
| HUD | DONE |
| Pause menu | DONE |
| Graphics presets | DONE |
| Auto-update | DONE |
| On-foot character | ✅ DONE (M1) |
| First-person on-foot gameplay | ✅ DONE (M1) |
| Getting into RV | ✅ DONE (M1) |
| Getting out of RV | ✅ DONE (M1) |
| Walking inside moving RV | ✅ DONE (M1) |
| Seats/passengers | ✅ DONE (M1) |
| Item pickup | ✅ DONE (M1) |
| Item carrying | ✅ DONE (M1) |
| Item throwing | ✅ DONE (M1) |
| Inventory | ✅ DONE (M4: 4-slot hotbar) |
| RV storage | ✅ DONE (M7: 31 physical slots: plank rack, spare mount, can holders, tool wall, fridge, shelf, bed, cup holders; saved) |
| Winch | ✅ DONE (M2) |
| Winch controller | ✅ DONE (M2) |
| Planks | ✅ DONE (M2) |
| Push RV | ✅ DONE (M2) |
| Finite route | ✅ DONE (M3; M10: the road runs along a walled valley, closed behind the camp and past home: no driving off into nowhere; M11: 4–5.5 km short trips on a surveyed, winding road through a wide valley that pinches at obstacles, telephone poles along it) |
| Bridges and jump puzzles | ✅ DONE (M11: timber bridges with a hole to jump off a kicker or plank over, two-beam crossings to line up on, gully jumps, steep hills with a tempting side track; generator-checked and driven in tests) |
| Places to explore | ✅ DONE (M11: cabins, fire lookout towers, wrecks, lookout hills off the road, with supplies) |
| Objective | ✅ DONE (M3: reach home) |
| Checkpoints | ✅ DONE (M3) |
| Gas stations | ✅ DONE (M3: checkpoint, save, restock; M4: pump and welder; M11: a forecourt lane between the pump islands to pull the RV into) |
| Respawn at the last checkpoint | ✅ DONE (M11: a wrecked RV, one lying down a ravine, or everyone down goes back to the last stop in the condition it left in, +30 min) |
| Saving/checkpoint progress | ✅ DONE (M3; M10: autosave every minute and on quit, resuming mid-road with the whole world state; saved trips listed on the main menu) |
| Discovery over hand-holding | ✅ DONE (M10: no warning signs, bridge planks hidden in the trees, terse prompts that never explain the solution) |
| RV body damage | ✅ DONE (M4: 16 detachable parts) |
| Tire damage | ✅ DONE (M4) |
| Engine damage | ✅ DONE (M4: oil, heat, seizing) |
| Frame damage | ✅ DONE (M4) |
| Repairs | ✅ DONE (M4: hammer+scrap, refit, drill, oil, welder; M11: the hammer swings three times, sparks off the panel) |
| Health / RV condition HUD | ✅ DONE (M11: a status panel with your health and the RV's condition as one bar of coloured systems, each with an icon) |
| Spare tires | ✅ DONE (M4) |
| Fuel | ✅ DONE (M4) |
| Jerry cans | ✅ DONE (M4) |
| Player health | ✅ DONE (M5: falls, RV, wildlife) |
| Downed state | ✅ DONE (M5: crawl, 60 s bleed-out) |
| Revive | ✅ DONE (M5: EpiPen, self or teammate) |
| Food | ✅ DONE (M5: burgers, soda, patties cooked on grills/stove) |
| Antidote | ✅ DONE (M5: snake venom) |
| Wildlife | ✅ DONE (M5: bears, rattlesnakes, eagles; placeholder looks) |
| Bear spray | ✅ DONE (M5) |
| Multiple biomes | ✅ DONE (M8: woods, bayou, canyon, mountain pass; procedural, placeholder looks) |
| Rivers/lakes | ✅ DONE (M8: river fords, ponds; wading, engine flooding, swimming) |
| Mud | ✅ DONE (M3) |
| Ice | ✅ DONE (M8: frozen ponds on the road, frozen lakes; planks give grip) |
| Caves | ✅ DONE (M8: roadside caves with supplies; placeholder rock) |
| Weather | ✅ DONE (M9: seeded spells: rain, snow, fog, storms; wet grip, gusts) |
| Day/night | ✅ DONE (M9: clock, moving sun/moon, dusk, night, flashlight) |
| Multiplayer lobby | ✅ DONE (M6: main menu host/join; LAN list, direct IP, relay room codes) |
| Player replication | ✅ DONE (M6) |
| Shared RV networking | ✅ DONE (M6: driver simulates, ownership handoff) |
| Item networking | ✅ DONE (M6: host-authoritative, optimistic pickups) |
| Winch networking | ✅ DONE (M6) |
| Proximity voice | MISSING |
| Character cosmetics | MISSING |
| Narrative | MISSING |
| Cassettes/tapes | MISSING |
| Music | MISSING |
| Sound effects | MISSING |
| Main menu | ✅ DONE (M6) |
| Settings | ✅ DONE (M11: display, interface scale, graphics quality and resolution scale, FOV, look sensitivity, volumes) |
| Key rebinding | MISSING |
| Achievements | MISSING |

---

# 17. Final assessment

The current project should be viewed as:

**A very developed RV driving/physics sandbox that has not yet implemented the actual adventure game layer.**

That is not a criticism of the current implementation. The vehicle system, deterministic terrain and streaming are substantial foundations.

The biggest mistake would be to interpret the remaining work as "add more RV features".

The next major milestone should instead be:

> **Put a real first-person human into the RV and make the human able to leave it, pick something up, use it to solve a physical obstacle, get back into the RV and continue toward a checkpoint.**

Once that loop works, the project starts resembling *RV There Yet?* in gameplay rather than merely in subject matter.

The strongest long-term direction would then be to combine the reference game's cooperative physical problem-solving loop with your own distinctive technical features:

- deterministic procedural maps;
- seed sharing;
- guaranteed-solvable procedural obstacles;
- cross-platform world determinism;
- efficient streaming;
- open-source development;
- potentially larger/generated routes.

That would make **Detour** more than a direct clone: it could use the same core gameplay philosophy while having its own world-generation and technical identity.

---

# Sources

## Your implementation

- `CURRENT_GAME.md` — supplied project snapshot, updated 28 September 2026. fileciteturn0file0L1-L8
- Controls and RV implementation. fileciteturn0file0L13-L37
- World generation and streaming. fileciteturn0file0L69-L102
- RV model and handling. fileciteturn0file0L106-L179
- Interface and update system. fileciteturn0file0L189-L227
- Future gameplay systems. fileciteturn0file0L257-L300

## Reference game

- Steam store page: core objective, four-player RV, winch, proximity chat, online co-op, hats, cooking and cigarettes. citeturn6view0
- Official/community wiki: RV mechanics, storage, damage and shared vehicle systems. citeturn0search1
- Official/community wiki: Mabutts Valley. citeturn1search0
- Official/community wiki: achievements and checkpoint/map progression. citeturn3search0
- Repair-system reference: body, tires, engine and frame repair. citeturn4search1
- Official September 2026 Map 3 update: St. Búttin Bay, animals, items, tools, narrative, music and beach items. citeturn8search0
- Current Steam listing: St. Búttin Bay available as of September 2026. citeturn5search0
- Current community achievement/route guide documenting St. Búttin Bay checkpoints, tapes and cosmetics. citeturn8search3
