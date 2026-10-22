//! `RegionMotions` (scripts/inbetween/region_motions.gd): searching the other key for
//! where each region landed, and scoring motions.

use godot::builtin::inner::InnerVector2;
use godot::global;
use godot::prelude::*;

use super::key_features::Features;
use super::outlines::mean_nearest;
use super::sort::sort_custom;

/// `RegionMotions`' constants, in the order `NativeKernels` gives them
pub struct Constants {
    pub cap: f64,
    pub move_cost: f64,
    pub area_cost: f64,
    pub samples: i64,
    pub turns: i64,
    pub voted: usize,
    pub kept_per_turn: usize,
    pub apart: f64,
    pub kept: usize,
    pub anchors: usize,
    pub anchor_color: f64,
    pub voters: usize,
    pub distance_cost: f64,
    pub shown_weight: f64,
    pub own_choices: usize,
    pub alike: f64,
    pub apart_cost: f64,
    pub alike_apart_cost: f64,
    pub gap_cap: f64,
    pub border_points: usize,
    pub region_points: usize,
}

impl Constants {
    pub fn of(numbers: &[f64]) -> Self {
        Self {
            cap: numbers[0],
            move_cost: numbers[1],
            area_cost: numbers[2],
            samples: numbers[3] as i64,
            turns: numbers[4] as i64,
            voted: numbers[5] as usize,
            kept_per_turn: numbers[6] as usize,
            apart: numbers[7],
            kept: numbers[8] as usize,
            anchors: numbers[9] as usize,
            anchor_color: numbers[10],
            voters: numbers[11] as usize,
            distance_cost: numbers[12],
            shown_weight: numbers[13],
            own_choices: numbers[14] as usize,
            alike: numbers[15],
            apart_cost: numbers[16],
            alike_apart_cost: numbers[17],
            gap_cap: numbers[18],
            border_points: numbers[19] as usize,
            region_points: numbers[20] as usize,
        }
    }
}

/// What a `RegionMotions` reads
pub struct Motions<'a> {
    /// The key's canvas width, as its regions' `point_of` reads it
    pub width: i64,
    pub features: Features<'a>,
    pub other: Features<'a>,
    pub shift: Vector2,
    pub side: f64,
    pub constants: Constants,
}

/// `Vector2.rotated` in Godot
fn rotated(v: Vector2, angle: f64) -> Vector2 {
    InnerVector2::from_outer(&v).rotated(angle)
}

/// `Transform2D(angle, Vector2.ZERO)` in Godot: its sine and cosine as `rotated` takes them
fn turned(angle: f64) -> Transform2D {
    let along = rotated(Vector2::new(1.0, 0.0), angle);
    let (cos, sin) = (along.x, along.y);
    Transform2D::from_cols(
        Vector2::new(cos, sin),
        Vector2::new(-sin, cos),
        Vector2::ZERO,
    )
}

/// `motion * at` in Godot
pub fn xform(motion: Transform2D, at: Vector2) -> Vector2 {
    let basis = basis_xform(motion, at);
    Vector2::new(basis.x + motion.origin.x, basis.y + motion.origin.y)
}

/// `motion.basis_xform(at)` in Godot
fn basis_xform(motion: Transform2D, at: Vector2) -> Vector2 {
    Vector2::new(
        motion.a.x * at.x + motion.b.x * at.y,
        motion.a.y * at.x + motion.b.y * at.y,
    )
}

/// `RegionMotions.about`
fn about(center: Vector2, angle: f64, step: Vector2) -> Transform2D {
    let mut motion = turned(angle);
    let turned_center = basis_xform(motion, center);
    let moved = Vector2::new(center.x + step.x, center.y + step.y);
    motion.origin = Vector2::new(moved.x - turned_center.x, moved.y - turned_center.y);
    motion
}

/// `Vector2.distance_to` in Godot
fn distance(a: Vector2, b: Vector2) -> f32 {
    let dx = a.x - b.x;
    let dy = a.y - b.y;
    (dx * dx + dy * dy).sqrt()
}

/// `KeyRegions.point_of`
fn point_of(p: i64, width: i64) -> Vector2 {
    Vector2::new(
        ((p % width) as f64 + 0.5) as f32,
        ((p / width) as f64 + 0.5) as f32,
    )
}

/// The middle of `pixels`, as `_search_pixels` sums it
fn middle(pixels: &[i32], width: i64) -> Vector2 {
    let mut center = Vector2::ZERO;
    for &p in pixels {
        let point = point_of(p as i64, width);
        center = Vector2::new(center.x + point.x, center.y + point.y);
    }
    let count = pixels.len().max(1) as f64 as f32;
    Vector2::new(center.x / count, center.y / count)
}

impl Motions<'_> {
    /// `RegionMotions.cost_of`
    pub fn cost_of(&self, pixels: &[i32], motion: Transform2D) -> f64 {
        let c = &self.constants;
        let size = pixels.len() as i64;
        let stride = 1i64.max((size as f64 / c.samples as f64).ceil() as i64);
        let total = self.features.landing_sum(
            pixels,
            stride as usize,
            motion,
            &self.other,
            c.cap,
            c.move_cost,
            self.shift,
            f64::INFINITY,
        );
        let counted = (size + stride - 1) / stride;
        let determinant = motion.a.x * motion.b.y - motion.a.y * motion.b.x;
        let area = (determinant as f64).abs();
        let area = if area > 1e-3 { area } else { 1e-3 };
        total / counted.max(1) as f64 + c.area_cost * global::log(area).abs()
    }

    /// `RegionMotions._colour_at`
    fn colour_at(&self, p: usize) -> Vector3 {
        let values = self.features.values;
        let i = p * 5;
        let alpha = values[i + 3] as f64 / self.constants.shown_weight;
        let alpha = (if alpha > 1e-3 { alpha } else { 1e-3 }) as f32;
        Vector3::new(
            values[i] / alpha,
            values[i + 1] / alpha,
            values[i + 2] / alpha,
        )
    }

    /// `RegionMotions._search_pixels`, with the other key's shown pixels' `places` and
    /// `colours` (`_voters`)
    pub fn search_pixels(
        &self,
        pixels: &[i32],
        places: &[Vector2],
        colours: &[Vector3],
    ) -> Vec<Transform2D> {
        let c = &self.constants;
        let center = middle(pixels, self.width);
        // Anchors spread through the region, and the other key's pixels of their colours
        let mut anchors: Vec<Vector2> = Vec::new();
        let mut anchor_voters: Vec<Vec<Vector2>> = Vec::new();
        let step = 1.max(pixels.len() / c.anchors);
        for k in (0..pixels.len()).step_by(step) {
            let p = pixels[k] as usize;
            let colour = self.colour_at(p);
            let mut near: Vec<Vector2> = Vec::new();
            for (v, place) in places.iter().enumerate() {
                let apart = Vector3::new(
                    colours[v].x - colour.x,
                    colours[v].y - colour.y,
                    colours[v].z - colour.z,
                );
                let summed =
                    (apart.x as f64).abs() + (apart.y as f64).abs() + (apart.z as f64).abs();
                if summed <= c.anchor_color {
                    near.push(*place);
                }
            }
            if near.len() > c.voters {
                let every = near.len() as f64 / c.voters as f64;
                near = (0..c.voters)
                    .map(|n| near[(n as f64 * every) as usize])
                    .collect();
            }
            let point = point_of(p as i64, self.width);
            anchors.push(Vector2::new(point.x - center.x, point.y - center.y));
            anchor_voters.push(near);
            if anchors.len() >= c.anchors {
                break;
            }
        }
        let expected = Vector2::new(center.x + self.shift.x, center.y + self.shift.y);
        let reach = self.side * 0.75 + 4.0;
        let grid_left = (expected.x as f64 - reach).floor() as i64 - 2;
        let grid_top = (expected.y as f64 - reach).floor() as i64 - 2;
        let grid_width = (2.0 * reach).ceil() as i64 + 5;
        let mut votes = vec![0i32; (grid_width * ((2.0 * reach).ceil() as i64 + 5)) as usize];
        // Score, motion and place of each kept
        let mut found: Vec<(f64, Transform2D, Vector2)> = Vec::new();
        let tau = std::f64::consts::TAU;
        for turn in 0..c.turns {
            let angle = tau * turn as f64 / c.turns as f64;
            let mut voted: Vec<usize> = Vec::new();
            for (anchor, spots) in anchors.iter().zip(&anchor_voters) {
                let offset = rotated(*anchor, angle);
                for spot in spots {
                    let at = Vector2::new(spot.x - offset.x, spot.y - offset.y);
                    if distance(at, expected) as f64 > reach {
                        continue;
                    }
                    let cell = ((at.y as f64).round() as i64 - grid_top) * grid_width
                        + (at.x as f64).round() as i64
                        - grid_left;
                    let cell = cell as usize;
                    if votes[cell] == 0 {
                        voted.push(cell);
                    }
                    votes[cell] += 1;
                }
            }
            sort_custom(&mut voted, |x, y| votes[*x] > votes[*y]);
            for &cell in &voted {
                votes[cell] = 0;
            }
            let mut scored: Vec<(f64, Transform2D, Vector2)> = Vec::new();
            for &cell in voted.iter().take(c.voted) {
                let cell = cell as i64;
                let place = Vector2::new(
                    (cell % grid_width + grid_left) as f32,
                    (cell / grid_width + grid_top) as f32,
                );
                let step = Vector2::new(place.x - center.x, place.y - center.y);
                let motion = about(center, angle, step);
                let score = self.cost_of(pixels, motion)
                    + c.distance_cost * distance(place, expected) as f64;
                scored.push((score, motion, place));
            }
            sort_custom(&mut scored, |x, y| x.0 < y.0);
            let mut kept: Vec<Vector2> = Vec::new();
            for entry in &scored {
                let place = entry.2;
                let close = kept.iter().any(|other| {
                    (place.x as f64 - other.x as f64).abs()
                        + (place.y as f64 - other.y as f64).abs()
                        < c.apart
                });
                if close {
                    continue;
                }
                kept.push(place);
                found.push(*entry);
                if kept.len() >= c.kept_per_turn {
                    break;
                }
            }
        }
        sort_custom(&mut found, |x, y| x.0 < y.0);
        found.iter().take(c.kept).map(|entry| entry.1).collect()
    }

    /// `RegionChoice._own_best` for one region's `pixels`: its best few `candidates`, by
    /// their place among them, and what each costs, -1 for those the GDScript gives up on
    /// as they can't be among the best (see there), so it comes out the same
    pub fn own_best(&self, pixels: &[i32], candidates: &[Transform2D]) -> (Vec<i32>, Vec<f64>) {
        let most_kept = self.constants.own_choices;
        let exact: Vec<f64> = candidates
            .iter()
            .map(|m| self.cost_of(pixels, *m))
            .collect();
        let mut row = vec![0.0f64; candidates.len()];
        // The lowest costs so far, cheapest first
        let mut lowest: Vec<f64> = Vec::new();
        let mut gave_up = false;
        for (c, &value) in exact.iter().enumerate() {
            let limit = if lowest.len() >= most_kept {
                lowest[most_kept - 1]
            } else {
                f64::INFINITY
            };
            if value > limit {
                row[c] = -1.0;
                gave_up = true;
                continue;
            }
            row[c] = value;
            let at = lowest.partition_point(|&low| low < value);
            lowest.insert(at, value);
            lowest.truncate(most_kept);
        }
        let most = if gave_up {
            *lowest.last().unwrap_or(&f64::INFINITY)
        } else {
            f64::INFINITY
        };
        let mut best = self.cheapest(&row, candidates, most, gave_up);
        if best.is_empty() && gave_up {
            for (c, value) in row.iter_mut().enumerate() {
                if *value == -1.0 {
                    *value = exact[c];
                }
            }
            best = self.cheapest(&row, candidates, f64::INFINITY, false);
        }
        (best, row)
    }

    /// `RegionChoice._cheapest`
    fn cheapest(&self, row: &[f64], candidates: &[Transform2D], most: f64, ties: bool) -> Vec<i32> {
        let mut scored: Vec<usize> = (0..row.len())
            .filter(|&c| row[c] != -1.0 && row[c] <= most)
            .collect();
        sort_custom(&mut scored, |x, y| row[*x] < row[*y]);
        if ties {
            for k in 1..scored.len() {
                let (now, last) = (scored[k], scored[k - 1]);
                if row[now] == row[last] && candidates[now] != candidates[last] {
                    return Vec::new();
                }
            }
        }
        scored
            .iter()
            .take(self.constants.own_choices)
            .map(|&c| c as i32)
            .collect()
    }
}

/// `RegionMotions._spread`
fn spread(points: &[Vector2], most: usize) -> Vec<Vector2> {
    if points.len() <= most {
        return points.to_vec();
    }
    (0..most)
        .map(|k| points[(k as f64 * (points.len() - 1) as f64 / (most - 1) as f64) as usize])
        .collect()
}

/// One pair of bordering regions, for `RegionMotions._apart_costs`
pub struct Border<'a> {
    pub points: &'a [Vector2],
    pub r_pixels: &'a [i32],
    pub s_pixels: &'a [i32],
    pub r_colour: Vector3,
    pub s_colour: Vector3,
    pub r_choices: &'a [Transform2D],
    pub s_choices: &'a [Transform2D],
}

/// `RegionMotions._apart_costs` on a canvas `width` pixels wide: rows by `r`'s choices
pub fn apart_costs(border: &Border, width: i64, c: &Constants) -> Vec<Vec<f32>> {
    let points_of = |pixels: &[i32]| -> Vec<Vector2> {
        pixels.iter().map(|&p| point_of(p as i64, width)).collect()
    };
    let along = spread(border.points, c.border_points);
    let r_points = spread(&points_of(border.r_pixels), c.region_points);
    let s_points = spread(&points_of(border.s_pixels), c.region_points);
    let moved = |motion: &Transform2D, points: &[Vector2]| -> Vec<Vector2> {
        points.iter().map(|&point| xform(*motion, point)).collect()
    };
    let r_border: Vec<Vec<Vector2>> = border.r_choices.iter().map(|m| moved(m, &along)).collect();
    let r_moved: Vec<Vec<Vector2>> = border
        .r_choices
        .iter()
        .map(|m| moved(m, &r_points))
        .collect();
    let s_border: Vec<Vec<Vector2>> = border.s_choices.iter().map(|m| moved(m, &along)).collect();
    let s_moved: Vec<Vec<Vector2>> = border
        .s_choices
        .iter()
        .map(|m| moved(m, &s_points))
        .collect();
    let a = Vector3::new(
        border.r_colour.x - border.s_colour.x,
        border.r_colour.y - border.s_colour.y,
        border.r_colour.z - border.s_colour.z,
    );
    let summed = (a.x as f64).abs() + (a.y as f64).abs() + (a.z as f64).abs();
    let alike = global::exp(-summed / c.alike);
    let weight =
        (c.apart_cost + (c.alike_apart_cost - c.apart_cost) * alike) * border.points.len() as f64;
    let mut table = Vec::with_capacity(r_border.len());
    for i in 0..r_border.len() {
        let mut row = Vec::with_capacity(s_border.len());
        for j in 0..s_border.len() {
            let gap = 0.5
                * (mean_nearest(&r_border[i], &s_moved[j])
                    + mean_nearest(&s_border[j], &r_moved[i]));
            let over = gap - 1.0;
            let clamped = if over < 0.0 {
                0.0
            } else if over > c.gap_cap {
                c.gap_cap
            } else {
                over
            };
            row.push((weight * clamped) as f32);
        }
        table.push(row);
    }
    table
}
