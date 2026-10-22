//! `KeyRegions.from_labels` and `PieceMorph._shrunk`.

use godot::global;
use godot::prelude::*;

/// What `KeyRegions.from_labels` works out, see `KeyRegions`' variables
pub struct Regions {
    pub pixels: Vec<Vec<i32>>,
    pub centers: Vec<Vector2>,
    pub colors: Vec<Vector3>,
    pub axes: Vec<f32>,
    pub elongations: Vec<f32>,
    /// Bordering pairs in the order first found, and the points along each border
    pub border_keys: Vec<(i32, i32)>,
    pub borders: Vec<Vec<Vector2>>,
}

/// `KeyRegions.point_of`
fn point_of(p: usize, width: usize) -> Vector2 {
    Vector2::new(
        ((p % width) as f64 + 0.5) as f32,
        ((p / width) as f64 + 0.5) as f32,
    )
}

fn max(a: f64, b: f64) -> f64 {
    if a > b { a } else { b }
}

/// `KeyRegions.from_labels`
pub fn from_labels(data: &[u8], width: usize, labels: &[i32]) -> Regions {
    let count = labels
        .iter()
        .fold(0i64, |most, &label| most.max(label as i64 + 1)) as usize;
    let mut pixels: Vec<Vec<i32>> = vec![Vec::new(); count];
    for (p, &label) in labels.iter().enumerate() {
        if label >= 0 {
            pixels[label as usize].push(p as i32);
        }
    }
    // KeyRegions._average_colors
    let mut colors = vec![Vector3::ZERO; count];
    let mut sizes = vec![0i64; count];
    for (p, &r) in labels.iter().enumerate() {
        if r >= 0 {
            let r = r as usize;
            let i = p * 4;
            let color = Vector3::new(
                data[i] as f32 / 255.0,
                data[i + 1] as f32 / 255.0,
                data[i + 2] as f32 / 255.0,
            );
            colors[r] = Vector3::new(
                colors[r].x + color.x,
                colors[r].y + color.y,
                colors[r].z + color.z,
            );
            sizes[r] += 1;
        }
    }
    for r in 0..count {
        if sizes[r] > 0 {
            let size = sizes[r] as f32;
            colors[r] = Vector3::new(colors[r].x / size, colors[r].y / size, colors[r].z / size);
        }
    }
    // KeyRegions._shape
    let mut centers = Vec::with_capacity(count);
    let mut axes = Vec::with_capacity(count);
    let mut elongations = Vec::with_capacity(count);
    for points in &pixels {
        let mut middle = Vector2::ZERO;
        for &p in points {
            let point = point_of(p as usize, width);
            middle = Vector2::new(middle.x + point.x, middle.y + point.y);
        }
        let size = points.len().max(1) as f32;
        let middle = Vector2::new(middle.x / size, middle.y / size);
        centers.push(middle);
        let (mut xx, mut xy, mut yy) = (0.0f64, 0.0f64, 0.0f64);
        for &p in points {
            let point = point_of(p as usize, width);
            let (dx, dy) = ((point.x - middle.x) as f64, (point.y - middle.y) as f64);
            xx += dx * dx;
            xy += dx * dy;
            yy += dy * dy;
        }
        let trace = xx + yy;
        let gap = max((xx - yy) * (xx - yy) + 4.0 * xy * xy, 0.0).sqrt();
        let big = (trace + gap) / 2.0;
        let small = max((trace - gap) / 2.0, 1e-3 * points.len() as f64);
        axes.push((0.5 * global::atan2(2.0 * xy, xx - yy)) as f32);
        elongations.push((max(big, 1e-6) / small).sqrt() as f32);
    }
    // Borders: midway between pixels of two regions side by side
    let mut border_keys: Vec<(i32, i32)> = Vec::new();
    let mut borders: Vec<Vec<Vector2>> = Vec::new();
    let mut index: std::collections::HashMap<(i32, i32), usize> = std::collections::HashMap::new();
    for (p, &label) in labels.iter().enumerate() {
        if label < 0 {
            continue;
        }
        for side in [1, width] {
            let q = p + side;
            if q >= labels.len() {
                continue;
            }
            let other = labels[q];
            if other < 0 || other == label {
                continue;
            }
            let key = (label.min(other), label.max(other));
            let k = *index.entry(key).or_insert_with(|| {
                border_keys.push(key);
                borders.push(Vec::new());
                borders.len() - 1
            });
            let (a, b) = (point_of(p, width), point_of(q, width));
            borders[k].push(Vector2::new((a.x + b.x) / 2.0, (a.y + b.y) / 2.0));
        }
    }
    Regions {
        pixels,
        centers,
        colors,
        axes,
        elongations,
        border_keys,
        borders,
    }
}

/// `PieceMorph._shrunk`: `data` (a canvas `width` × `height`) `shrink` times smaller
pub fn shrunk(data: &[u8], width: usize, height: usize, shrink: usize) -> Vec<u8> {
    let small_width = (width as f64 / shrink as f64).ceil() as usize;
    let small_height = (height as f64 / shrink as f64).ceil() as usize;
    let mut out = vec![0u8; small_width * small_height * 4];
    let round = |value: f64| value.round() as i64 as u8;
    for sy in 0..small_height {
        for sx in 0..small_width {
            let mut sum = [0f32; 4];
            let mut count = 0i64;
            for y in sy * shrink..((sy + 1) * shrink).min(height) {
                for x in sx * shrink..((sx + 1) * shrink).min(width) {
                    let i = (y * width + x) * 4;
                    let alpha = data[i + 3] as i64;
                    sum[0] += (data[i] as i64 * alpha) as f32;
                    sum[1] += (data[i + 1] as i64 * alpha) as f32;
                    sum[2] += (data[i + 2] as i64 * alpha) as f32;
                    sum[3] += alpha as f32;
                    count += 1;
                }
            }
            if sum[3] as f64 <= 0.0 {
                continue;
            }
            let o = (sy * small_width + sx) * 4;
            let w = sum[3] as f64;
            out[o] = round(sum[0] as f64 / w);
            out[o + 1] = round(sum[1] as f64 / w);
            out[o + 2] = round(sum[2] as f64 / w);
            out[o + 3] = round(w / count as f64);
        }
    }
    out
}
