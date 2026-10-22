//! `MeshDrawing.drawn` (scripts/inbetween/mesh_drawing.gd), with `MeshTools.closed` and
//! `MeshTools.drawn_over`: a bent key drawn in a frame.

use godot::global;
use godot::prelude::*;

/// `MeshDrawing`'s and `KeyMesh`'s constants
pub struct Constants {
    pub alike_reach: i64,
    pub own_move: f64,
    pub magnified: f64,
    pub turned: f64,
}

/// What `MeshDrawing.drawn` reads: the key drawn bigger and its pixels placed in the
/// triangles, and the mesh
pub struct Drawing<'a> {
    pub data: &'a [u8],
    pub scale: i64,
    pub width: i64,
    pub height: i64,
    pub points: &'a [Vector2],
    pub pixels: &'a [i32],
    pub triangles_of: &'a [i32],
    pub weights_of: &'a [Vector3],
    pub strays: &'a [i32],
    pub mesh_width: i64,
    pub depth: &'a [i32],
    pub triangles: &'a [i32],
    pub weights: &'a [f32],
    pub rest: &'a [Vector2],
}

fn plus(a: Vector2, b: Vector2) -> Vector2 {
    Vector2::new(a.x + b.x, a.y + b.y)
}

fn minus(a: Vector2, b: Vector2) -> Vector2 {
    Vector2::new(a.x - b.x, a.y - b.y)
}

fn scaled(v: Vector2, by: f64) -> Vector2 {
    let by = by as f32;
    Vector2::new(v.x * by, v.y * by)
}

fn cross(a: Vector2, b: Vector2) -> f32 {
    a.x * b.y - a.y * b.x
}

fn minf(a: f64, b: f64) -> f64 {
    if a < b { a } else { b }
}

fn maxf(a: f64, b: f64) -> f64 {
    if a > b { a } else { b }
}

/// A `Rect2i`, as position and end
#[derive(Clone, Copy)]
struct Area {
    x0: i64,
    y0: i64,
    x1: i64,
    y1: i64,
}

impl Area {
    /// `Rect2i.intersection`, of rectangles given as position and size
    fn intersection(position: (i64, i64), size: (i64, i64), other_size: (i64, i64)) -> Area {
        let (end_x, end_y) = (position.0 + size.0, position.1 + size.1);
        if 0 >= end_x || position.0 >= other_size.0 || 0 >= end_y || position.1 >= other_size.1 {
            return Area {
                x0: 0,
                y0: 0,
                x1: 0,
                y1: 0,
            };
        }
        let x0 = position.0.max(0);
        let y0 = position.1.max(0);
        Area {
            x0,
            y0,
            x1: x0 + (other_size.0.min(end_x) - x0),
            y1: y0 + (other_size.1.min(end_y) - y0),
        }
    }

    fn each(&self, width: i64, mut work: impl FnMut(usize, i64, i64)) {
        for y in self.y0..self.y1 {
            for x in self.x0..self.x1 {
                work((y * width + x) as usize, x, y);
            }
        }
    }
}

/// `MeshTools.closed` in `area`
fn closed(mask: &[u8], width: i64, height: i64, area: Area) -> Vec<u8> {
    let mut grown = mask.to_vec();
    area.each(width, |p, x, y| {
        if mask[p] == 1 {
            return;
        }
        let w = width as usize;
        if (x > 0 && mask[p - 1] == 1)
            || (x < width - 1 && mask[p + 1] == 1)
            || (y > 0 && mask[p - w] == 1)
            || (y < height - 1 && mask[p + w] == 1)
        {
            grown[p] = 1;
        }
    });
    let mut result = grown.clone();
    area.each(width, |p, x, y| {
        if grown[p] == 0 {
            return;
        }
        let w = width as usize;
        if x == 0
            || x == width - 1
            || y == 0
            || y == height - 1
            || grown[p - 1] == 0
            || grown[p + 1] == 0
            || grown[p - w] == 0
            || grown[p + w] == 0
        {
            result[p] = 0;
        }
    });
    area.each(width, |p, _, _| {
        if mask[p] == 1 {
            result[p] = 1;
        }
    });
    result
}

impl Drawing<'_> {
    /// `MeshTools.nearest_covering`
    fn nearest_covering(&self, at: Vector2) -> i64 {
        let x = ((at.x as f64).floor() as i64).clamp(0, self.width - 1);
        let q = ((at.y as f64).floor() as i64).clamp(0, self.height - 1) * self.width + x;
        if self.data[q as usize * 4 + 3] > 0 {
            q
        } else {
            -1
        }
    }

    /// `MeshTools.smooth_covering`
    fn smooth_covering(&self, at: Vector2) -> i64 {
        let x = at.x as f64 - 0.5;
        let y = at.y as f64 - 0.5;
        let x0 = x.floor() as i64;
        let y0 = y.floor() as i64;
        let fx = x - x0 as f64;
        let fy = y - y0 as f64;
        let mut covered = 0.0f64;
        let mut best = -1i64;
        let mut best_weight = 0.0f64;
        for dy in 0..2 {
            for dx in 0..2 {
                let (qx, qy) = (x0 + dx, y0 + dy);
                if qx < 0 || qy < 0 || qx >= self.width || qy >= self.height {
                    continue;
                }
                let q = qy * self.width + qx;
                if self.data[q as usize * 4 + 3] == 0 {
                    continue;
                }
                let weight =
                    (if dx == 1 { fx } else { 1.0 - fx }) * (if dy == 1 { fy } else { 1.0 - fy });
                covered += weight;
                if weight > best_weight || best < 0 {
                    best_weight = weight;
                    best = q;
                }
            }
        }
        if covered >= 0.5 { best } else { -1 }
    }

    /// `MeshTools.drawn_over`: the triangles drawn, and 1 where they're drawn smooth
    fn drawn_over(&self, positions: &[Vector2], c: &Constants) -> (Vec<u8>, Vec<u8>) {
        let (big_width, big_height) = (self.width, self.height);
        let count = (big_width * big_height) as usize;
        let mut out = vec![0u8; count * 4];
        let mut grown = vec![0u8; count];
        let scale = self.scale as f32;
        for k in (0..self.triangles.len()).step_by(3) {
            if (self.weights[k / 3] as f64) < 1.0 {
                continue;
            }
            let corner = |e: usize| self.triangles[k + e] as usize;
            let (c0, c1, c2) = (
                positions[corner(0)],
                positions[corner(1)],
                positions[corner(2)],
            );
            let rest = |e: usize| {
                let r = self.rest[corner(e)];
                Vector2::new(r.x * scale, r.y * scale)
            };
            let (s0, s1, s2) = (rest(0), rest(1), rest(2));
            let e1 = minus(c1, c0);
            let e2 = minus(c2, c0);
            let area = cross(e1, e2) as f64;
            if area <= 1e-6 {
                continue;
            }
            let (f1, f2) = (minus(s1, s0), minus(s2, s0));
            let determinant = f1.x * f2.y - f1.y * f2.x;
            let mut magnified = false;
            if (determinant as f64).abs() > 1e-6 {
                // Transform2D(e1, e2, 0) * Transform2D(f1, f2, 0).affine_inverse()
                let idet = 1.0f32 / determinant;
                let inverse_x = Vector2::new(f2.y * idet, f1.y * -idet);
                let inverse_y = Vector2::new(f2.x * -idet, f1.x * idet);
                let tdot = |v: Vector2| (e1.x * v.x + e2.x * v.y, e1.y * v.x + e2.y * v.y);
                let (gxx, gxy) = tdot(inverse_x);
                let (gyx, gyy) = tdot(inverse_y);
                let turn = global::atan2(gxy as f64 - gyx as f64, gxx as f64 + gyy as f64);
                let (a, b, cc, d) = (gxx as f64, gyx as f64, gxy as f64, gyy as f64);
                // MeshTools.largest_stretch
                let sum = a * a + b * b + cc * cc + d * d;
                let det = a * d - b * cc;
                let stretch = maxf(
                    (sum + maxf(sum * sum - 4.0 * det * det, 0.0).sqrt()) / 2.0,
                    0.0,
                )
                .sqrt();
                magnified = stretch >= c.magnified || turn.abs() >= c.turned;
            }
            let x0 = ((minf(c0.x as f64, minf(c1.x as f64, c2.x as f64))).floor() as i64).max(0);
            let y0 = ((minf(c0.y as f64, minf(c1.y as f64, c2.y as f64))).floor() as i64).max(0);
            let x1 = ((maxf(c0.x as f64, maxf(c1.x as f64, c2.x as f64))).ceil() as i64 + 1)
                .min(big_width);
            let y1 = ((maxf(c0.y as f64, maxf(c1.y as f64, c2.y as f64))).ceil() as i64 + 1)
                .min(big_height);
            for py in y0..y1 {
                for px in x0..x1 {
                    let d = minus(
                        Vector2::new((px as f64 + 0.5) as f32, (py as f64 + 0.5) as f32),
                        c0,
                    );
                    let u = cross(d, e2) as f64 / area;
                    let v = cross(e1, d) as f64 / area;
                    if u < -0.02 || v < -0.02 || u + v > 1.02 {
                        continue;
                    }
                    let source = plus(plus(s0, scaled(f1, u)), scaled(f2, v));
                    let q = if magnified {
                        self.smooth_covering(source)
                    } else {
                        self.nearest_covering(source)
                    };
                    let p = (py * big_width + px) as usize;
                    if magnified {
                        grown[p] = 1;
                    }
                    if q < 0 {
                        continue;
                    }
                    let q = q as usize;
                    out[p * 4..p * 4 + 4].copy_from_slice(&self.data[q * 4..q * 4 + 4]);
                }
            }
        }
        (out, grown)
    }

    /// `MeshDrawing.drawn`, the corners at `positions` (already made the key's size)
    pub fn drawn(&self, positions: &[Vector2], c: &Constants) -> Vec<u8> {
        let (big_width, big_height) = (self.width, self.height);
        let count = self.pixels.len();
        // MeshTools.Located.at
        let mut landed: Vec<Vector2> = (0..count)
            .map(|s| {
                let k = self.triangles_of[s] as usize * 3;
                let w = self.weights_of[s];
                let corner = |e: usize| positions[self.triangles[k + e] as usize];
                plus(
                    plus(scaled(corner(0), w.x as f64), scaled(corner(1), w.y as f64)),
                    scaled(corner(2), w.z as f64),
                )
            })
            .collect();
        let mut moves = Vec::with_capacity(count);
        let mut move_at = vec![-1i64; (big_width * big_height) as usize];
        for s in 0..count {
            let off = minus(landed[s], self.points[s]);
            moves.push(Vector2::new(off.x.round(), off.y.round()));
            move_at[self.pixels[s] as usize] = s as i64;
        }
        let mut chosen = Vec::with_capacity(count + self.strays.len() / 2);
        let mut tally = [0f64; 9];
        let mut found = [0usize; 9];
        let reach = c.alike_reach;
        for s in 0..count {
            let p = self.pixels[s] as i64;
            let (px, py) = (p % big_width, p / big_width);
            let own = moves[s];
            let mut kinds = 0;
            for dy in -reach..=reach {
                let qy = py + dy;
                if qy < 0 || qy >= big_height {
                    continue;
                }
                for dx in -reach..=reach {
                    let qx = px + dx;
                    if qx < 0 || qx >= big_width {
                        continue;
                    }
                    let other = move_at[(qy * big_width + qx) as usize];
                    if other < 0 {
                        continue;
                    }
                    let step = moves[other as usize];
                    let off_x = step.x as f64 - own.x as f64;
                    let off_y = step.y as f64 - own.y as f64;
                    if off_x.abs() > 1.0 || off_y.abs() > 1.0 {
                        continue;
                    }
                    let kind = (off_y + 1.0) as i64 as usize * 3 + (off_x + 1.0) as i64 as usize;
                    if tally[kind] == 0.0 {
                        found[kinds] = kind;
                        kinds += 1;
                    }
                    tally[kind] += 1.0;
                }
            }
            if tally[4] == 0.0 {
                found[kinds] = 4;
                kinds += 1;
            }
            tally[4] += c.own_move;
            let mut best = 4usize;
            let mut most = -1.0f64;
            for &kind in &found[..kinds] {
                if tally[kind] > most {
                    most = tally[kind];
                    best = kind;
                }
                tally[kind] = 0.0;
            }
            chosen.push(plus(
                own,
                Vector2::new((best % 3) as f32 - 1.0, (best / 3) as f32 - 1.0),
            ));
        }
        // Pixels off the triangles move with the nearest pixel on them
        let mut pixels: Vec<i64> = self.pixels.iter().map(|&p| p as i64).collect();
        for pair in self.strays.chunks_exact(2) {
            let (stray, on) = (pair[0] as i64, pair[1] as i64);
            let s = move_at[on as usize];
            // GDScript reads index -1 as the last
            let at = |len: usize| {
                if s < 0 {
                    (len as i64 + s) as usize
                } else {
                    s as usize
                }
            };
            pixels.push(stray);
            let s_chosen = at(chosen.len());
            chosen.push(chosen[s_chosen]);
            let apart = Vector2::new(
                (stray % big_width - on % big_width) as f32,
                (stray / big_width - on / big_width) as f32,
            );
            let s_landed = at(landed.len());
            landed.push(plus(landed[s_landed], apart));
        }
        let canvas = (big_width * big_height) as usize;
        let mut out = vec![0u8; canvas * 4];
        let mut front = vec![f32::NEG_INFINITY; canvas];
        let (mut low_x, mut low_y, mut high_x, mut high_y) = (big_width, big_height, -1i64, -1i64);
        for s in 0..pixels.len() {
            let p = pixels[s];
            let dest_x = p % big_width + chosen[s].x as i64;
            let dest_y = p / big_width + chosen[s].y as i64;
            if dest_x < 0 || dest_y < 0 || dest_x >= big_width || dest_y >= big_height {
                continue;
            }
            let small =
                (p / big_width / self.scale) * self.mesh_width + (p % big_width) / self.scale;
            let rank = if (small as usize) < self.depth.len() {
                self.depth[small as usize]
            } else {
                0
            };
            let middle = Vector2::new((dest_x as f32) + 0.5, (dest_y as f32) + 0.5);
            let apart = minus(landed[s], middle);
            let key = rank as f64 * 100.0 - (apart.x * apart.x + apart.y * apart.y).sqrt() as f64;
            let q = (dest_y * big_width + dest_x) as usize;
            if key < front[q] as f64 {
                continue;
            }
            front[q] = key as f32;
            let p = p as usize;
            out[q * 4..q * 4 + 4].copy_from_slice(&self.data[p * 4..p * 4 + 4]);
            low_x = low_x.min(dest_x);
            low_y = low_y.min(dest_y);
            high_x = high_x.max(dest_x);
            high_y = high_y.max(dest_y);
        }
        for k in (0..self.triangles.len()).step_by(3) {
            if (self.weights[k / 3] as f64) < 1.0 {
                continue;
            }
            for e in 0..3 {
                let corner = positions[self.triangles[k + e] as usize];
                low_x = low_x.min((corner.x as f64).floor() as i64);
                low_y = low_y.min((corner.y as f64).floor() as i64);
                high_x = high_x.max((corner.x as f64).ceil() as i64);
                high_y = high_y.max((corner.y as f64).ceil() as i64);
            }
        }
        if high_x < 0 {
            return out;
        }
        // Rect2i(low, high - low + ONE).grow(2) on the canvas
        let area = Area::intersection(
            (low_x - 2, low_y - 2),
            (high_x - low_x + 1 + 4, high_y - low_y + 1 + 4),
            (big_width, big_height),
        );
        let mut covered = vec![0u8; canvas];
        area.each(big_width, |p, _, _| {
            covered[p] = u8::from(out[p * 4 + 3] > 0)
        });
        let closed_covered = closed(&covered, big_width, big_height, area);
        let (over, grown) = self.drawn_over(positions, c);
        let mut over_shown = vec![0u8; canvas];
        area.each(big_width, |p, _, _| {
            over_shown[p] = u8::from(over[p * 4 + 3] > 0)
        });
        let over_closed = closed(&over_shown, big_width, big_height, area);
        area.each(big_width, |p, _, _| {
            let smooth = grown[p] == 1 && (over_shown[p] == 1 || over_closed[p] == 0);
            if smooth || (covered[p] == 0 && closed_covered[p] == 1 && over_shown[p] == 1) {
                out[p * 4..p * 4 + 4].copy_from_slice(&over[p * 4..p * 4 + 4]);
            }
        });
        out
    }
}
