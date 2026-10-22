//! `KeyFeatures` (scripts/inbetween/key_features.gd): how alike two keys' pixels are.

use godot::prelude::*;

/// Features per pixel, `KeyFeatures.COUNT`
const COUNT: usize = 5;

/// A key's features, see `KeyFeatures`
pub struct Features<'a> {
    pub width: i64,
    pub height: i64,
    pub values: &'a [f32],
}

impl Features<'_> {
    /// `KeyFeatures.difference`
    fn difference(&self, p: usize, other: &Features, at: Vector2) -> f64 {
        let x = at.x as f64 - 0.5;
        let y = at.y as f64 - 0.5;
        let x0 = x.floor() as i64;
        let y0 = y.floor() as i64;
        let fx = x - x0 as f64;
        let fy = y - y0 as f64;
        let w = other.width;
        let h = other.height;
        let o = other.values;
        let mut w00 = (1.0 - fx) * (1.0 - fy);
        let mut w10 = fx * (1.0 - fy);
        let mut w01 = (1.0 - fx) * fy;
        let mut w11 = fx * fy;
        if x0 < 0 || y0 < 0 {
            w00 = 0.0;
        }
        if x0 + 1 >= w || y0 < 0 {
            w10 = 0.0;
        }
        if x0 < 0 || y0 + 1 >= h {
            w01 = 0.0;
        }
        if x0 + 1 >= w || y0 + 1 >= h {
            w11 = 0.0;
        }
        if x0 + 1 < 0 || y0 + 1 < 0 || x0 >= w || y0 >= h {
            let mut none = 0.0f64;
            for c in 0..COUNT {
                none += (self.values[p * COUNT + c] as f64).abs();
            }
            return none;
        }
        let row = |y: i64| y.clamp(0, h - 1) * w;
        let q00 = ((row(y0) + x0.clamp(0, w - 1)) as usize) * COUNT;
        let q10 = ((row(y0) + (x0 + 1).clamp(0, w - 1)) as usize) * COUNT;
        let q01 = ((row(y0 + 1) + x0.clamp(0, w - 1)) as usize) * COUNT;
        let q11 = ((row(y0 + 1) + (x0 + 1).clamp(0, w - 1)) as usize) * COUNT;
        let i = p * COUNT;
        let mut total = 0.0f64;
        for c in 0..COUNT {
            let sampled = o[q00 + c] as f64 * w00
                + o[q10 + c] as f64 * w10
                + o[q01 + c] as f64 * w01
                + o[q11 + c] as f64 * w11;
            total += (self.values[i + c] as f64 - sampled).abs();
        }
        total
    }

    /// `KeyFeatures.landing_sum`, or `landing_sum_below` given up as soon as the sum is
    /// over `bound`
    #[allow(clippy::too_many_arguments)]
    pub fn landing_sum(
        &self,
        pixels: &[i32],
        stride: usize,
        motion: Transform2D,
        other: &Features,
        cap: f64,
        move_cost: f64,
        shift: Vector2,
        bound: f64,
    ) -> f64 {
        let own = self.values;
        let o = other.values;
        let w = other.width;
        let h = other.height;
        let row = w as usize * COUNT;
        let mut total = 0.0f64;
        for &p in pixels.iter().step_by(stride) {
            let p = p as i64;
            let at = Vector2::new(
                ((p % self.width) as f64 + 0.5) as f32,
                ((p / self.width) as f64 + 0.5) as f32,
            );
            let landed = transformed(motion, at);
            let x = landed.x as f64 - 0.5;
            let y = landed.y as f64 - 0.5;
            let x0 = x.floor() as i64;
            let y0 = y.floor() as i64;
            let i = p as usize * COUNT;
            let mut d = 0.0f64;
            if x0 >= 0 && y0 >= 0 && x0 + 1 < w && y0 + 1 < h {
                let fx = x - x0 as f64;
                let fy = y - y0 as f64;
                let w00 = (1.0 - fx) * (1.0 - fy);
                let w10 = fx * (1.0 - fy);
                let w01 = (1.0 - fx) * fy;
                let w11 = fx * fy;
                let q00 = (y0 * w + x0) as usize * COUNT;
                let q10 = q00 + COUNT;
                let q01 = q00 + row;
                let q11 = q01 + COUNT;
                for c in 0..COUNT {
                    let sampled = o[q00 + c] as f64 * w00
                        + o[q10 + c] as f64 * w10
                        + o[q01 + c] as f64 * w01
                        + o[q11 + c] as f64 * w11;
                    d += (own[i + c] as f64 - sampled).abs();
                }
            } else {
                d = self.difference(p as usize, other, landed);
            }
            total += if d < cap { d } else { cap };
            if move_cost != 0.0 {
                let to = at + shift;
                let dx = landed.x - to.x;
                let dy = landed.y - to.y;
                total += move_cost * (dx * dx + dy * dy).sqrt() as f64;
            }
            if total > bound {
                return total;
            }
        }
        total
    }
}

/// `motion * at` in Godot: `Transform2D::xform`
fn transformed(motion: Transform2D, at: Vector2) -> Vector2 {
    Vector2::new(
        motion.a.x * at.x + motion.b.x * at.y + motion.origin.x,
        motion.a.y * at.x + motion.b.y * at.y + motion.origin.y,
    )
}
