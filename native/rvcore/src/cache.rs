//! Worlds built so far, shared between `WorldGen` and `ChunkBuilder` so a trip is only
//! generated once, and the background loader that builds them while the loading screen shows
//! its progress.

use std::sync::{Arc, Mutex};
use std::thread;

use rvgen::{SeedCode, World};

/// How many worlds are kept (the current trip and the one before).
const KEEP: usize = 2;

static CACHE: Mutex<Vec<(SeedCode, Arc<World>)>> = Mutex::new(Vec::new());

/// The cached world for `code`, if it's been built.
pub fn cached(code: SeedCode) -> Option<Arc<World>> {
    let cache = CACHE.lock().ok()?;
    cache
        .iter()
        .find(|(c, _)| *c == code)
        .map(|(_, w)| w.clone())
}

fn remember(code: SeedCode, world: Arc<World>) {
    if let Ok(mut cache) = CACHE.lock() {
        cache.retain(|(c, _)| *c != code);
        cache.push((code, world));
        while cache.len() > KEEP {
            cache.remove(0);
        }
    }
}

/// The world for a seed code: from the cache, or built now (on this thread).
pub fn world_for(text: &str) -> Result<Arc<World>, String> {
    let code = SeedCode::parse(text)
        .and_then(|c| c.check_supported().map(|_| c))
        .map_err(|e| e.to_string())?;
    if let Some(w) = cached(code) {
        return Ok(w);
    }
    let world = Arc::new(World::new(code).map_err(|e| e.to_string())?);
    remember(code, world.clone());
    Ok(world)
}

/// Where a background load has got to.
#[derive(Default)]
pub struct Progress {
    pub fraction: f32,
    pub stage: String,
    /// Set once it's finished.
    pub result: Option<Result<Arc<World>, String>>,
}

/// Builds the world for `text` on a background thread (or straight away from the cache).
pub fn load_in_background(text: &str) -> Arc<Mutex<Progress>> {
    let progress = Arc::new(Mutex::new(Progress::default()));
    let code = match SeedCode::parse(text).and_then(|c| c.check_supported().map(|_| c)) {
        Ok(c) => c,
        Err(e) => {
            progress.lock().expect("fresh mutex").result = Some(Err(e.to_string()));
            return progress;
        }
    };
    if let Some(w) = cached(code) {
        let mut p = progress.lock().expect("fresh mutex");
        p.fraction = 1.0;
        p.result = Some(Ok(w));
        drop(p);
        return progress;
    }
    let shared = progress.clone();
    let spawned = thread::Builder::new()
        .name("rvgen-load".into())
        .spawn(move || {
            let report = shared.clone();
            let mut tell = move |f: f32, what: &str| {
                if let Ok(mut p) = report.lock() {
                    p.fraction = f.clamp(0.0, 1.0);
                    if p.stage != what {
                        p.stage = what.to_string();
                    }
                }
            };
            let result = World::new_with_progress(code, &mut tell)
                .map(Arc::new)
                .map_err(|e| e.to_string());
            if let Ok(w) = &result {
                remember(code, w.clone());
            }
            if let Ok(mut p) = shared.lock() {
                p.fraction = 1.0;
                p.result = Some(result);
            }
        });
    if let Err(e) = spawned {
        progress.lock().expect("fresh mutex").result =
            Some(Err(format!("could not start loading: {e}")));
    }
    progress
}
