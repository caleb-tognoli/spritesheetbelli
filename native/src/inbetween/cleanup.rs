//! `PixelCleanup` (scripts/inbetween/pixel_cleanup.gd): tidying frames up.

use std::collections::HashSet;

/// `PixelCleanup`'s constants
const STRAY_OPEN: u32 = 7;
const JAG_ROUNDS: usize = 2;
const CENTER: i64 = 1 << 4;
const WIDE_CENTER: i64 = 1 << 12;
const WIDE_FULL: i64 = (1 << 25) - 1;

/// A `Rect2i` as start and end, empty when it has no area
#[derive(Clone, Copy)]
struct Area {
    x0: i64,
    y0: i64,
    x1: i64,
    y1: i64,
}

impl Area {
    const NONE: Area = Area {
        x0: 0,
        y0: 0,
        x1: 0,
        y1: 0,
    };

    /// `Rect2i(position, size).intersection(Rect2i(1, 1, width - 2, height - 2))`
    fn inside_border(position: (i64, i64), size: (i64, i64), width: i64, height: i64) -> Area {
        let (other_x, other_y, other_w, other_h) = (1, 1, width - 2, height - 2);
        let (end_x, end_y) = (position.0 + size.0, position.1 + size.1);
        if position.0 >= other_x + other_w
            || end_x <= other_x
            || position.1 >= other_y + other_h
            || end_y <= other_y
        {
            return Area::NONE;
        }
        let x0 = position.0.max(other_x);
        let y0 = position.1.max(other_y);
        Area {
            x0,
            y0,
            x1: (other_x + other_w).min(end_x),
            y1: (other_y + other_h).min(end_y),
        }
    }
}

/// `PixelCanvas.colors`
pub fn colors(data: &[u8]) -> Vec<i32> {
    data.as_chunks::<4>().0.iter()
        .map(|c| {
            if c[3] > 0 {
                (u32::from(c[0]) << 24
                    | u32::from(c[1]) << 16
                    | u32::from(c[2]) << 8
                    | u32::from(c[3])) as i32
            } else {
                0
            }
        })
        .collect()
}

/// `PixelCanvas.shown_area`
fn shown_area(colors: &[i32], width: i64, height: i64) -> Area {
    let (mut low_x, mut low_y, mut high_x, mut high_y) = (width, height, -1i64, -1i64);
    for (p, &color) in colors.iter().enumerate() {
        if color != 0 {
            let (x, y) = (p as i64 % width, p as i64 / width);
            low_x = low_x.min(x);
            low_y = low_y.min(y);
            high_x = high_x.max(x);
            high_y = high_y.max(y);
        }
    }
    if high_x < 0 {
        return Area::NONE;
    }
    Area::inside_border(
        (low_x - 1, low_y - 1),
        (high_x - low_x + 3, high_y - low_y + 3),
        width,
        height,
    )
}

/// `PixelCleanup._shown_area`: the used rect grown by a pixel, kept off the border
fn used_area(data: &[u8], width: i64, height: i64) -> Area {
    let (mut low_x, mut low_y, mut high_x, mut high_y) = (width, height, -1i64, -1i64);
    for (p, pixel) in data.as_chunks::<4>().0.iter().enumerate() {
        if pixel[3] > 0 {
            let (x, y) = (p as i64 % width, p as i64 / width);
            low_x = low_x.min(x);
            low_y = low_y.min(y);
            high_x = high_x.max(x);
            high_y = high_y.max(y);
        }
    }
    if high_x < 0 {
        return Area::NONE;
    }
    Area::inside_border(
        (low_x - 1, low_y - 1),
        (high_x - low_x + 1 + 2, high_y - low_y + 1 + 2),
        width,
        height,
    )
}

/// `PixelParts.sides_of(width, true)`
fn sides_of(width: i64) -> [i64; 8] {
    [
        -1,
        1,
        -width,
        width,
        -width - 1,
        -width + 1,
        width - 1,
        width + 1,
    ]
}

/// `PixelCleanup._most_common`, of colours read with `color_at` (0 for none)
fn most_common(p: i64, sides: &[i64; 8], color_at: impl Fn(usize) -> i64) -> i64 {
    let mut counts: Vec<(i64, i32)> = Vec::with_capacity(8);
    let mut best = 0i64;
    let mut best_count = 0;
    for side in sides {
        let other = color_at((p + side) as usize);
        if other == 0 {
            continue;
        }
        let count = match counts.iter_mut().find(|(color, _)| *color == other) {
            Some(entry) => {
                entry.1 += 1;
                entry.1
            }
            None => {
                counts.push((other, 1));
                1
            }
        };
        if best == 0 || count > best_count {
            best = other;
            best_count = count;
        } else if other == best {
            best_count = count;
        }
    }
    best
}

fn paint(data: &mut [u8], p: usize, color: i64) {
    let color = color as u32;
    data[p * 4] = (color >> 24 & 255) as u8;
    data[p * 4 + 1] = (color >> 16 & 255) as u8;
    data[p * 4 + 2] = (color >> 8 & 255) as u8;
    data[p * 4 + 3] = (color & 255) as u8;
}

/// `PixelCleanup.tidy_data`, in place
pub fn tidy_data(data: &mut [u8], width: i64, height: i64) {
    let colors = colors(data);
    let sides = sides_of(width);
    let area = shown_area(&colors, width, height);
    for y in area.y0..area.y1 {
        for x in area.x0..area.x1 {
            let p = y * width + x;
            let color = colors[p as usize];
            let (mut clear, mut same) = (0, 0);
            for side in sides {
                let other = colors[(p + side) as usize];
                if other == 0 {
                    clear += 1;
                } else if other == color {
                    same += 1;
                }
            }
            if color != 0 && same == 0 && clear >= STRAY_OPEN {
                data[p as usize * 4..p as usize * 4 + 4].fill(0);
            } else if color == 0 && {
                let around = |q: i64| colors[q as usize] != 0;
                around(p - 1) && around(p + 1) && around(p - width) && around(p + width)
            } {
                let best = most_common(p, &sides, |q| colors[q] as i64);
                paint(data, p as usize, best);
            }
        }
    }
}

/// `PixelCleanup._shown`
fn shown(data: &[u8], least_alpha: u8) -> Vec<u8> {
    data.as_chunks::<4>().0.iter()
        .map(|c| u8::from(c[3] >= least_alpha))
        .collect()
}

/// `PixelCleanup._shape_at`
fn shape_at(mask: &[u8], p: i64, width: i64) -> i64 {
    let at = |q: i64| mask[q as usize] as i64;
    let (up, down) = (p - width, p + width);
    at(up - 1)
        | at(up) << 1
        | at(up + 1) << 2
        | at(p - 1) << 3
        | at(p) << 4
        | at(p + 1) << 5
        | at(down - 1) << 6
        | at(down) << 7
        | at(down + 1) << 8
}

/// `PixelCleanup._wide_at`
fn wide_at(mask: &[u8], p: i64, width: i64) -> i64 {
    let at = |q: i64| mask[q as usize] as i64;
    let mut bits = 0i64;
    let mut bit = 0;
    for dy in -2..=2 {
        let q = p + dy * width;
        bits |= (at(q - 2) | at(q - 1) << 1 | at(q) << 2 | at(q + 1) << 3 | at(q + 2) << 4) << bit;
        bit += 5;
    }
    bits
}

/// `PixelCleanup.smooth_jags`, in place
pub fn smooth_jags(
    data: &mut [u8],
    width: i64,
    height: i64,
    shapes: &[i32],
    least_alpha: u8,
    wide_shapes: &HashSet<i64>,
) {
    let sides = sides_of(width);
    let wide = !wide_shapes.is_empty();
    let wide_empty = wide_shapes.contains(&WIDE_CENTER) && !wide_shapes.contains(&0);
    let wide_full =
        wide_shapes.contains(&(WIDE_FULL ^ WIDE_CENTER)) && !wide_shapes.contains(&WIDE_FULL);
    for _ in 0..JAG_ROUNDS {
        let mut mask = shown(data, least_alpha);
        let before = data.to_vec();
        let area = used_area(data, width, height);
        let mut changed = false;
        for y in area.y0..area.y1 {
            for x in area.x0..area.x1 {
                let p = y * width + x;
                let shape = shape_at(&mask, p, width);
                let flipped = shape ^ CENTER;
                let at = |q: i64| mask[q as usize];
                let shown_sides = at(p - 1) + at(p + 1) + at(p - width) + at(p + width);
                let jag = if at(p) == 1 {
                    shown_sides <= 1
                } else {
                    shown_sides >= 3
                };
                let mut smoothed =
                    jag && shapes[shape as usize] == 0 && shapes[flipped as usize] > 0;
                if !smoothed && wide && x >= 2 && y >= 2 && x < width - 2 && y < height - 2 {
                    let around = wide_at(&mask, p, width);
                    smoothed = if around == 0 {
                        wide_empty
                    } else if around == WIDE_FULL {
                        wide_full
                    } else {
                        !wide_shapes.contains(&around)
                            && wide_shapes.contains(&(around ^ WIDE_CENTER))
                    };
                }
                if !smoothed {
                    continue;
                }
                let pu = p as usize;
                if mask[pu] == 1 {
                    data[pu * 4..pu * 4 + 4].fill(0);
                } else {
                    let best = most_common(p, &sides, |q| {
                        let i = q * 4;
                        if before[i + 3] == 0 {
                            0
                        } else {
                            (i64::from(before[i]) << 24)
                                | (i64::from(before[i + 1]) << 16)
                                | (i64::from(before[i + 2]) << 8)
                                | i64::from(before[i + 3])
                        }
                    });
                    paint(data, pu, best);
                }
                mask[pu] = 1 - mask[pu];
                changed = true;
            }
        }
        if !changed {
            return;
        }
    }
}

/// `PixelCleanup.shapes_of`
pub fn shapes_of(data: &[u8], width: i64, height: i64, least_alpha: u8) -> Vec<i32> {
    let mut counts = vec![0i32; 512];
    let mask = shown(data, least_alpha);
    let area = shown_area(&colors(data), width, height);
    for y in area.y0..area.y1 {
        for x in area.x0..area.x1 {
            counts[shape_at(&mask, y * width + x, width) as usize] += 1;
        }
    }
    counts
}

/// `PixelCleanup.wide_shapes_of`: the shapes in the order first found
pub fn wide_shapes_of(data: &[u8], width: i64, height: i64, least_alpha: u8) -> Vec<i64> {
    let mut found = Vec::new();
    let mut seen = HashSet::new();
    let mask = shown(data, least_alpha);
    let area = shown_area(&colors(data), width, height);
    for y in area.y0..area.y1 {
        for x in area.x0..area.x1 {
            if x >= 2 && y >= 2 && x < width - 2 && y < height - 2 {
                let shape = wide_at(&mask, y * width + x, width);
                if seen.insert(shape) {
                    found.push(shape);
                }
            }
        }
    }
    found
}
