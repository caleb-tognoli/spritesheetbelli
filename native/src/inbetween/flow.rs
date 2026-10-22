//! `FlowMorph._moved` (scripts/inbetween/flow_morph.gd): a key's pixels moved by their flow.

use godot::prelude::*;

/// What `FlowMorph._moved` reads besides the key
pub struct Moving<'a> {
    pub width: i64,
    pub height: i64,
    /// `_keys_area`, as start and end
    pub area: (i64, i64, i64, i64),
    pub flow: &'a [Vector2],
    pub doubt: &'a [f32],
    pub most_stretch: i64,
    pub close: f64,
}

fn plus(a: Vector2, b: Vector2) -> Vector2 {
    Vector2::new(a.x + b.x, a.y + b.y)
}

fn minus(a: Vector2, b: Vector2) -> Vector2 {
    Vector2::new(a.x - b.x, a.y - b.y)
}

fn low(a: Vector2, b: Vector2) -> Vector2 {
    Vector2::new(
        if a.x < b.x { a.x } else { b.x },
        if a.y < b.y { a.y } else { b.y },
    )
}

fn high(a: Vector2, b: Vector2) -> Vector2 {
    Vector2::new(
        if a.x > b.x { a.x } else { b.x },
        if a.y > b.y { a.y } else { b.y },
    )
}

fn cross(a: Vector2, b: Vector2) -> f64 {
    (a.x * b.y - a.y * b.x) as f64
}

impl Moving<'_> {
    /// `FlowMorph._moved`: `data` moved `t` of the way
    pub fn moved(&self, data: &[u8], t: f64) -> Vec<u8> {
        let (width, height) = (self.width, self.height);
        let count = (width * height) as usize;
        let mut out = vec![0u8; count * 4];
        let mut best = vec![f32::INFINITY; count];
        let (last_x, last_y) = (width - 1, height - 1);
        let shown = |q: i64| data[q as usize * 4 + 3] > 0;
        let flow = |q: i64| self.flow[q as usize];
        let (area_x0, area_y0, area_x1, area_y1) = self.area;
        for y in area_y0..area_y1 {
            for x in area_x0..area_x1 {
                let p = y * width + x;
                if !shown(p) {
                    continue;
                }
                let own = flow(p);
                let (up, down) = (p - width, p + width);
                let has_left = x > 0 && shown(p - 1);
                let has_right = x < last_x && shown(p + 1);
                let has_up = y > 0 && shown(up);
                let has_down = y < last_y && shown(down);
                // Each corner moves as the shown pixels sharing it, on average
                let corner =
                    |at: (f64, f64), beside: Option<i64>, by: Option<i64>, across: Option<i64>| {
                        let mut sum = own;
                        let mut n = 1;
                        for q in [beside, by, across].into_iter().flatten() {
                            sum = plus(sum, flow(q));
                            n += 1;
                        }
                        let along = (t / n as f64) as f32;
                        let start = Vector2::new(at.0 as f32, at.1 as f32);
                        plus(start, Vector2::new(sum.x * along, sum.y * along))
                    };
                let (xf, yf) = (x as f64, y as f64);
                let c0 = corner(
                    (xf - 0.5, yf - 0.5),
                    has_left.then_some(p - 1),
                    has_up.then_some(up),
                    (x > 0 && y > 0 && shown(up - 1)).then_some(up - 1),
                );
                let c1 = corner(
                    (xf + 0.5, yf - 0.5),
                    has_right.then_some(p + 1),
                    has_up.then_some(up),
                    (x < last_x && y > 0 && shown(up + 1)).then_some(up + 1),
                );
                let c2 = corner(
                    (xf + 0.5, yf + 0.5),
                    has_right.then_some(p + 1),
                    has_down.then_some(down),
                    (x < last_x && y < last_y && shown(down + 1)).then_some(down + 1),
                );
                let c3 = corner(
                    (xf - 0.5, yf + 0.5),
                    has_left.then_some(p - 1),
                    has_down.then_some(down),
                    (x > 0 && y < last_y && shown(down - 1)).then_some(down - 1),
                );
                let lowest = low(low(c0, c1), low(c2, c3));
                let highest = high(high(c0, c1), high(c2, c3));
                let x0 = 0.max((lowest.x as f64).floor() as i64);
                let y0 = 0.max((lowest.y as f64).floor() as i64);
                let x1 = last_x
                    .min((highest.x as f64).ceil() as i64)
                    .min(x0 + self.most_stretch);
                let y1 = last_y
                    .min((highest.y as f64).ceil() as i64)
                    .min(y0 + self.most_stretch);
                let own_doubt = self.doubt[p as usize] as f64;
                let (side_01, side_12, side_20) = (minus(c1, c0), minus(c2, c1), minus(c0, c2));
                let (side_02, side_23, side_30) = (minus(c2, c0), minus(c3, c2), minus(c0, c3));
                let close = self.close;
                let within = |d1: f64, d2: f64, d3: f64| {
                    (d1 >= -close && d2 >= -close && d3 >= -close)
                        || (d1 <= close && d2 <= close && d3 <= close)
                };
                let i = p as usize * 4;
                for py in y0..=y1 {
                    for px in x0..=x1 {
                        let q = (py * width + px) as usize;
                        if own_doubt > best[q] as f64 {
                            continue;
                        }
                        let at = Vector2::new(px as f32, py as f32);
                        let first = within(
                            cross(side_01, minus(at, c0)),
                            cross(side_12, minus(at, c1)),
                            cross(side_20, minus(at, c2)),
                        );
                        if !first
                            && !within(
                                cross(side_02, minus(at, c0)),
                                cross(side_23, minus(at, c2)),
                                cross(side_30, minus(at, c3)),
                            )
                        {
                            continue;
                        }
                        best[q] = own_doubt as f32;
                        out[q * 4..q * 4 + 4].copy_from_slice(&data[i..i + 4]);
                    }
                }
            }
        }
        out
    }
}
