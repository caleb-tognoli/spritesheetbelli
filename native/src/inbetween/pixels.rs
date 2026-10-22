//! Whole-canvas loops: `PixelCanvas.distances`, `KeyFeatures.of` and `MeshTools.edges`.

/// `PixelCanvas.distances`: each pixel's distance (in thirds of a pixel) to the nearest
/// whose `mask` is `value`, and which that is, or -1
pub fn distances(
    mask: &[u8],
    width: usize,
    height: usize,
    value: u8,
    far: i64,
) -> (Vec<i32>, Vec<i32>) {
    let count = width * height;
    let none = if far > 0 {
        far
    } else {
        (width as i64 + height as i64) * 4
    } as i32;
    let mut distance = vec![none; count];
    let mut nearest = vec![-1i32; count];
    for (p, &m) in mask.iter().enumerate().take(count) {
        if m == value {
            distance[p] = 0;
            nearest[p] = p as i32;
        }
    }
    if width == 0 {
        return (distance, nearest);
    }
    let last_column = width - 1;
    for y in 0..height {
        let row = y * width;
        for x in 0..width {
            let p = row + x;
            let mut d = distance[p];
            if d == 0 {
                continue;
            }
            let mut n = nearest[p];
            if x > 0 && distance[p - 1] + 3 < d {
                d = distance[p - 1] + 3;
                n = nearest[p - 1];
            }
            if y > 0 {
                let q = p - width;
                if x > 0 && distance[q - 1] + 4 < d {
                    d = distance[q - 1] + 4;
                    n = nearest[q - 1];
                }
                if distance[q] + 3 < d {
                    d = distance[q] + 3;
                    n = nearest[q];
                }
                if x < last_column && distance[q + 1] + 4 < d {
                    d = distance[q + 1] + 4;
                    n = nearest[q + 1];
                }
            }
            distance[p] = d;
            nearest[p] = n;
        }
    }
    let last_row = height.saturating_sub(1);
    for y in (0..height).rev() {
        let row = y * width;
        for x in (0..width).rev() {
            let p = row + x;
            let mut d = distance[p];
            if d == 0 {
                continue;
            }
            let mut n = nearest[p];
            if x < last_column && distance[p + 1] + 3 < d {
                d = distance[p + 1] + 3;
                n = nearest[p + 1];
            }
            if y < last_row {
                let q = p + width;
                if x < last_column && distance[q + 1] + 4 < d {
                    d = distance[q + 1] + 4;
                    n = nearest[q + 1];
                }
                if distance[q] + 3 < d {
                    d = distance[q] + 3;
                    n = nearest[q];
                }
                if x > 0 && distance[q - 1] + 4 < d {
                    d = distance[q - 1] + 4;
                    n = nearest[q - 1];
                }
            }
            distance[p] = d;
            nearest[p] = n;
        }
    }
    (distance, nearest)
}

/// `KeyFeatures`' constants
pub struct FeatureWeights {
    pub shown: f64,
    pub depth: f64,
    pub depth_reach: f64,
}

/// `KeyFeatures.of`'s values, five per pixel
pub fn features_of(
    data: &[u8],
    width: usize,
    height: usize,
    depth_scale: f64,
    weights: &FeatureWeights,
) -> Vec<f32> {
    let count = width * height;
    let shown: Vec<u8> = (0..count)
        .map(|p| u8::from(data[p * 4 + 3] >= 128))
        .collect();
    let inside = distances(&shown, width, height, 0, 0).0;
    let outside = distances(&shown, width, height, 1, 0).0;
    let mut values = vec![0f32; count * 5];
    for p in 0..count {
        let alpha = data[p * 4 + 3] as f64 / 255.0;
        let i = p * 5;
        values[i] = (data[p * 4] as f64 / 255.0 * alpha) as f32;
        values[i + 1] = (data[p * 4 + 1] as f64 / 255.0 * alpha) as f32;
        values[i + 2] = (data[p * 4 + 2] as f64 / 255.0 * alpha) as f32;
        values[i + 3] = (alpha * weights.shown) as f32;
        let depth = (inside[p] as i64 - outside[p] as i64) as f64 / 3.0 / depth_scale;
        values[i + 4] =
            (clamp(depth, -weights.depth_reach, weights.depth_reach) * weights.depth) as f32;
    }
    values
}

/// Godot's `clampf`
fn clamp(value: f64, low: f64, high: f64) -> f64 {
    if value < low {
        low
    } else if value > high {
        high
    } else {
        value
    }
}

/// `MeshTools.edges`
pub fn edges(colors: &[f32], width: usize, height: usize, least_step: f64) -> Vec<u8> {
    let mut result = vec![0u8; width * height];
    // Right, left, down and up
    const STEPS: [(i64, i64); 4] = [(1, 0), (-1, 0), (0, 1), (0, -1)];
    for y in 0..height {
        for x in 0..width {
            let p = y * width + x;
            let i = p * 4;
            if (colors[i + 3] as f64) < 0.5 {
                continue;
            }
            for (across, down) in STEPS {
                let qx = x as i64 + across;
                let qy = y as i64 + down;
                if qx < 0 || qy < 0 || qx >= width as i64 || qy >= height as i64 {
                    result[p] = 1;
                    break;
                }
                let j = (qy as usize * width + qx as usize) * 4;
                if (colors[j + 3] as f64) < 0.5 {
                    result[p] = 1;
                    break;
                }
                let mut step = 0.0f64;
                for c in 0..4 {
                    step += (colors[j + c] as f64 - colors[i + c] as f64).abs();
                }
                if step > least_step {
                    result[p] = 1;
                    break;
                }
            }
        }
    }
    result
}
