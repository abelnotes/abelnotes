//! C-ABI bridge between the `onenote_parser` crate and the Flutter app.
//!
//! One entry point: [`onenote_parse_file`] takes a path to a `.one`,
//! `.onepkg` or `.onetoc2` file and returns a JSON document tree (sections →
//! pages → positioned contents). Keeping the FFI surface to a single
//! path-in / JSON-string-out call avoids all struct marshalling; the Dart
//! side decodes the JSON and maps it onto ncnote elements.
//!
//! Unit conventions in the emitted JSON — everything is in POINTS (72 dpi),
//! the app's page-logical unit:
//! - OneNote layout offsets/sizes come in half-inch increments → × 36.
//! - Ink coordinates and stroke widths come in HIMETRIC-like units
//!   (2540 per inch) → × 72 / 2540.
//! - Font sizes come in half-points → × 0.5.

use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};

use base64::engine::general_purpose::STANDARD as B64;
use base64::Engine;
use onenote_parser::contents::{
    Content, Image, Ink, InkStroke, OutlineElement, OutlineItem, RichText, Table,
};
use onenote_parser::page::{Page, PageContent};
use typed_path::TypedPath;
use onenote_parser::property::common::ColorRef;
use onenote_parser::section::{Section, SectionEntry};
use onenote_parser::Parser;
use serde_json::{json, Map, Value};

const HALF_INCH_PT: f32 = 36.0;
const INK_TO_PT: f32 = 72.0 / 2540.0;

/// Parse the given OneNote file and return a JSON tree. The returned string
/// must be released with [`onenote_free_string`]. Never returns null: on
/// failure the JSON is `{"error": "..."}`.
///
/// # Safety
/// `path` must be a valid NUL-terminated UTF-8 string pointer.
#[no_mangle]
pub unsafe extern "C" fn onenote_parse_file(path: *const c_char) -> *mut c_char {
    let result = catch_unwind(AssertUnwindSafe(|| parse_to_json(path)));
    let json = match result {
        Ok(Ok(value)) => value.to_string(),
        Ok(Err(message)) => json!({ "error": message }).to_string(),
        Err(_) => json!({ "error": "internal panic while parsing" }).to_string(),
    };
    // JSON never contains interior NULs (serde escapes control chars).
    CString::new(json)
        .unwrap_or_else(|_| CString::new("{\"error\":\"NUL in output\"}").unwrap())
        .into_raw()
}

/// Release a string returned by [`onenote_parse_file`].
///
/// # Safety
/// `ptr` must be a pointer previously returned by [`onenote_parse_file`]
/// and must not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn onenote_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

unsafe fn parse_to_json(path: *const c_char) -> Result<Value, String> {
    if path.is_null() {
        return Err("null path".into());
    }
    let path_str = CStr::from_ptr(path)
        .to_str()
        .map_err(|_| "path is not valid UTF-8".to_string())?;
    let typed = TypedPath::derive(path_str);
    let lower = path_str.to_lowercase();

    let parser = Parser::new();
    let mut sections_json = Vec::new();

    if lower.ends_with(".one") {
        let section = parser
            .parse_section(typed)
            .map_err(|e| format!("parse_section: {e}"))?;
        sections_json.push(section_to_json(&section));
    } else {
        let notebook = if lower.ends_with(".onepkg") {
            parser
                .parse_package(typed)
                .map_err(|e| format!("parse_package: {e}"))?
        } else {
            parser
                .parse_notebook(typed)
                .map_err(|e| format!("parse_notebook: {e}"))?
        };
        collect_sections(notebook.entries(), &mut sections_json);
    }

    Ok(json!({ "sections": sections_json }))
}

fn collect_sections(entries: &[SectionEntry], out: &mut Vec<Value>) {
    for entry in entries {
        match entry {
            SectionEntry::Section(section) => out.push(section_to_json(section)),
            SectionEntry::SectionGroup(group) => collect_sections(group.entries(), out),
        }
    }
}

fn section_to_json(section: &Section) -> Value {
    let pages: Vec<Value> = section
        .page_series()
        .iter()
        .flat_map(|series| series.pages())
        .map(page_to_json)
        .collect();
    json!({
        "name": section.display_name(),
        "pages": pages,
    })
}

fn page_to_json(page: &Page) -> Value {
    let mut contents = Vec::new();
    let mut skipped = 0u32;
    for content in page.contents() {
        match content {
            PageContent::Outline(outline) => {
                let mut elements = Vec::new();
                walk_outline_items(outline.items(), 0, &mut elements, &mut skipped);
                contents.push(json!({
                    "type": "outline",
                    "x": outline.offset_horizontal().unwrap_or(0.0) * HALF_INCH_PT,
                    "y": outline.offset_vertical().unwrap_or(0.0) * HALF_INCH_PT,
                    "width": outline.layout_max_width().map(|w| w * HALF_INCH_PT),
                    "elements": elements,
                }));
            }
            PageContent::Image(image) => {
                if let Some(value) = image_to_json(
                    image,
                    image.offset_horizontal().unwrap_or(0.0) * HALF_INCH_PT,
                    image.offset_vertical().unwrap_or(0.0) * HALF_INCH_PT,
                ) {
                    contents.push(value);
                } else {
                    skipped += 1;
                }
            }
            PageContent::Ink(ink) => {
                collect_ink(ink, &mut contents);
            }
            PageContent::Unknown | PageContent::EmbeddedFile(_) => skipped += 1,
        }
    }
    json!({
        "title": page_title_text(page),
        "height": page.height().map(|h| h * HALF_INCH_PT),
        "skipped": skipped,
        "contents": contents,
    })
}

fn page_title_text(page: &Page) -> Value {
    match page.title_text() {
        Some(text) => Value::String(text.to_string()),
        None => Value::Null,
    }
}

fn walk_outline_items(
    items: &[OutlineItem],
    level: u8,
    out: &mut Vec<Value>,
    skipped: &mut u32,
) {
    for item in items {
        match item {
            OutlineItem::Element(element) => {
                walk_outline_element(element, level, out, skipped)
            }
            OutlineItem::Group(group) => {
                walk_outline_items(group.outlines(), level + group.child_level(), out, skipped)
            }
        }
    }
}

fn walk_outline_element(
    element: &OutlineElement,
    level: u8,
    out: &mut Vec<Value>,
    skipped: &mut u32,
) {
    let level = level + element.child_level();
    let has_bullet = !element.list_contents().is_empty();
    for content in element.contents() {
        match content {
            Content::RichText(text) => {
                out.push(rich_text_to_json(text, level, has_bullet));
            }
            Content::Table(table) => {
                out.push(table_to_json(table, level, skipped));
            }
            Content::Image(image) => {
                if let Some(value) = image_to_json(image, 0.0, 0.0) {
                    let mut obj = value.as_object().cloned().unwrap_or_default();
                    obj.insert("level".into(), json!(level));
                    obj.insert("inline".into(), json!(true));
                    out.push(Value::Object(obj));
                } else {
                    *skipped += 1;
                }
            }
            Content::Ink(ink) => {
                // Outline-embedded ink keeps only stroke geometry (drawn
                // relative to the outline, which the importer offsets).
                let mut ink_parts = Vec::new();
                collect_ink(ink, &mut ink_parts);
                for mut part in ink_parts {
                    if let Some(obj) = part.as_object_mut() {
                        obj.insert("level".into(), json!(level));
                        obj.insert("inline".into(), json!(true));
                    }
                    out.push(part);
                }
            }
            Content::EmbeddedFile(_) | Content::Unknown => *skipped += 1,
        }
    }
    for child in element.children() {
        // Child elements of a list item / paragraph nest one level deeper.
        match child {
            OutlineItem::Element(el) => walk_outline_element(el, level + 1, out, skipped),
            OutlineItem::Group(group) => {
                walk_outline_items(group.outlines(), level + 1 + group.child_level(), out, skipped)
            }
        }
    }
}

fn rich_text_to_json(text: &RichText, level: u8, bullet: bool) -> Value {
    // Runs: text_run_indices are UTF-16 positions where runs END; formatting
    // aligns 1:1 with the resulting parts (trailing part inherits paragraph
    // style). We emit (utf16 length, style) pairs so the Dart side can split
    // without re-deriving the boundary semantics.
    let utf16: Vec<u16> = text.text().encode_utf16().collect();
    let indices = text.text_run_indices();
    let styles = text.text_run_formatting();

    let mut runs = Vec::new();
    let mut prev = 0usize;
    for (i, end) in indices.iter().enumerate() {
        let end = (*end as usize).min(utf16.len());
        if end > prev {
            runs.push(run_json(&utf16[prev..end], styles.get(i)));
        }
        prev = end;
    }
    if prev < utf16.len() {
        runs.push(run_json(&utf16[prev..], styles.get(indices.len())));
    }

    let paragraph = text.paragraph_style();
    json!({
        "kind": "text",
        "level": level,
        "bullet": bullet,
        "align": match format!("{:?}", text.paragraph_alignment()).as_str() {
            "Center" => "center",
            "Right" => "right",
            _ => "left",
        },
        "spaceBefore": text.paragraph_space_before() * HALF_INCH_PT,
        "spaceAfter": text.paragraph_space_after() * HALF_INCH_PT,
        "baseBold": paragraph.bold(),
        "baseItalic": paragraph.italic(),
        "baseFont": paragraph.font(),
        "baseSize": paragraph.font_size().map(|s| s as f32 / 2.0),
        "baseColor": paragraph.font_color().and_then(color_ref_to_argb),
        "styleId": paragraph.style_id(),
        "runs": runs,
    })
}

fn run_json(utf16: &[u16], style: Option<&onenote_parser::contents::ParagraphStyling>) -> Value {
    let text = String::from_utf16_lossy(utf16);
    let mut obj = Map::new();
    obj.insert("text".into(), json!(text));
    if let Some(s) = style {
        if s.bold() {
            obj.insert("bold".into(), json!(true));
        }
        if s.italic() {
            obj.insert("italic".into(), json!(true));
        }
        if s.underline() {
            obj.insert("underline".into(), json!(true));
        }
        if s.strikethrough() {
            obj.insert("strike".into(), json!(true));
        }
        if let Some(font) = s.font() {
            obj.insert("font".into(), json!(font));
        }
        if let Some(size) = s.font_size() {
            obj.insert("size".into(), json!(size as f32 / 2.0));
        }
        if let Some(argb) = s.font_color().and_then(color_ref_to_argb) {
            obj.insert("color".into(), json!(argb));
        }
    }
    Value::Object(obj)
}

fn color_ref_to_argb(color: ColorRef) -> Option<u32> {
    match color {
        ColorRef::Auto => None,
        ColorRef::Manual { r, g, b } => {
            Some(0xFF000000 | ((r as u32) << 16) | ((g as u32) << 8) | (b as u32))
        }
    }
}

fn table_to_json(table: &Table, level: u8, skipped: &mut u32) -> Value {
    // v1: plain cell text only (the Dart side renders a monospace grid).
    let rows: Vec<Vec<String>> = table
        .contents()
        .iter()
        .map(|row| {
            row.contents()
                .iter()
                .map(|cell| {
                    let mut parts = Vec::new();
                    let mut cell_skipped = 0u32;
                    for element in cell.contents() {
                        walk_outline_element(element, 0, &mut parts, &mut cell_skipped);
                    }
                    *skipped += cell_skipped;
                    parts
                        .iter()
                        .filter_map(|v| {
                            v.get("runs").and_then(Value::as_array).map(|runs| {
                                runs.iter()
                                    .filter_map(|r| r.get("text").and_then(Value::as_str))
                                    .collect::<String>()
                            })
                        })
                        .collect::<Vec<_>>()
                        .join(" ")
                })
                .collect()
        })
        .collect();
    json!({ "kind": "table", "level": level, "rows": rows })
}

fn image_to_json(image: &Image, x_pt: f32, y_pt: f32) -> Option<Value> {
    use std::io::Read;
    let mut reader = image.read()?;
    let mut data = Vec::new();
    reader.read_to_end(&mut data).ok()?;
    if data.is_empty() {
        return None;
    }
    Some(json!({
        "type": "image",
        "x": x_pt,
        "y": y_pt,
        "width": image
            .layout_max_width()
            .or_else(|| image.picture_width())
            .map(|w| w * HALF_INCH_PT),
        "height": image
            .layout_max_height()
            .or_else(|| image.picture_height())
            .map(|h| h * HALF_INCH_PT),
        "ext": image.extension().unwrap_or(""),
        "name": image.image_filename().unwrap_or(""),
        "alt": image.alt_text().unwrap_or(""),
        "b64": B64.encode(&data),
    }))
}

/// Page-level ink. Absolute point position in points:
/// `p * 72/2540 + offset(half-inch) * 36` — same math one2html uses for its
/// SVG rendering, converted from 96 dpi px to 72 dpi points.
fn collect_ink(ink: &Ink, out: &mut Vec<Value>) {
    for child in ink.child_groups() {
        collect_ink(child, out);
    }
    let strokes = ink.ink_strokes();
    if strokes.is_empty() {
        return;
    }
    let dx = ink.offset_horizontal().unwrap_or(0.0) * HALF_INCH_PT;
    let dy = ink.offset_vertical().unwrap_or(0.0) * HALF_INCH_PT;
    let strokes_json: Vec<Value> = strokes.iter().map(|s| stroke_to_json(s, dx, dy)).collect();
    out.push(json!({ "type": "ink", "strokes": strokes_json }));
}

fn stroke_to_json(stroke: &InkStroke, dx: f32, dy: f32) -> Value {
    // The path is delta-encoded: the first point is absolute (ink space),
    // every following point is an offset from the previous one — one2html
    // renders it as an SVG `M x y l dx dy…` path. Accumulate to absolutes.
    let mut points: Vec<f32> = Vec::with_capacity(stroke.path().len() * 2);
    let mut cx = 0.0f32;
    let mut cy = 0.0f32;
    for (i, p) in stroke.path().iter().enumerate() {
        if i == 0 {
            cx = p.x();
            cy = p.y();
        } else {
            cx += p.x();
            cy += p.y();
        }
        points.push(cx * INK_TO_PT + dx);
        points.push(cy * INK_TO_PT + dy);
    }
    // COLORREF byte order: 0x00BBGGRR.
    let color = stroke.color().map(|v| {
        let r = v & 0xFF;
        let g = (v >> 8) & 0xFF;
        let b = (v >> 16) & 0xFF;
        0xFF000000u32 | (r << 16) | (g << 8) | b
    });
    // one2html: opacity = (255 - transparency)/256, transparency None = opaque.
    let opacity = (255 - stroke.transparency().unwrap_or(0) as u32) as f32 / 255.0;
    let width_pt = (stroke.width().max(stroke.height()) * INK_TO_PT).max(0.75);
    json!({
        "points": points,
        "color": color,
        "width": width_pt,
        "opacity": opacity,
    })
}
