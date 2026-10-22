//! The in-betweens' hottest loops (see `scripts/inbetween/`), called by
//! `scripts/inbetween/native_kernels.gd` when the library is loaded. Each does the same sums
//! in the same order as the GDScript it stands in for, so frames come out the same to the
//! bit: GDScript's `float` is `f64`, while `Vector2` and `PackedFloat32Array` hold `f32`.
//! Sines and exponentials are asked of Godot, as its own can differ from Rust's in the last
//! bit. Nothing is kept between calls, so threads can call them at once.

mod cleanup;
mod drawing;
mod flow;
mod key_features;
mod mesh_lay;
mod mesh_matching;
mod outlines;
mod pixels;
mod region_motions;
mod regions;
mod sort;

use godot::prelude::*;

use key_features::Features;
use mesh_matching::{Matching, Pulls};

/// See the module's description. Its functions are static, and called on threads.
#[derive(GodotClass)]
#[class(base = RefCounted, init)]
pub struct InBetweenKernels {
    base: Base<RefCounted>,
}

#[godot_api]
impl InBetweenKernels {
    /// `MeshMatching.pixel_matches`, see [`matching`] for `size`, `arrays` and `numbers`:
    /// `[goals, pulls]`
    #[func]
    fn pixel_matches(
        size: Vector2i,
        arrays: VarArray,
        numbers: PackedFloat64Array,
        start: i64,
        end: i64,
    ) -> VarArray {
        let held = Held::of(&arrays);
        let (matching, pulls) = matching(size, &held, numbers.as_slice());
        let (goals, pulls) = matching.pixel_matches(start as usize, end as usize, &pulls);
        varray![
            &PackedVector2Array::from(goals),
            &PackedFloat32Array::from(pulls)
        ]
    }

    /// `MeshMatching.edge_pulls`, see [`matching`] for `size`, `arrays` and `numbers`:
    /// `[samples, goals, pulls]`
    #[func]
    fn edge_pulls(
        size: Vector2i,
        arrays: VarArray,
        numbers: PackedFloat64Array,
        start: i64,
        end: i64,
    ) -> VarArray {
        let held = Held::of(&arrays);
        let (matching, pulls) = matching(size, &held, numbers.as_slice());
        let (samples, goals, pulls) = matching.edge_pulls(start as usize, end as usize, &pulls);
        varray![
            &PackedInt32Array::from(samples),
            &PackedVector2Array::from(goals),
            &PackedFloat32Array::from(pulls)
        ]
    }

    /// `KeyFeatures.landing_sum` of features `values` (a canvas `width` pixels wide) on
    /// the `other_values` (a canvas `other_size`), or `landing_sum_below` given up once
    /// over `bound` (no bound when infinite)
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn landing_sum(
        values: PackedFloat32Array,
        width: i64,
        pixels: PackedInt32Array,
        stride: i64,
        motion: Transform2D,
        other_values: PackedFloat32Array,
        other_size: Vector2i,
        cap: f64,
        move_cost: f64,
        shift: Vector2,
        bound: f64,
    ) -> f64 {
        let own = Features {
            width,
            height: 0,
            values: values.as_slice(),
        };
        let other = Features {
            width: other_size.x as i64,
            height: other_size.y as i64,
            values: other_values.as_slice(),
        };
        own.landing_sum(
            pixels.as_slice(),
            stride.max(1) as usize,
            motion,
            &other,
            cap,
            move_cost,
            shift,
            bound,
        )
    }

    /// `PixelCanvas.distances`
    #[func]
    fn distances(
        mask: PackedByteArray,
        width: i64,
        height: i64,
        value: i64,
        far: i64,
    ) -> Array<PackedInt32Array> {
        let (distance, nearest) = pixels::distances(
            mask.as_slice(),
            width as usize,
            height as usize,
            value as u8,
            far,
        );
        array![
            &PackedInt32Array::from(distance),
            &PackedInt32Array::from(nearest)
        ]
    }

    /// `KeyFeatures.of`'s values; `weights` are `SHOWN_WEIGHT`, `DEPTH_WEIGHT` and
    /// `DEPTH_REACH`
    #[func]
    fn features_of(
        data: PackedByteArray,
        width: i64,
        height: i64,
        depth_scale: f64,
        weights: PackedFloat64Array,
    ) -> PackedFloat32Array {
        let weights = weights.as_slice();
        let weights = pixels::FeatureWeights {
            shown: weights[0],
            depth: weights[1],
            depth_reach: weights[2],
        };
        let values = pixels::features_of(
            data.as_slice(),
            width as usize,
            height as usize,
            depth_scale,
            &weights,
        );
        PackedFloat32Array::from(values)
    }

    /// `MeshTools.edges`
    #[func]
    fn edges(
        colors: PackedFloat32Array,
        width: i64,
        height: i64,
        least_step: f64,
    ) -> PackedByteArray {
        let found = pixels::edges(
            colors.as_slice(),
            width as usize,
            height as usize,
            least_step,
        );
        PackedByteArray::from(found)
    }

    /// `ShapeBlend._warp`: `[cost, moves]`, moves empty unless `writing`
    #[func]
    fn warp(
        costs: PackedFloat32Array,
        n: i64,
        m: i64,
        start: i64,
        step_cost: f64,
        writing: bool,
    ) -> VarArray {
        let (cost, moves) = outlines::warp(
            costs.as_slice(),
            n as usize,
            m as usize,
            start as usize,
            step_cost,
            writing,
        );
        varray![cost, &PackedByteArray::from(moves)]
    }

    /// `RegionMotions._search_pixels` for `pixels`, see [`motions`] for `arrays` (then the
    /// other key's shown pixels' places and colours) and `numbers`
    #[func]
    fn search_pixels(
        pixels: PackedInt32Array,
        arrays: VarArray,
        numbers: PackedFloat64Array,
    ) -> Array<Transform2D> {
        let held = MotionsHeld::of(&arrays);
        let places: PackedVector2Array = arrays.at(2).to();
        let colours: PackedVector3Array = arrays.at(3).to();
        let motions = motions(&held, numbers.as_slice());
        let found = motions.search_pixels(pixels.as_slice(), places.as_slice(), colours.as_slice());
        found.into_iter().collect()
    }

    /// `RegionMotions._own_best` for the regions with `pixels`, see [`motions`] for
    /// `arrays` and `numbers`: `[best few, costs]`
    #[func]
    fn own_best(
        pixels: Array<PackedInt32Array>,
        candidates: Array<Transform2D>,
        arrays: VarArray,
        numbers: PackedFloat64Array,
    ) -> VarArray {
        let held = MotionsHeld::of(&arrays);
        let motions = motions(&held, numbers.as_slice());
        let candidates: Vec<Transform2D> = candidates.iter_shared().collect();
        let mut own: Array<PackedInt32Array> = Array::new();
        let mut costs: Array<PackedFloat64Array> = Array::new();
        for region in pixels.iter_shared() {
            let (best, row) = motions.own_best(region.as_slice(), &candidates);
            own.push(&PackedInt32Array::from(best));
            costs.push(&PackedFloat64Array::from(row));
        }
        varray![&own, &costs]
    }

    /// `RegionMotions._apart_tables`: for each pair of bordering regions in `pairs`
    /// (`r` and `s` after one another) with `borders`, what each two of their `choices`
    /// cost together; `pixels` and `colours` are the regions', on a canvas `width` pixels
    /// wide, and `numbers` as for [`motions`]
    #[func]
    fn apart_tables(
        pairs: PackedInt32Array,
        borders: Array<PackedVector2Array>,
        choices: AnyArray,
        regions: VarArray,
        width: i64,
        numbers: PackedFloat64Array,
    ) -> VarArray {
        let pixels: Array<PackedInt32Array> = regions.at(0).to();
        let colours: PackedVector3Array = regions.at(1).to();
        let constants = region_motions::Constants::of(numbers.as_slice());
        let choices_of = |r: usize| -> Vec<Transform2D> {
            let list: Array<Transform2D> = choices.at(r).to();
            list.iter_shared().collect()
        };
        let pairs = pairs.as_slice();
        let mut tables = VarArray::new();
        for (n, points) in borders.iter_shared().enumerate() {
            let (r, s) = (pairs[n * 2] as usize, pairs[n * 2 + 1] as usize);
            let (r_pixels, s_pixels) = (pixels.at(r), pixels.at(s));
            let (r_choices, s_choices) = (choices_of(r), choices_of(s));
            let border = region_motions::Border {
                points: points.as_slice(),
                r_pixels: r_pixels.as_slice(),
                s_pixels: s_pixels.as_slice(),
                r_colour: colours.as_slice()[r],
                s_colour: colours.as_slice()[s],
                r_choices: &r_choices,
                s_choices: &s_choices,
            };
            let table: Array<PackedFloat32Array> =
                region_motions::apart_costs(&border, width, &constants)
                    .into_iter()
                    .map(PackedFloat32Array::from)
                    .collect();
            tables.push(&table.to_variant());
        }
        tables
    }

    /// `KeyRegions.from_labels`: `[pixels, centers, colors, axes, elongations, border
    /// pairs (one after the other, in the order found), border points]`
    #[func]
    fn regions_from_labels(
        data: PackedByteArray,
        width: i64,
        labels: PackedInt32Array,
    ) -> VarArray {
        let found = regions::from_labels(data.as_slice(), width as usize, labels.as_slice());
        let pixels: Array<PackedInt32Array> = found
            .pixels
            .into_iter()
            .map(PackedInt32Array::from)
            .collect();
        let pairs: Vec<i32> = found
            .border_keys
            .iter()
            .flat_map(|&(r, s)| [r, s])
            .collect();
        let borders: Array<PackedVector2Array> = found
            .borders
            .into_iter()
            .map(PackedVector2Array::from)
            .collect();
        varray![
            &pixels,
            &PackedVector2Array::from(found.centers),
            &PackedVector3Array::from(found.colors),
            &PackedFloat32Array::from(found.axes),
            &PackedFloat32Array::from(found.elongations),
            &PackedInt32Array::from(pairs),
            &borders
        ]
    }

    /// `PieceMorph._shrunk`
    #[func]
    fn shrunk(data: PackedByteArray, width: i64, height: i64, shrink: i64) -> PackedByteArray {
        let out = regions::shrunk(
            data.as_slice(),
            width as usize,
            height as usize,
            shrink as usize,
        );
        PackedByteArray::from(out)
    }

    /// `MeshMatrix.solve` for the matrix `diagonal` and `sides` (between corners `from` and
    /// `to`): `x` solved
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn solve(
        diagonal: PackedFloat64Array,
        sides: PackedFloat64Array,
        from: PackedInt32Array,
        to: PackedInt32Array,
        x: PackedVector2Array,
        right: PackedVector2Array,
        steps: i64,
        close: f64,
    ) -> PackedVector2Array {
        let matrix = mesh_lay::Matrix {
            diagonal: diagonal.as_slice().to_vec(),
            sides: sides.as_slice().to_vec(),
            from: from.as_slice(),
            to: to.as_slice(),
        };
        let mut solved = x.as_slice().to_vec();
        matrix.solve(&mut solved, right.as_slice(), steps, close);
        PackedVector2Array::from(solved)
    }

    /// `KeyMesh._lay`: where the corners end up. `mesh` holds the mesh's `rest`, `target`,
    /// `triangles`, `weights`, `_side_from`, `_side_to`, `_triangle_sides` and its
    /// laplacian's diagonal and sides; `pulled` the located pixels' triangles and weights,
    /// their goals and pulls, then the extra ones'; `numbers` the stiffness total, the
    /// stiffness, the rounds and the solver's steps and closeness
    #[func]
    fn lay(mesh: VarArray, pulled: VarArray, numbers: PackedFloat64Array) -> PackedVector2Array {
        let rest: PackedVector2Array = mesh.at(0).to();
        let target: PackedVector2Array = mesh.at(1).to();
        let triangles: PackedInt32Array = mesh.at(2).to();
        let weights: PackedFloat32Array = mesh.at(3).to();
        let side_from: PackedInt32Array = mesh.at(4).to();
        let side_to: PackedInt32Array = mesh.at(5).to();
        let triangle_sides: PackedInt32Array = mesh.at(6).to();
        let laplacian_diagonal: PackedFloat64Array = mesh.at(7).to();
        let laplacian_sides: PackedFloat64Array = mesh.at(8).to();
        let located_triangles: PackedInt32Array = pulled.at(0).to();
        let located_weights: PackedVector3Array = pulled.at(1).to();
        let goals: PackedVector2Array = pulled.at(2).to();
        let pulls: PackedFloat32Array = pulled.at(3).to();
        let extra: PackedInt32Array = pulled.at(4).to();
        let extra_goals: PackedVector2Array = pulled.at(5).to();
        let extra_pulls: PackedFloat32Array = pulled.at(6).to();
        let numbers = numbers.as_slice();
        let laid = mesh_lay::Mesh {
            rest: rest.as_slice(),
            triangles: triangles.as_slice(),
            weights: weights.as_slice(),
            side_from: side_from.as_slice(),
            side_to: side_to.as_slice(),
            triangle_sides: triangle_sides.as_slice(),
            laplacian_diagonal: laplacian_diagonal.as_slice(),
            laplacian_sides: laplacian_sides.as_slice(),
            stiff_total: numbers[0],
        };
        let pixels = mesh_lay::Pulled {
            triangles: located_triangles.as_slice(),
            weights: located_weights.as_slice(),
            samples: None,
            goals: goals.as_slice(),
            pulls: pulls.as_slice(),
        };
        let extra = mesh_lay::Pulled {
            samples: Some(extra.as_slice()),
            goals: extra_goals.as_slice(),
            pulls: extra_pulls.as_slice(),
            ..pixels
        };
        let mut laid_target = target.as_slice().to_vec();
        let solving = (numbers[3] as i64, numbers[4]);
        laid.lay(
            &mut laid_target,
            &pixels,
            &extra,
            numbers[1],
            numbers[2] as i64,
            solving,
        );
        PackedVector2Array::from(laid_target)
    }

    /// `MeshDrawing.drawn` with the corners at `positions` (made the key's size): `drawing`
    /// holds the key drawn bigger, its points, pixels, triangles and weights, its strays,
    /// and the mesh's depth, triangles, weights and rest; `numbers` the key's scale, width
    /// and height, the mesh's width, and `ALIKE_REACH`, `OWN_MOVE`, `MAGNIFIED` and `TURNED`
    #[func]
    fn drawn(
        drawing: VarArray,
        positions: PackedVector2Array,
        numbers: PackedFloat64Array,
    ) -> PackedByteArray {
        let data: PackedByteArray = drawing.at(0).to();
        let points: PackedVector2Array = drawing.at(1).to();
        let pixels: PackedInt32Array = drawing.at(2).to();
        let triangles_of: PackedInt32Array = drawing.at(3).to();
        let weights_of: PackedVector3Array = drawing.at(4).to();
        let strays: PackedInt32Array = drawing.at(5).to();
        let depth: PackedInt32Array = drawing.at(6).to();
        let triangles: PackedInt32Array = drawing.at(7).to();
        let weights: PackedFloat32Array = drawing.at(8).to();
        let rest: PackedVector2Array = drawing.at(9).to();
        let numbers = numbers.as_slice();
        let drawn = drawing::Drawing {
            data: data.as_slice(),
            scale: numbers[0] as i64,
            width: numbers[1] as i64,
            height: numbers[2] as i64,
            points: points.as_slice(),
            pixels: pixels.as_slice(),
            triangles_of: triangles_of.as_slice(),
            weights_of: weights_of.as_slice(),
            strays: strays.as_slice(),
            mesh_width: numbers[3] as i64,
            depth: depth.as_slice(),
            triangles: triangles.as_slice(),
            weights: weights.as_slice(),
            rest: rest.as_slice(),
        };
        let constants = drawing::Constants {
            alike_reach: numbers[4] as i64,
            own_move: numbers[5],
            magnified: numbers[6],
            turned: numbers[7],
        };
        PackedByteArray::from(drawn.drawn(positions.as_slice(), &constants))
    }

    /// `FlowMorph._moved`: `data` moved `t` of the way by `flow`; `numbers` hold the
    /// canvas's width and height, `_keys_area`'s start and end, and `MOST_STRETCH` and
    /// `CLOSE`
    #[func]
    fn flow_moved(
        data: PackedByteArray,
        flow: PackedVector2Array,
        doubt: PackedFloat32Array,
        t: f64,
        numbers: PackedFloat64Array,
    ) -> PackedByteArray {
        let n = numbers.as_slice();
        let moving = flow::Moving {
            width: n[0] as i64,
            height: n[1] as i64,
            area: (n[2] as i64, n[3] as i64, n[4] as i64, n[5] as i64),
            flow: flow.as_slice(),
            doubt: doubt.as_slice(),
            most_stretch: n[6] as i64,
            close: n[7],
        };
        PackedByteArray::from(moving.moved(data.as_slice(), t))
    }

    /// `PixelCleanup.tidy_data`: `data` tidied
    #[func]
    fn tidy_data(data: PackedByteArray, width: i64, height: i64) -> PackedByteArray {
        let mut tidied = data.as_slice().to_vec();
        cleanup::tidy_data(&mut tidied, width, height);
        PackedByteArray::from(tidied)
    }

    /// `PixelCleanup.smooth_jags`: `data` smoothed, `wide_shapes` given as a list
    #[func]
    fn smooth_jags(
        data: PackedByteArray,
        width: i64,
        height: i64,
        shapes: PackedInt32Array,
        least_alpha: i64,
        wide_shapes: PackedInt64Array,
    ) -> PackedByteArray {
        let mut smoothed = data.as_slice().to_vec();
        let wide: std::collections::HashSet<i64> = wide_shapes.as_slice().iter().copied().collect();
        cleanup::smooth_jags(
            &mut smoothed,
            width,
            height,
            shapes.as_slice(),
            least_alpha as u8,
            &wide,
        );
        PackedByteArray::from(smoothed)
    }

    /// `PixelCleanup.shapes_of`
    #[func]
    fn shapes_of(
        data: PackedByteArray,
        width: i64,
        height: i64,
        least_alpha: i64,
    ) -> PackedInt32Array {
        PackedInt32Array::from(cleanup::shapes_of(
            data.as_slice(),
            width,
            height,
            least_alpha as u8,
        ))
    }

    /// `PixelCleanup.wide_shapes_of`: the shapes, in the order first found
    #[func]
    fn wide_shapes_of(
        data: PackedByteArray,
        width: i64,
        height: i64,
        least_alpha: i64,
    ) -> PackedInt64Array {
        PackedInt64Array::from(cleanup::wide_shapes_of(
            data.as_slice(),
            width,
            height,
            least_alpha as u8,
        ))
    }

    /// Godot's `Vector2` and `Transform2D` sums as worked out here, for each of `motions`
    /// with two of `points` after one another: `motion * a`, `a.length_squared()`,
    /// `a.dot(b)`, `a.cross(b)`, `a.distance_to(b)`, `a.distance_squared_to(b)`, the
    /// motion's determinant and `Transform2D(a, b, Vector2.ZERO) * motion.affine_inverse()`.
    /// Godot built to fuse multiplications and additions would differ: then the GDScript
    /// is used (see `NativeKernels`).
    #[func]
    fn engine_math(points: PackedVector2Array, motions: Array<Transform2D>) -> PackedFloat64Array {
        let points = points.as_slice();
        let mut found = Vec::new();
        for (k, motion) in motions.iter_shared().enumerate() {
            let (a, b) = (points[k * 2], points[k * 2 + 1]);
            let moved = region_motions::xform(motion, a);
            let (dx, dy) = (a.x - b.x, a.y - b.y);
            let determinant = motion.a.x * motion.b.y - motion.a.y * motion.b.x;
            let idet = 1.0f32 / determinant;
            let inverse_x = Vector2::new(motion.b.y * idet, motion.a.y * -idet);
            let inverse_y = Vector2::new(motion.b.x * -idet, motion.a.x * idet);
            let tdot = |v: Vector2| [a.x * v.x + b.x * v.y, a.y * v.x + b.y * v.y];
            let numbers = [
                moved.x,
                moved.y,
                a.x * a.x + a.y * a.y,
                a.x * b.x + a.y * b.y,
                a.x * b.y - a.y * b.x,
                (dx * dx + dy * dy).sqrt(),
                dx * dx + dy * dy,
                determinant,
            ];
            found.extend(
                numbers
                    .iter()
                    .chain(&tdot(inverse_x))
                    .chain(&tdot(inverse_y))
                    .map(|&n| n as f64),
            );
        }
        PackedFloat64Array::from(found)
    }

    /// Indices of `keys` sorted as `Array.sort_custom` sorts them, by key: to test that
    /// sorting here orders ties as Godot does
    #[func]
    fn sorted_by_key(keys: PackedFloat64Array) -> PackedInt32Array {
        let keys = keys.as_slice();
        let mut order: Vec<i32> = (0..keys.len() as i32).collect();
        sort::sort_custom(&mut order, |x, y| keys[*x as usize] < keys[*y as usize]);
        PackedInt32Array::from(order)
    }
}

/// The packed arrays a `RegionMotions` reads, in the order `NativeKernels` gives them: the
/// key's features and the other's
struct MotionsHeld {
    features: PackedFloat32Array,
    other: PackedFloat32Array,
}

impl MotionsHeld {
    fn of(arrays: &VarArray) -> Self {
        Self {
            features: arrays.at(0).to(),
            other: arrays.at(1).to(),
        }
    }
}

/// A `RegionMotions` with `held`'s arrays and `numbers`: the canvas width of the key's
/// regions and of its features, the other's features' width and height, the whole sprite's shift (x and y) and size, then
/// [`region_motions::Constants`]
fn motions<'a>(held: &'a MotionsHeld, numbers: &[f64]) -> region_motions::Motions<'a> {
    region_motions::Motions {
        width: numbers[0] as i64,
        features: Features {
            width: numbers[1] as i64,
            height: 0,
            values: held.features.as_slice(),
        },
        other: Features {
            width: numbers[2] as i64,
            height: numbers[3] as i64,
            values: held.other.as_slice(),
        },
        shift: Vector2::new(numbers[4] as f32, numbers[5] as f32),
        side: numbers[6],
        constants: region_motions::Constants::of(&numbers[7..]),
    }
}

/// The packed arrays a `MeshMatching` reads, in the order `NativeKernels` gives them
struct Held {
    own: PackedFloat32Array,
    others: PackedFloat32Array,
    own_edges: PackedByteArray,
    pixels: PackedInt32Array,
    triangles: PackedInt32Array,
    turns: PackedFloat32Array,
    landed: PackedVector2Array,
    spot_x: PackedInt32Array,
    spot_y: PackedInt32Array,
    spot_least: PackedFloat64Array,
    edges: PackedInt32Array,
}

impl Held {
    fn of(arrays: &VarArray) -> Self {
        Self {
            own: arrays.at(0).to(),
            others: arrays.at(1).to(),
            own_edges: arrays.at(2).to(),
            pixels: arrays.at(3).to(),
            triangles: arrays.at(4).to(),
            turns: arrays.at(5).to(),
            landed: arrays.at(6).to(),
            spot_x: arrays.at(7).to(),
            spot_y: arrays.at(8).to(),
            spot_least: arrays.at(9).to(),
            edges: arrays.at(10).to(),
        }
    }
}

/// A `MeshMatching` on a canvas `size`, with `held`'s arrays, and `numbers`: what being a
/// pixel away costs, the cells' size, and `KeyMesh`'s `FLAT_PULL`, `EDGE_PULL` and
/// `LIKENESS`
fn matching<'a>(size: Vector2i, held: &'a Held, numbers: &[f64]) -> (Matching<'a>, Pulls) {
    let matching = Matching {
        width: size.x as i64,
        height: size.y as i64,
        own: held.own.as_slice(),
        others: held.others.as_slice(),
        own_edges: held.own_edges.as_slice(),
        pixels: held.pixels.as_slice(),
        triangles: held.triangles.as_slice(),
        turns: held.turns.as_slice(),
        landed: held.landed.as_slice(),
        spot_x: held.spot_x.as_slice(),
        spot_y: held.spot_y.as_slice(),
        spot_least: held.spot_least.as_slice(),
        near_cost: numbers[0],
        cell: numbers[1],
        edges: held.edges.as_slice(),
    };
    let pulls = Pulls {
        flat: numbers[2],
        edge: numbers[3],
        likeness: numbers[4],
    };
    (matching, pulls)
}
