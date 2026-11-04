#!/usr/bin/env python3
"""Structural checks of LÖVE smoke screenshots.

These assertions catch blank screens and regression to a uniformly dark Brush
panel. They are NOT pixel-fidelity comparisons to ibisPaint Windows 14.1.4.
"""
from __future__ import annotations

import argparse
from pathlib import Path
from PIL import Image

REQUIRED = (
    "title", "gallery", "gallery_new", "gallery_folders", "gallery_inside",
    "gallery_selection", "gallery_many", "new_canvas", "new_canvas_dpi",
    "editor", "editor_square", "layer", "layer_floating", "layer_properties", "layer_blend",
    "transparent", "brush", "brush_search", "color", "zoom", "solo",
    "view", "grid_settings", "grid", "reference",
    "color_palette", "color_hex", "color_floating", "color_rgb",
    "editor_settings", "tool_popup_1", "tool_popup_2", "tool_popup_3",
    "tool_right", "tool_labels_off",
)


class ScreenshotCheckError(AssertionError):
    pass


def rgb_luma(image: Image.Image, x: int, y: int) -> float:
    r, g, b = image.getpixel((x, y))[:3]
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def check_brush_layout(image: Image.Image) -> None:
    """Check the Windows-inspired *structure*, not copyrighted pixels."""
    w, h = image.size
    if w < 800 or h < 600:
        raise ScreenshotCheckError(f"Brush capture too small: {w}x{h}")
    # Coordinates derive from main.lua's logical layout at the CI 1024x768
    # resolution, and scale with the viewport height if necessary.
    scale = max(0.70, min(1.4, h / 768))
    logic_w = w / scale
    logic_h = h / scale
    x = min(185, max(66, logic_w * 0.16))
    panel_w = min(565, logic_w - x - 34)
    panel_h = min(logic_h - 107, 660)
    inner_x = x + 8
    inner_w = panel_w - 16
    split = inner_x + int(inner_w * 0.53)
    # List and dark properties interior well below the header.
    sample_y = int((55 + panel_h - 84) * scale)
    left_x = int((inner_x + 29) * scale)
    right_x = int((split + (inner_w - int(inner_w * 0.53)) * 0.60) * scale)
    white_value = rgb_luma(image, left_x, sample_y)
    dark_value = rgb_luma(image, right_x, sample_y)
    if white_value - dark_value < 105:
        raise ScreenshotCheckError(
            "Brush panel lost its light-list/dark-properties division: "
            f"left={white_value:.0f}, right={dark_value:.0f}"
        )


def check_tool_rail_layout(image: Image.Image, expected: str) -> None:
    """Verify rail placement/popup absence in LÖVE captures, not pixel fidelity."""
    w, h = image.size
    if (w, h) != (1024, 768):
        raise ScreenshotCheckError(
            f"Tool rail structural check expects 1024x768: got {image.size}"
        )
    # Sample rail edges away from white tool-icon strokes. The previous
    # single pixel landed on a bright icon and produced a false negative.
    ys = (279, 320, 510, 620)
    left = sorted(rgb_luma(image, 5, y) for y in ys)[len(ys) // 2]
    right = sorted(rgb_luma(image, w - 6, y) for y in ys)[len(ys) // 2]
    if expected == "left":
        correct = right - left >= 65
    elif expected == "right":
        correct = left - right >= 65
    elif expected == "popup":
        correct = left >= 145 and right >= 145
    else:
        raise ValueError("Expected rail position must be left/right/popup")
    if not correct:
        raise ScreenshotCheckError(
            f"Tool Select layout {expected} incorrect: "
            f"left={left:.0f}, right={right:.0f}"
        )


def check_directory(directory: Path) -> None:
    missing = [name for name in REQUIRED if not (directory / (name + ".png")).is_file()]
    if missing:
        raise ScreenshotCheckError("Missing LÖVE captures: " + ", ".join(missing))
    for name in REQUIRED:
        file = directory / (name + ".png")
        with Image.open(file) as img:
            img.verify()
        with Image.open(file) as img:
            if img.size != (1024, 768):
                raise ScreenshotCheckError(
                    f"{name}: expected CI 1024x768 screenshot; got {img.size}"
                )
            if name in ("brush", "brush_search"):
                check_brush_layout(img.convert("RGB"))
            if name in ("editor", "editor_settings"):
                check_tool_rail_layout(img.convert("RGB"), "left")
            elif name == "tool_right":
                check_tool_rail_layout(img.convert("RGB"), "right")
            elif name.startswith("tool_popup_") or name == "tool_labels_off":
                check_tool_rail_layout(img.convert("RGB"), "popup")
    print(f"PASS: {len(REQUIRED)} PNGs, Brush split, Left/Right/Popup rail placement")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    check_directory(args.directory)


if __name__ == "__main__":
    main()
