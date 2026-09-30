# Third-party assets

All assets below are **CC0** (public domain) from [Poly Haven](https://polyhaven.com).
Credit is not required, but we give it gladly. Models built from them live in
`game/assets/models/` and are made by `tools/assets/blender/*.py`.

| Used as | Asset | Authors |
|---|---|---|
| texture `bark` | [Pine Bark](https://polyhaven.com/a/pine_bark) | Dimitrios Savva |
| texture `counter` | [Wood Table Worn](https://polyhaven.com/a/wood_table_worn) | Dimitrios Savva, Rico Cilliers |
| texture `dark_metal` | [Metal Plate 02](https://polyhaven.com/a/metal_plate_02) | Rob Tuytel |
| texture `fabric` | [Fabric Pattern 07](https://polyhaven.com/a/fabric_pattern_07) | Rob Tuytel |
| texture `fabric_plaid` | [Fabric Pattern 05](https://polyhaven.com/a/fabric_pattern_05) | Rob Tuytel |
| texture `floor` | [Laminate Floor 02](https://polyhaven.com/a/laminate_floor_02) | Dario Barresi, Charlotte Baglioni |
| texture `ground_dirt` | [Forest Ground 01](https://polyhaven.com/a/forrest_ground_01) | Rob Tuytel |
| texture `ground_grass` | [Leafy Grass](https://polyhaven.com/a/leafy_grass) | Charlotte Baglioni |
| texture `ground_rock` | [Rock Face 03](https://polyhaven.com/a/rock_face_03) | Dario Barresi, Rico Cilliers |
| texture `ground_snow` | [Snow 02](https://polyhaven.com/a/snow_02) | Rob Tuytel |
| texture `metal` | [Blue Metal Plate](https://polyhaven.com/a/blue_metal_plate) | Rob Tuytel |
| texture `needles` | [Forest Leaves 03](https://polyhaven.com/a/forest_leaves_03) | Rob Tuytel, Dimitrios Savva |
| texture `paint` | [Green Metal Rust](https://polyhaven.com/a/green_metal_rust) | Rob Tuytel |
| texture `plank` | [Weathered Brown Planks](https://polyhaven.com/a/weathered_brown_planks) | Dimitrios Savva, Rico Cilliers |
| texture `rubber` | [Rubberized Track](https://polyhaven.com/a/rubberized_track) | Charlotte Baglioni |
| texture `wall_panel` | [Japanese Cedar Planks](https://polyhaven.com/a/japanese_cedar_planks) | Charlotte Baglioni, Rico Cilliers |
| model `log` | [Dead Tree Trunk](https://polyhaven.com/a/dead_tree_trunk) | Rob Tuytel |
| model `rocks_a` | [Rock Moss Set 01](https://polyhaven.com/a/rock_moss_set_01) | Kless Gyzen |
| model `rocks_b` | [Rock Moss Set 02](https://polyhaven.com/a/rock_moss_set_02) | Kless Gyzen |
| model `rocks_c` | [Boulder 01](https://polyhaven.com/a/boulder_01) | Rico Cilliers |
| model `stump` | [Tree Stump 01](https://polyhaven.com/a/tree_stump_01) | Rob Tuytel |

## Kenney (www.kenney.nl), CC0

Low-poly models from Kenney's kits (Creative Commons Zero), fetched by
`tools/assets/fetch_kenney.py` into `game/assets/models/kenney/<kit>/`:
Nature Kit (tent, campfire, log stack, bushes, flowers, mushrooms, grass), Survival Kit
(bedroll, signposts, workbench, barrel, crate, hammer), City Kit Suburban (house, fence,
driveway) and City Kit Commercial (shop, awning).

## Sounds

Everything in `game/assets/audio/` (Ogg Vorbis) is one of two kinds. The check that every
file is listed here is `game/tests/audio.gd`; the measurements behind "does it sound right"
(peaks, loudness, loop seams, spectra) are `tools/audio/check_sounds.py`.

**Birdsong: real recordings, CC0.** Songs of a common blackbird and an Eurasian blackcap from
[BigSoundBank](https://bigsoundbank.com) (recorded in France's Centre region, spring
mornings). Each sound's page says *"CC0 (public domain): Free and royalty-free"*, and the
[licence page](https://bigsoundbank.com/licenses.html) spells it out: Creative Commons CC0 1.0
Universal (share, adapt, use commercially, "without any restrictions, without asking
permission"). Credit is not required, but we give it gladly. `tools/audio/fetch_birds.py`
downloads them, checks that line again, and tidies them for the game (mono, rumble and the
sharpest ticks filtered out, trimmed, levelled).

| File | Sound | Author | Source page |
|---|---|---|---|
| `audio/birds/blackbird_1.ogg` | Common Blackbird #3 | Le tiroir du fond | [s3476](https://bigsoundbank.com/common-blackbird-3-s3476.html) |
| `audio/birds/blackbird_2.ogg` | Common Blackbird #5 | Le tiroir du fond | [s3478](https://bigsoundbank.com/common-blackbird-5-s3478.html) |
| `audio/birds/blackbird_3.ogg` | Common Blackbird #6 | Le tiroir du fond | [s3479](https://bigsoundbank.com/common-blackbird-6-s3479.html) |
| `audio/birds/blackbird_4.ogg` | Common Blackbird #7 | Le tiroir du fond | [s3480](https://bigsoundbank.com/common-blackbird-7-s3480.html) |
| `audio/birds/blackbird_5.ogg` | Common Blackbird #11 | Le tiroir du fond | [s3484](https://bigsoundbank.com/common-blackbird-11-s3484.html) |
| `audio/birds/blackbird_6.ogg` | Common Blackbird #12 | Le tiroir du fond | [s3485](https://bigsoundbank.com/common-blackbird-12-s3485.html) |
| `audio/birds/blackbird_7.ogg` | Common Blackbird #14 | Le tiroir du fond | [s3487](https://bigsoundbank.com/common-blackbird-14-s3487.html) |
| `audio/birds/blackbird_8.ogg` | Common Blackbird #15 | Le tiroir du fond | [s3488](https://bigsoundbank.com/common-blackbird-15-s3488.html) |
| `audio/birds/blackbird_9.ogg` | Common Blackbird #17 | Le tiroir du fond | [s3490](https://bigsoundbank.com/common-blackbird-17-s3490.html) |
| `audio/birds/blackbird_10.ogg` | Common Blackbird #22 | Le tiroir du fond | [s3495](https://bigsoundbank.com/common-blackbird-22-s3495.html) |
| `audio/birds/blackbird_11.ogg` | Common Blackbird #23 | Le tiroir du fond | [s3496](https://bigsoundbank.com/common-blackbird-23-s3496.html) |
| `audio/birds/blackcap_1.ogg` | Eurasian blackcap #1 | Le tiroir du fond | [s3466](https://bigsoundbank.com/eurasian-blackcap-1-s3466.html) |
| `audio/birds/blackcap_2.ogg` | Eurasian blackcap #5 | Le tiroir du fond | [s3470](https://bigsoundbank.com/eurasian-blackcap-5-s3470.html) |
| `audio/birds/blackcap_3.ogg` | Eurasian blackcap #6 | Le tiroir du fond | [s3471](https://bigsoundbank.com/eurasian-blackcap-6-s3471.html) |

**Everything else: made for Detour**, synthesized from noise and sine waves by
`tools/audio/make_sounds.py` (fixed seeds: the same command gives the same sounds; nothing is
sampled from anywhere). Author: the Detour project; same licence as the game's own art (see the
README). The engine loops are the RV's V8 at four speeds (crossfaded and re-pitched in game).

| File | Sound |
|---|---|
| `audio/rv/engine_idle.ogg` | Engine loop at 750 rpm (4 s) |
| `audio/rv/engine_low.ogg` | Engine loop at 1320 rpm (3 s) |
| `audio/rv/engine_mid.ogg` | Engine loop at 2100 rpm (4 s) |
| `audio/rv/engine_high.ogg` | Engine loop at 3400 rpm (3 s) |
| `audio/rv/starter_crank.ogg` | Starter motor and the engine turning over (loop) |
| `audio/rv/engine_start.ogg` | The engine catching and settling to idle |
| `audio/rv/engine_stall.ogg` | The engine stalling |
| `audio/rv/gear_clunk.ogg` | The gearbox going into gear |
| `audio/rv/tire_road.ogg` | Tires humming on the road (loop) |
| `audio/rv/tire_gravel.ogg` | Tires crunching on gravel and dirt (loop) |
| `audio/rv/landing_thud.ogg` | The body landing on its springs |
| `audio/rv/crash.ogg` | The RV hitting something |
| `audio/rv/door_open.ogg` | The door latch and swing |
| `audio/rv/door_close.ogg` | The door shutting |
| `audio/tools/hammer_clank_1.ogg` | A hammer blow on metal (three variants) |
| `audio/tools/hammer_clank_2.ogg` | " |
| `audio/tools/hammer_clank_3.ogg` | " |
| `audio/ambience/wind_bed.ogg` | Wind, a low breathing rush (loop, also the rush of air at speed) |
| `audio/ambience/wind_trees.ogg` | Wind in leaves and needles (loop) |
| `audio/ambience/rain_loop.ogg` | Steady rain (loop) |
| `audio/ambience/rain_roof.ogg` | Rain drumming on the RV's roof, heard inside (loop) |
| `audio/ambience/thunder_1.ogg` | Distant thunder |
| `audio/ambience/thunder_2.ogg` | Distant thunder, shorter |
| `audio/ambience/crickets_loop.ogg` | Crickets at night (loop) |
| `audio/rv/horn.ogg` | The RV's horn, two tones (loop, fades with the button) |
| `audio/rv/winch_motor.ogg` | The winch motor and gears (loop, pitch rises with the load) |
| `audio/rv/winch_snap.ogg` | The winch rope snapping |
| `audio/rv/part_fall.ogg` | A panel or wheel coming off and clanging on the road |
| `audio/rv/tape_insert.ogg` | A cassette going into the tape deck |
| `audio/tools/winch_hook.ogg` | The winch hook clinking onto an anchor |
| `audio/tools/drill_bolt.ogg` | The drill running a wheel bolt in |
| `audio/tools/weld_zap.ogg` | The welder's arc |
| `audio/tools/pour.ogg` | Liquid pouring from a can or bottle (loop, played once) |
| `audio/tools/plank_lay.ogg` | A plank set down |
| `audio/items/pickup.ogg` | Picking something up |
| `audio/items/drop.ogg` | Something dropped or landing (played louder the harder it lands) |
| `audio/items/throw.ogg` | Throwing something (a whoosh) |
| `audio/items/eat.ogg` | Eating: bites and a swallow |
| `audio/items/drink.ogg` | A can opened and drunk |
| `audio/items/epipen.ogg` | The EpiPen's click and hiss |
| `audio/items/spray.ogg` | A puff of bear spray |
| `audio/steps/step_grass_1.ogg` | A footstep on grass (variant 1) |
| `audio/steps/step_grass_2.ogg` | " |
| `audio/steps/step_grass_3.ogg` | " |
| `audio/steps/step_grass_4.ogg` | " |
| `audio/steps/step_dirt_1.ogg` | A footstep on dirt (variant 1) |
| `audio/steps/step_dirt_2.ogg` | " |
| `audio/steps/step_dirt_3.ogg` | " |
| `audio/steps/step_dirt_4.ogg` | " |
| `audio/steps/step_rock_1.ogg` | A footstep on rock (variant 1) |
| `audio/steps/step_rock_2.ogg` | " |
| `audio/steps/step_rock_3.ogg` | " |
| `audio/steps/step_rock_4.ogg` | " |
| `audio/steps/step_snow_1.ogg` | A footstep on crunching snow (variant 1) |
| `audio/steps/step_snow_2.ogg` | " |
| `audio/steps/step_snow_3.ogg` | " |
| `audio/steps/step_snow_4.ogg` | " |
| `audio/steps/step_ice_1.ogg` | A footstep on ice (variant 1) |
| `audio/steps/step_ice_2.ogg` | " |
| `audio/steps/step_ice_3.ogg` | " |
| `audio/steps/step_ice_4.ogg` | " |
| `audio/steps/step_wood_1.ogg` | A footstep on a plank (variant 1) |
| `audio/steps/step_wood_2.ogg` | " |
| `audio/steps/step_wood_3.ogg` | " |
| `audio/steps/step_wood_4.ogg` | " |
| `audio/steps/step_rvfloor_1.ogg` | A footstep on the RV's floor (variant 1) |
| `audio/steps/step_rvfloor_2.ogg` | " |
| `audio/steps/step_rvfloor_3.ogg` | " |
| `audio/steps/step_rvfloor_4.ogg` | " |
| `audio/steps/step_water_1.ogg` | A footstep on wading through water (variant 1) |
| `audio/steps/step_mud_1.ogg` | A footstep on mud (variant 1) |
| `audio/steps/step_water_2.ogg` | " |
| `audio/steps/step_mud_2.ogg` | " |
| `audio/steps/step_water_3.ogg` | " |
| `audio/steps/step_mud_3.ogg` | " |
| `audio/steps/splash.ogg` | Stepping or falling into water |
| `audio/wildlife/rattle.ogg` | A rattlesnake's rattle (loop) |
| `audio/wildlife/snake_hiss.ogg` | A snake striking |
| `audio/wildlife/bear_roar.ogg` | A bear rearing up and roaring |
| `audio/wildlife/bear_swipe.ogg` | A bear's paw swiping |
| `audio/wildlife/eagle_screech.ogg` | An eagle's cry |
| `audio/ui/chime.ogg` | Reaching a gas station |
| `audio/ui/toast.ogg` | Earning an achievement |
| `audio/ui/home.ogg` | Getting home |
