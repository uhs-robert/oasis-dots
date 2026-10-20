//! How click-ocr cuts a captured window into horizontal strips, and the argument lists of the external tools that do
//! the cutting and the reading. Pure and integer, so the plan can be compared with the bash script's.
use std::path::Path;

/// An image taller than this is read in strips.
const TALL_PX: i64 = 1000;
const STRIP_TARGET_PX: i64 = 350;
const STRIPS_MIN: i64 = 4;
const STRIPS_MAX: i64 = 6;
/// How far a strip's crop reaches past the rows it owns, at scale 1: at least 2.5 times a typical line, so a line
/// across a cut is whole in the strip that owns it. It grows with the capture's scale.
const OVERLAP_PX: i64 = 80;
/// A capture whose mean luminance is under this is light text on dark, read better inverted.
pub const DARK_BELOW: f64 = 0.5;
/// The x and y scales of a capture agree to within this fraction, or its pixels cannot be mapped to the screen.
pub const SCALE_TOLERANCE: f64 = 0.02;
/// The most strips there can be, for naming the files in the work directory.
pub const MOST_STRIPS: usize = STRIPS_MAX as usize;

/// One strip: where its crop starts and how tall it is (tesseract's coordinates are relative to the crop), and the
/// rows of the image it owns, which decide which strip a line belongs to.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub struct Cut {
    pub index: usize,
    pub crop_top: i64,
    pub crop_height: i64,
    pub own_top: i64,
    pub own_bottom: i64,
}

pub fn plan(image_w: i64, image_h: i64, window_w: i64) -> Vec<Cut> {
    let overlap = (OVERLAP_PX * image_w + window_w / 2) / window_w;
    let strips = if image_h > TALL_PX {
        ((image_h + STRIP_TARGET_PX - 1) / STRIP_TARGET_PX).clamp(STRIPS_MIN, STRIPS_MAX)
    } else {
        1
    };
    let own_h = (image_h + strips - 1) / strips;
    (0..strips)
        .map(|i| {
            let top = (i * own_h - overlap).max(0);
            let bottom = ((i + 1) * own_h + overlap).min(image_h);
            let own_top = i * own_h;
            Cut {
                index: usize::try_from(i).unwrap_or(0),
                crop_top: top,
                crop_height: bottom - top,
                own_top,
                own_bottom: (own_top + own_h).min(image_h),
            }
        })
        .collect()
}

pub fn strip_file(work: &Path, cut: &Cut) -> std::path::PathBuf {
    work.join(format!("strip{}.pgm", cut.index))
}

pub fn strip_text_file(work: &Path, cut: &Cut) -> std::path::PathBuf {
    work.join(format!("strip{}.tsv", cut.index))
}

/// One magick run grays the shot, writes every strip and prints the mean luminance of the whole image (scaled down
/// first, so it is cheap). The parentheses are arguments of their own, as magick takes them.
pub fn magick_cut_args(work: &Path, image_w: i64, cuts: &[Cut]) -> Vec<String> {
    let mut args: Vec<String> = [work.join("shot.ppm").to_string_lossy().into_owned()]
        .into_iter()
        .chain(["-colorspace", "Gray", "-depth", "8"].map(String::from))
        .collect();
    for cut in cuts {
        args.extend(["(", "+clone", "-crop"].map(String::from));
        args.push(format!("{image_w}x{}+0+{}", cut.crop_height, cut.crop_top));
        args.extend(["+repage", "-write"].map(String::from));
        args.push(strip_file(work, cut).to_string_lossy().into_owned());
        args.extend(["+delete", ")"].map(String::from));
    }
    args.extend(
        [
            "(",
            "+clone",
            "-filter",
            "box",
            "-resize",
            "1x1!",
            "-format",
            "%[fx:mean]",
            "-write",
            "info:-",
            "+delete",
            ")",
            "null:",
        ]
        .map(String::from),
    );
    args
}

/// tesseract's arguments after its input, which is the strip's file or `-` for the inverted pipe.
pub fn tesseract_args(input: &str) -> Vec<String> {
    [
        input,
        "-",
        "--psm",
        "11",
        "--oem",
        "1",
        "-c",
        "tessedit_do_invert=0",
        "tsv",
    ]
    .map(String::from)
    .to_vec()
}

/// The inverting stage of a dark strip: magick negates the strip and pipes it to tesseract, whose own inversion is
/// slower and stays off.
pub fn negate_args(file: &Path) -> Vec<String> {
    vec![file.to_string_lossy().into_owned(), "-negate".into(), "pgm:-".into()]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_normal_window_is_one_strip() {
        assert_eq!(
            plan(256, 154, 160),
            [Cut {
                index: 0,
                crop_top: 0,
                crop_height: 154,
                own_top: 0,
                own_bottom: 154
            }]
        );
    }

    #[test]
    fn a_tall_window_is_four_to_six_strips_owning_every_row_once() {
        for (height, strips) in [(1001, 4), (1500, 5), (2100, 6), (4000, 6)] {
            let cuts = plan(1000, height, 1000);
            assert_eq!(cuts.len(), strips, "height {height}");
            assert_eq!(cuts[0].own_top, 0);
            assert_eq!(cuts.last().unwrap().own_bottom, height);
            assert!(cuts.windows(2).all(|pair| pair[0].own_bottom == pair[1].own_top));
        }
    }

    #[test]
    fn the_overlap_scales_with_the_capture_and_is_clipped_to_the_image() {
        let at_scale_one = plan(1000, 1500, 1000);
        assert_eq!(at_scale_one[1].own_top - at_scale_one[1].crop_top, 80);
        assert_eq!(
            plan(2000, 3000, 1000)[1].own_top - plan(2000, 3000, 1000)[1].crop_top,
            160
        );
        let last = at_scale_one.last().unwrap();
        assert_eq!(last.crop_top + last.crop_height, 1500);
    }

    #[test]
    fn the_cut_arguments_name_every_strip_and_end_with_the_mean() {
        let work = Path::new("/w");
        let args = magick_cut_args(work, 10, &plan(10, 8, 10));
        assert_eq!(
            args.join(" "),
            "/w/shot.ppm -colorspace Gray -depth 8 ( +clone -crop 10x8+0+0 +repage -write /w/strip0.pgm +delete ) \
             ( +clone -filter box -resize 1x1! -format %[fx:mean] -write info:- +delete ) null:"
        );
    }
}
