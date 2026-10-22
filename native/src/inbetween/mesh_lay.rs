//! `MeshMatrix` (scripts/inbetween/mesh_matrix.gd) and `KeyMesh._lay`: laying a key's
//! triangles where pulls want them.

use godot::builtin::inner::InnerVector2;
use godot::global;
use godot::prelude::*;

/// `Vector2 * float` in GDScript: the number made a `real_t` first
fn scaled(v: Vector2, by: f64) -> Vector2 {
    let by = by as f32;
    Vector2::new(v.x * by, v.y * by)
}

fn divided(v: Vector2, by: f64) -> Vector2 {
    let by = by as f32;
    Vector2::new(v.x / by, v.y / by)
}

fn times(a: Vector2, b: Vector2) -> Vector2 {
    Vector2::new(a.x * b.x, a.y * b.y)
}

fn plus(a: Vector2, b: Vector2) -> Vector2 {
    Vector2::new(a.x + b.x, a.y + b.y)
}

fn minus(a: Vector2, b: Vector2) -> Vector2 {
    Vector2::new(a.x - b.x, a.y - b.y)
}

fn length_squared(v: Vector2) -> f32 {
    v.x * v.x + v.y * v.y
}

fn most(a: f64, b: f64) -> f64 {
    if a > b { a } else { b }
}

/// A `MeshMatrix`
pub struct Matrix<'a> {
    pub diagonal: Vec<f64>,
    pub sides: Vec<f64>,
    pub from: &'a [i32],
    pub to: &'a [i32],
}

impl Matrix<'_> {
    /// `MeshMatrix.times_into`
    fn times_into(&self, values: &[Vector2], result: &mut Vec<Vector2>) {
        result.clear();
        result.extend(
            values
                .iter()
                .zip(&self.diagonal)
                .map(|(&v, &d)| scaled(v, d)),
        );
        for e in 0..self.sides.len() {
            let a = self.from[e] as usize;
            let b = self.to[e] as usize;
            let amount = self.sides[e];
            result[a] = plus(result[a], scaled(values[b], amount));
            result[b] = plus(result[b], scaled(values[a], amount));
        }
    }

    /// `MeshMatrix.solve`
    pub fn solve(&self, x: &mut [Vector2], right: &[Vector2], steps: i64, close: f64) {
        let n = self.diagonal.len();
        let mut residual = Vec::with_capacity(n);
        self.times_into(x, &mut residual);
        let mut scaled_residual = vec![Vector2::ZERO; n];
        let mut along = Vector2::ZERO;
        let mut size = 1e-12f64;
        for i in 0..n {
            residual[i] = minus(right[i], residual[i]);
            scaled_residual[i] = divided(residual[i], self.diagonal[i]);
            along = plus(along, times(residual[i], scaled_residual[i]));
            size += length_squared(right[i]) as f64;
        }
        let mut direction = scaled_residual.clone();
        let mut pushed: Vec<Vector2> = Vec::with_capacity(n);
        for _ in 0..steps {
            let mut left = 0.0f64;
            for r in &residual {
                left += length_squared(*r) as f64;
            }
            if left <= close * close * size {
                break;
            }
            self.times_into(&direction, &mut pushed);
            let mut curve = Vector2::ZERO;
            for i in 0..n {
                curve = plus(curve, times(direction[i], pushed[i]));
            }
            let step = Vector2::new(
                (along.x as f64 / most(curve.x as f64, 1e-30)) as f32,
                (along.y as f64 / most(curve.y as f64, 1e-30)) as f32,
            );
            let mut next = Vector2::ZERO;
            for i in 0..n {
                x[i] = plus(x[i], times(direction[i], step));
                residual[i] = minus(residual[i], times(pushed[i], step));
                scaled_residual[i] = divided(residual[i], self.diagonal[i]);
                next = plus(next, times(residual[i], scaled_residual[i]));
            }
            let keep = Vector2::new(
                (next.x as f64 / most(along.x as f64, 1e-30)) as f32,
                (next.y as f64 / most(along.y as f64, 1e-30)) as f32,
            );
            for i in 0..n {
                direction[i] = plus(scaled_residual[i], times(direction[i], keep));
            }
            along = next;
        }
    }
}

/// What `KeyMesh._lay` reads of the mesh
pub struct Mesh<'a> {
    pub rest: &'a [Vector2],
    pub triangles: &'a [i32],
    pub weights: &'a [f32],
    pub side_from: &'a [i32],
    pub side_to: &'a [i32],
    pub triangle_sides: &'a [i32],
    pub laplacian_diagonal: &'a [f64],
    pub laplacian_sides: &'a [f64],
    pub stiff_total: f64,
}

/// Pixels of a key pulled somewhere: their triangles and how far along each corner, where
/// to and how hard
pub struct Pulled<'a> {
    pub triangles: &'a [i32],
    pub weights: &'a [Vector3],
    pub samples: Option<&'a [i32]>,
    pub goals: &'a [Vector2],
    pub pulls: &'a [f32],
}

impl Mesh<'_> {
    /// `KeyMesh._add_pull`
    fn add_pull(
        &self,
        matrix: &mut Matrix,
        right: &mut [Vector2],
        s: usize,
        goal: Vector2,
        pull: f64,
        pulled: &Pulled,
    ) {
        if pull <= 0.0 {
            return;
        }
        let k = pulled.triangles[s] as usize * 3;
        let w = pulled.weights[s];
        let (wx, wy, wz) = (w.x as f64, w.y as f64, w.z as f64);
        let corners = [(wx, wy), (wy, wz), (wz, wx)];
        for (e, (along, next)) in corners.into_iter().enumerate() {
            let i = self.triangles[k + e] as usize;
            matrix.diagonal[i] += pull * along * along;
            right[i] = plus(right[i], scaled(goal, pull * along));
            matrix.sides[self.triangle_sides[k + e] as usize] += pull * along * next;
        }
    }

    /// `KeyMesh._triangle_turns`, from where the corners rest
    pub fn triangle_turns(&self, positions: &[Vector2]) -> Vec<f32> {
        let rest = self.rest;
        let corners = self.triangles;
        let mut result = Vec::with_capacity(corners.len() / 3);
        for k in (0..corners.len()).step_by(3) {
            let at = |list: &[Vector2], e: usize| list[corners[k + e] as usize];
            let (r0, r1, r2) = (at(rest, 0), at(rest, 1), at(rest, 2));
            let (q0, q1, q2) = (at(positions, 0), at(positions, 1), at(positions, 2));
            let rm = divided(plus(plus(r0, r1), r2), 3.0);
            let qm = divided(plus(plus(q0, q1), q2), 3.0);
            let dot = |a: Vector2, b: Vector2| (a.x * b.x + a.y * b.y) as f64;
            let cross = |a: Vector2, b: Vector2| (a.x * b.y - a.y * b.x) as f64;
            let (d0, d1, d2) = (minus(r0, rm), minus(r1, rm), minus(r2, rm));
            let (e0, e1, e2) = (minus(q0, qm), minus(q1, qm), minus(q2, qm));
            let dots = dot(d0, e0) + dot(d1, e1) + dot(d2, e2);
            let crosses = cross(d0, e0) + cross(d1, e1) + cross(d2, e2);
            result.push(global::atan2(crosses, dots) as f32);
        }
        result
    }

    /// `KeyMesh._pulls` with no stretches, each triangle counting its weight, from where
    /// the corners rest
    fn turned_pulls(&self, turns: &[f32]) -> Vec<Vector2> {
        let mut result = vec![Vector2::ZERO; self.rest.len()];
        for k in (0..self.triangles.len()).step_by(3) {
            let t = k / 3;
            let w = self.weights[t] as f64;
            if w <= 0.0 {
                continue;
            }
            let turn = turns[t] as f64;
            for e in 0..3 {
                let from = self.triangles[k + e] as usize;
                let to = self.triangles[k + (e + 1) % 3] as usize;
                let side = minus(self.rest[to], self.rest[from]);
                let side = scaled(InnerVector2::from_outer(&side).rotated(turn), w * 1.0);
                result[to] = plus(result[to], side);
                result[from] = minus(result[from], side);
            }
        }
        result
    }

    /// `KeyMesh._lay`: where the corners end up from `target`
    pub fn lay(
        &self,
        target: &mut [Vector2],
        pixels: &Pulled,
        extra: &Pulled,
        stiffness: f64,
        rounds: i64,
        solving: (i64, f64),
    ) {
        let n = self.rest.len();
        let mut matrix = Matrix {
            diagonal: vec![0.0; n],
            sides: vec![0.0; self.side_from.len()],
            from: self.side_from,
            to: self.side_to,
        };
        let mut data_side = vec![Vector2::ZERO; n];
        let mut pulled = 0.0f64;
        for s in 0..pixels.pulls.len() {
            pulled += pixels.pulls[s] as f64;
            self.add_pull(
                &mut matrix,
                &mut data_side,
                s,
                pixels.goals[s],
                pixels.pulls[s] as f64,
                pixels,
            );
        }
        let samples = extra.samples.unwrap_or(&[]);
        for (e, &s) in samples.iter().enumerate() {
            pulled += extra.pulls[e] as f64;
            self.add_pull(
                &mut matrix,
                &mut data_side,
                s as usize,
                extra.goals[e],
                extra.pulls[e] as f64,
                extra,
            );
        }
        let scale = stiffness * pulled / most(self.stiff_total, 1e-9) * 3.0;
        for i in 0..n {
            matrix.diagonal[i] += self.laplacian_diagonal[i] * scale;
        }
        for e in 0..matrix.sides.len() {
            matrix.sides[e] += self.laplacian_sides[e] * scale;
        }
        for d in &mut matrix.diagonal {
            *d += 1e-6;
        }
        for _ in 0..rounds {
            let turns = self.triangle_turns(target);
            let wanted = self.turned_pulls(&turns);
            let right: Vec<Vector2> = (0..n)
                .map(|i| {
                    plus(
                        plus(scaled(wanted[i], scale), data_side[i]),
                        scaled(target[i], 1e-6),
                    )
                })
                .collect();
            matrix.solve(target, &right, solving.0, solving.1);
        }
    }
}
