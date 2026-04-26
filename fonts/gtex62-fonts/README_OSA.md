# gtex62-osa-font

A clean-room recreation of the AlphaSmart 3000-style LCD font, built from first principles using a fixed 5×7 block grid.

---

## Overview

This font reproduces the visual behavior of the AlphaSmart 3000 display:

* 5 × 7 block matrix per glyph
* Monospaced layout
* Fixed advance width
* Consistent margins and spacing
* LCD-style segmented appearance

The font was constructed manually by deriving the grid system and proportions, not by copying or modifying any existing font files.

---

## Design Characteristics

* **Grid:** 5 columns × 7 rows
* **Style:** Block / LCD matrix
* **Spacing:** Monospaced
* **Advance Width:** 1228 units
* **Em Size:** 2048
* **Rendering:** Optimized for crisp, grid-aligned display

Each glyph is composed of uniform rectangular blocks with consistent spacing, designed to emulate a hardware display rather than traditional typography.

---

## Character Set

Currently includes:

* Uppercase letters (A–Z)
* Numbers (0–9)
* Basic punctuation

The font is intentionally minimal and focused.

---

## Technical Details

* **Format:** TrueType (.ttf)
* **Encoding:** Reduced (no full Unicode grid)
* **OS/2 Metrics:** Cleaned and normalized
* **Panose:** Minimal / monospaced classification
* **GASP:** Simplified (modern rendering behavior)

All unused glyph slots have been removed to reduce file size and eliminate encoding overhead.

---

## File Size

Final font size: ~11.8 KB

This reflects a minimal, efficient glyph set with no unused Unicode space.

---

## Usage

This font is suitable for:

* Terminal-style displays
* Retro UI themes
* Embedded-style interfaces
* Conky / HUD-style overlays
* Pixel / grid-based design systems

---

## Notes

* Designed for clarity at medium-to-large sizes
* Small-size rendering may vary depending on rasterizer
* No hinting is applied

---

## License

This font is a clean-room implementation of a display style.
No original font data or outlines were used.

MIT

---

## Author

gtex62

---

