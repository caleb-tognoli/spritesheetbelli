//! `ShapeBlend._warp` and `RegionMotions._mean_nearest`.

use godot::prelude::*;

/// `ShapeBlend._warp`: the cost of warping outline A (`n` points) onto B (`m`) from B's
/// point `start`, and each step's move when `writing`
pub fn warp(
    costs: &[f32],
    n: usize,
    m: usize,
    start: usize,
    step_cost: f64,
    writing: bool,
) -> (f64, Vec<u8>) {
    let mut moves = if writing {
        vec![0u8; n * m]
    } else {
        Vec::new()
    };
    let mut above = vec![0f32; m];
    let mut row = vec![0f32; m];
    for i in 0..n {
        for j in 0..m {
            let here = costs[i * m + (j + start) % m] as f64;
            if i == 0 && j == 0 {
                row[0] = here as f32;
                continue;
            }
            let mut best = f64::INFINITY;
            let mut step = 0u8;
            if i > 0 && j > 0 {
                best = above[j - 1] as f64;
            }
            if i > 0 && (above[j] as f64) + step_cost < best {
                best = above[j] as f64 + step_cost;
                step = 1;
            }
            if j > 0 && (row[j - 1] as f64) + step_cost < best {
                best = row[j - 1] as f64 + step_cost;
                step = 2;
            }
            row[j] = (best + here) as f32;
            if writing {
                moves[i * m + j] = step;
            }
        }
        std::mem::swap(&mut above, &mut row);
    }
    (above[m - 1] as f64, moves)
}

/// `RegionMotions._mean_nearest`: the average, over `points`, of how far each is from the
/// nearest of `others`
pub fn mean_nearest(points: &[Vector2], others: &[Vector2]) -> f64 {
    let mut total = 0.0f64;
    for point in points {
        let mut nearest = f64::INFINITY;
        for spot in others {
            let dx = point.x - spot.x;
            let dy = point.y - spot.y;
            let apart = (dx * dx + dy * dy) as f64;
            if apart < nearest {
                nearest = apart;
            }
        }
        total += nearest.sqrt();
    }
    total / points.len().max(1) as f64
}
