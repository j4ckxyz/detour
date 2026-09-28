//! `rvgen-cli`: poke the world generator without Godot.
//!
//! ```text
//! rvgen-cli new [short|medium|long]          print a fresh seed code
//! rvgen-cli hash <code> <cx> <cz>            chunk content hash
//! rvgen-cli png <code> <out.png> [radius]    shaded-relief preview of (2r)² chunks around 0,0
//! rvgen-cli bench [chunks]                   time heightfield + mesh + scatter per chunk
//! rvgen-cli golden                           print the golden table for tests/golden.rs
//! ```

use std::fs::File;
use std::io::BufWriter;
use std::process::ExitCode;
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use rvgen::hash::Fnv64;
use rvgen::mesh::{LOD_STEPS, chunk_mesh, ground_color};
use rvgen::{CHUNK_SIZE, ChunkCoord, SeedCode, TripLength, World, scatter};

/// Fixed inputs for the cross-platform golden test. Changing these requires regenerating
/// `native/rvgen/tests/golden.rs`.
const GOLDEN_SEEDS: [(TripLength, u64); 3] = [
    (TripLength::Short, 1),
    (TripLength::Medium, 0x00AB_CDEF),
    (TripLength::Long, 0xFF_FFFF_FFFF),
];
const GOLDEN_CHUNKS: [(i32, i32); 4] = [(0, 0), (1, -1), (-5, 3), (40, -80)];

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let result = match args.first().map(String::as_str) {
        Some("new") => cmd_new(args.get(1).map(String::as_str)),
        Some("hash") => cmd_hash(&args[1..]),
        Some("png") => cmd_png(&args[1..]),
        Some("bench") => cmd_bench(args.get(1).map(String::as_str)),
        Some("golden") => cmd_golden(),
        _ => Err(USAGE.to_string()),
    };
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("{e}");
            ExitCode::FAILURE
        }
    }
}

const USAGE: &str = "usage: rvgen-cli <new [short|medium|long] | hash <code> <cx> <cz> | \
png <code> <out.png> [radius] | bench [chunks] | golden>";

fn parse_trip(s: Option<&str>) -> Result<TripLength, String> {
    match s.unwrap_or("short") {
        "short" => Ok(TripLength::Short),
        "medium" => Ok(TripLength::Medium),
        "long" => Ok(TripLength::Long),
        other => Err(format!("unknown trip length '{other}'")),
    }
}

fn world_from(code: &str) -> Result<World, String> {
    let code = SeedCode::parse(code).map_err(|e| e.to_string())?;
    World::new(code).map_err(|e| e.to_string())
}

fn arg<T: std::str::FromStr>(args: &[String], i: usize, name: &str) -> Result<T, String> {
    args.get(i)
        .ok_or_else(|| format!("missing <{name}>\n{USAGE}"))?
        .parse()
        .map_err(|_| format!("bad <{name}>"))
}

fn cmd_new(trip: Option<&str>) -> Result<(), String> {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| e.to_string())?
        .as_nanos() as u64;
    println!("{}", SeedCode::from_entropy(parse_trip(trip)?, nanos));
    Ok(())
}

fn cmd_hash(args: &[String]) -> Result<(), String> {
    let world = world_from(&arg::<String>(args, 0, "code")?)?;
    let coord = ChunkCoord::new(arg(args, 1, "cx")?, arg(args, 2, "cz")?);
    println!("{:016x}", world.heightfield(coord).content_hash());
    Ok(())
}

fn cmd_png(args: &[String]) -> Result<(), String> {
    let world = world_from(&arg::<String>(args, 0, "code")?)?;
    let out: String = arg(args, 1, "out.png")?;
    let radius: i32 = args
        .get(2)
        .map_or(Ok(4), |s| s.parse().map_err(|_| "bad radius"))?;
    let size = (2 * radius * CHUNK_SIZE) as usize;
    let mut rgb = vec![0u8; size * size * 3];
    for cz in -radius..radius {
        for cx in -radius..radius {
            let hf = world.heightfield(ChunkCoord::new(cx, cz));
            for z in 0..CHUNK_SIZE as usize {
                for x in 0..CHUNK_SIZE as usize {
                    let h = hf.height_m(x, z);
                    // 3x vertical exaggeration so gentle slopes read in the preview.
                    let dx = 3.0 * (hf.height_m(x + 1, z) - h);
                    let dz = 3.0 * (hf.height_m(x, z + 1) - h);
                    let len = (dx * dx + 1.0 + dz * dz).sqrt();
                    let ny = 1.0 / len;
                    // Light from the north-west.
                    let shade = (0.55 + 0.45 * ((-dx - dz) / len * 0.7 + ny * 0.7)).clamp(0.2, 1.2);
                    let (ox, oz) = ChunkCoord::new(cx, cz).origin();
                    let tint = world
                        .terrain()
                        .tint((ox + x as i32) as f32, (oz + z as i32) as f32);
                    let c = ground_color(h, ny, tint);
                    let px = ((cx + radius) * CHUNK_SIZE) as usize + x;
                    let pz = ((cz + radius) * CHUNK_SIZE) as usize + z;
                    let i = (pz * size + px) * 3;
                    for k in 0..3 {
                        rgb[i + k] = (c[k] * shade * 255.0).clamp(0.0, 255.0) as u8;
                    }
                }
            }
        }
    }
    let file = File::create(&out).map_err(|e| format!("{out}: {e}"))?;
    let mut enc = png::Encoder::new(BufWriter::new(file), size as u32, size as u32);
    enc.set_color(png::ColorType::Rgb);
    enc.set_depth(png::BitDepth::Eight);
    enc.write_header()
        .and_then(|mut w| w.write_image_data(&rgb))
        .map_err(|e| e.to_string())?;
    println!("wrote {out} ({size}x{size} px, 1 px = 1 m)");
    Ok(())
}

fn cmd_bench(chunks: Option<&str>) -> Result<(), String> {
    let count: i32 = chunks.map_or(Ok(64), |s| s.parse().map_err(|_| "bad chunk count"))?;
    let world = World::new(SeedCode::new(TripLength::Short, 42)).map_err(|e| e.to_string())?;
    let side = (count as f32).sqrt().ceil() as i32;
    let coords: Vec<_> = (0..count)
        .map(|i| ChunkCoord::new(i % side, i / side))
        .collect();

    let t = Instant::now();
    let fields: Vec<_> = coords.iter().map(|&c| world.heightfield(c)).collect();
    let hf_ms = t.elapsed().as_secs_f64() * 1000.0 / count as f64;

    let mut mesh_ms = Vec::new();
    for step in LOD_STEPS {
        let t = Instant::now();
        let mut verts = 0;
        for hf in &fields {
            verts += chunk_mesh(&world, hf, step).positions.len();
        }
        mesh_ms.push((
            step,
            t.elapsed().as_secs_f64() * 1000.0 / count as f64,
            verts / fields.len(),
        ));
    }

    let t = Instant::now();
    let tree_lists: Vec<_> = fields.iter().map(|hf| scatter::trees(&world, hf)).collect();
    let tree_ms = t.elapsed().as_secs_f64() * 1000.0 / count as f64;
    let trees: usize = tree_lists.iter().map(Vec::len).sum();

    let t = Instant::now();
    let mut kinds = [0usize; 4];
    for (hf, trees) in fields.iter().zip(&tree_lists) {
        for p in scatter::props(&world, hf, trees) {
            kinds[p.kind as usize] += 1;
        }
    }
    let props_ms = t.elapsed().as_secs_f64() * 1000.0 / count as f64;

    println!("{count} chunks, single thread (budget: < 4 ms per chunk incl. LOD0 mesh)");
    println!("  heightfield        {hf_ms:7.3} ms/chunk");
    for (step, ms, verts) in mesh_ms {
        println!("  mesh step {step} m      {ms:7.3} ms/chunk  ({verts} verts)");
    }
    println!(
        "  trees              {tree_ms:7.3} ms/chunk  ({:.0} trees/chunk)",
        trees as f64 / count as f64
    );
    let per = |n: usize| n as f64 / count as f64;
    println!(
        "  props              {props_ms:7.3} ms/chunk  ({:.1} rocks, {:.1} stumps, {:.1} logs, {:.1} saplings per chunk)",
        per(kinds[0]),
        per(kinds[1]),
        per(kinds[2]),
        per(kinds[3])
    );
    Ok(())
}

fn trees_hash(world: &World, coord: ChunkCoord) -> u64 {
    let hf = world.heightfield(coord);
    let mut h = Fnv64::new();
    for t in scatter::trees(world, &hf) {
        for v in [t.pos[0], t.pos[1], t.pos[2], t.yaw, t.scale] {
            h.write(&v.to_bits().to_le_bytes());
        }
        h.write(&[t.kind]);
    }
    h.finish()
}

fn props_hash(world: &World, coord: ChunkCoord) -> u64 {
    let hf = world.heightfield(coord);
    let trees = scatter::trees(world, &hf);
    let mut h = Fnv64::new();
    for p in scatter::props(world, &hf, &trees) {
        for v in [
            p.pos[0], p.pos[1], p.pos[2], p.up[0], p.up[1], p.up[2], p.yaw, p.scale,
        ] {
            h.write(&v.to_bits().to_le_bytes());
        }
        h.write(&[p.kind as u8, p.variant]);
    }
    h.finish()
}

fn cmd_golden() -> Result<(), String> {
    println!(
        "// Generated by `cargo run -p rvgen-cli -- golden` on {}-{}.",
        std::env::consts::OS,
        std::env::consts::ARCH
    );
    println!("const EXPECTED: &[Golden] = &[");
    for (trip, seed) in GOLDEN_SEEDS {
        let code = SeedCode::new(trip, seed);
        let world = World::new(code).map_err(|e| e.to_string())?;
        for (cx, cz) in GOLDEN_CHUNKS {
            let c = ChunkCoord::new(cx, cz);
            println!(
                "    (\"{code}\", ({cx}, {cz}), 0x{:016x}, 0x{:016x}, 0x{:016x}),",
                world.heightfield(c).content_hash(),
                trees_hash(&world, c),
                props_hash(&world, c)
            );
        }
    }
    println!("];");
    Ok(())
}
