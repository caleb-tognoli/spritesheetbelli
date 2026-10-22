//! `MeshMatching` (scripts/inbetween/mesh_matching.gd): where a key's pixels are pulled.

use std::collections::HashMap;

use godot::builtin::inner::InnerVector2;
use godot::global;
use godot::prelude::*;

/// What `MeshMatching` reads, see its variables
pub struct Matching<'a> {
    pub width: i64,
    pub height: i64,
    pub own: &'a [f32],
    pub others: &'a [f32],
    pub own_edges: &'a [u8],
    pub pixels: &'a [i32],
    pub triangles: &'a [i32],
    pub turns: &'a [f32],
    pub landed: &'a [Vector2],
    pub spot_x: &'a [i32],
    pub spot_y: &'a [i32],
    pub spot_least: &'a [f64],
    pub near_cost: f64,
    pub cell: f64,
    pub edges: &'a [i32],
}

/// `KeyMesh`'s constants used here
pub struct Pulls {
    pub flat: f64,
    pub edge: f64,
    pub likeness: f64,
}

impl Matching<'_> {
    /// `MeshMatching.pixel_matches`: goals and pulls
    pub fn pixel_matches(
        &self,
        start: usize,
        end: usize,
        pulling: &Pulls,
    ) -> (Vec<Vector2>, Vec<f32>) {
        let (width, height) = (self.width, self.height);
        let (own, others) = (self.own, self.others);
        let mut goals = Vec::with_capacity(end - start);
        let mut pulls = Vec::with_capacity(end - start);
        let mut patch = [0f32; 36];
        // Each triangle's 3 × 3 steps turned, worked out when first needed
        let mut ways_of: Vec<Option<[i64; 18]>> = vec![None; self.turns.len()];
        for s in start..end {
            let p = self.pixels[s] as i64;
            let px = p % width;
            let py = p / width;
            let mut k = 0;
            for oy in -1..=1 {
                let qy = py + oy;
                for ox in -1..=1 {
                    let qx = px + ox;
                    if qx < 0 || qy < 0 || qx >= width || qy >= height {
                        patch[k..k + 4].fill(0.0);
                    } else {
                        let q = ((qy * width + qx) * 4) as usize;
                        patch[k..k + 4].copy_from_slice(&own[q..q + 4]);
                    }
                    k += 4;
                }
            }
            let triangle = self.triangles[s] as usize;
            let ways = *ways_of[triangle].get_or_insert_with(|| turned_ways(self.turns[triangle]));
            let place = self.landed[s];
            let base_x = (place.x as f64).floor() as i64;
            let base_y = (place.y as f64).floor() as i64;
            let mut best = f64::INFINITY;
            let mut best_cost = 0.0f64;
            let mut best_x = base_x;
            let mut best_y = base_y;
            for n in 0..self.spot_least.len() {
                if self.spot_least[n] >= best {
                    break;
                }
                let cx = base_x + self.spot_x[n] as i64;
                let cy = base_y + self.spot_y[n] as i64;
                let apart_x = (cx as f64 + 0.5) as f32 - place.x;
                let apart_y = (cy as f64 + 0.5) as f32 - place.y;
                let prior = self.near_cost * (apart_x * apart_x + apart_y * apart_y) as f64;
                if prior >= best {
                    continue;
                }
                let mut cost = 0.0f64;
                let limit = (best - prior) * 9.0;
                for j in 0..9 {
                    let qx = cx + ways[j * 2];
                    let qy = cy + ways[j * 2 + 1];
                    let i = j * 4;
                    if qx < 0 || qy < 0 || qx >= width || qy >= height {
                        cost += (patch[i] as f64).abs();
                        cost += (patch[i + 1] as f64).abs();
                        cost += (patch[i + 2] as f64).abs();
                        cost += (patch[i + 3] as f64).abs();
                    } else {
                        let q = ((qy * width + qx) * 4) as usize;
                        cost += (others[q] as f64 - patch[i] as f64).abs();
                        cost += (others[q + 1] as f64 - patch[i + 1] as f64).abs();
                        cost += (others[q + 2] as f64 - patch[i + 2] as f64).abs();
                        cost += (others[q + 3] as f64 - patch[i + 3] as f64).abs();
                    }
                    if cost >= limit {
                        break;
                    }
                }
                if cost >= limit {
                    continue;
                }
                cost /= 9.0;
                if cost + prior < best {
                    best = cost + prior;
                    best_cost = cost;
                    best_x = cx;
                    best_y = cy;
                }
            }
            goals.push(Vector2::new(best_x as f32 + 0.5, best_y as f32 + 0.5));
            let pull = if self.own_edges[p as usize] == 1 {
                1.0
            } else {
                pulling.flat
            };
            pulls.push((pull * global::exp(-best_cost / pulling.likeness)) as f32);
        }
        (goals, pulls)
    }

    /// `MeshMatching.edge_pulls`: samples, goals and pulls
    pub fn edge_pulls(
        &self,
        start: usize,
        end: usize,
        pulling: &Pulls,
    ) -> (Vec<i32>, Vec<Vector2>, Vec<f32>) {
        let width = self.width;
        let cell = self.cell;
        // The landed pixels in square cells, each cell's in order, as MeshMatching's buckets
        let mut buckets: HashMap<(i64, i64), Vec<usize>> = HashMap::new();
        for (s, place) in self.landed.iter().enumerate() {
            let key = (
                (place.x as f64 / cell).floor() as i64,
                (place.y as f64 / cell).floor() as i64,
            );
            buckets.entry(key).or_default().push(s);
        }
        let mut samples = Vec::new();
        let mut goals = Vec::new();
        let mut pulls = Vec::new();
        for e in start..end {
            let q = self.edges[e] as i64;
            let spot = Vector2::new(
                ((q % width) as f64 + 0.5) as f32,
                ((q / width) as f64 + 0.5) as f32,
            );
            let home_x = (spot.x as f64 / cell).floor() as i64;
            let home_y = (spot.y as f64 / cell).floor() as i64;
            let mut best = f64::INFINITY;
            let mut best_cost = 0.0f64;
            let mut best_sample: Option<usize> = None;
            let i = (q * 4) as usize;
            for by in home_y - 1..home_y + 2 {
                for bx in home_x - 1..home_x + 2 {
                    let Some(bucket) = buckets.get(&(bx, by)) else {
                        continue;
                    };
                    for &s in bucket {
                        let place = self.landed[s];
                        let dx = place.x - spot.x;
                        let dy = place.y - spot.y;
                        let apart = (dx * dx + dy * dy) as f64;
                        if apart > cell * cell {
                            continue;
                        }
                        let o = (self.pixels[s] * 4) as usize;
                        let mut cost = 0.0f64;
                        cost += (self.own[o] as f64 - self.others[i] as f64).abs();
                        cost += (self.own[o + 1] as f64 - self.others[i + 1] as f64).abs();
                        cost += (self.own[o + 2] as f64 - self.others[i + 2] as f64).abs();
                        cost += (self.own[o + 3] as f64 - self.others[i + 3] as f64).abs();
                        let total = cost + self.near_cost * apart;
                        if total < best {
                            best = total;
                            best_cost = cost;
                            best_sample = Some(s);
                        }
                    }
                }
            }
            if let Some(s) = best_sample {
                samples.push(s as i32);
                goals.push(spot);
                pulls.push((pulling.edge * global::exp(-best_cost / pulling.likeness)) as f32);
            }
        }
        (samples, goals, pulls)
    }
}

/// The steps to a pixel's 3 × 3 neighbours, each turned by `turn` and rounded to a whole
/// pixel, as `Vector2(ox, oy).rotated(turn)` gives in Godot: x and y of each, by rows
fn turned_ways(turn: f32) -> [i64; 18] {
    let mut ways = [0i64; 18];
    let mut k = 0;
    for oy in -1..=1 {
        for ox in -1..=1 {
            let step = Vector2::new(ox as f32, oy as f32);
            let turned = InnerVector2::from_outer(&step).rotated(turn as f64);
            ways[k] = (turned.x as f64 + 0.5).floor() as i64;
            ways[k + 1] = (turned.y as f64 + 0.5).floor() as i64;
            k += 2;
        }
    }
    ways
}
