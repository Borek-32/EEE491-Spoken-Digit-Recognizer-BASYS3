#!/usr/bin/env python3
"""Build deterministic, metadata-free report figures for the home-fab PCB."""

from __future__ import annotations

import hashlib
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[1]
OUT = Path(__file__).resolve().parent / "derived"
PHOTOS = ROOT / "photos"
KICAD = ROOT / "kicad" / "evidence"
FONT_PATH = Path("DejaVuSans.ttf")
FONT_BOLD_PATH = Path("DejaVuSans-Bold.ttf")


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    path = FONT_BOLD_PATH if bold else FONT_PATH
    return ImageFont.truetype(str(path), size=size)


def load_rgb(path: Path) -> Image.Image:
    with Image.open(path) as source:
        return ImageOps.exif_transpose(source).convert("RGB")


def labeled_pair(
    left_path: Path,
    left_crop: tuple[int, int, int, int],
    left_label: str,
    right_path: Path,
    right_crop: tuple[int, int, int, int],
    right_label: str,
    output: Path,
    cell_size: tuple[int, int] = (1200, 760),
) -> None:
    left = ImageOps.fit(load_rgb(left_path).crop(left_crop), cell_size, Image.Resampling.LANCZOS)
    right = ImageOps.fit(load_rgb(right_path).crop(right_crop), cell_size, Image.Resampling.LANCZOS)
    gap = 20
    label_h = 72
    canvas = Image.new("RGB", (cell_size[0] * 2 + gap, cell_size[1] + label_h), "white")
    canvas.paste(left, (0, label_h))
    canvas.paste(right, (cell_size[0] + gap, label_h))
    draw = ImageDraw.Draw(canvas)
    title_font = font(34, bold=True)
    draw.text((24, 17), left_label, fill="#111111", font=title_font)
    draw.text((cell_size[0] + gap + 24, 17), right_label, fill="#111111", font=title_font)
    canvas.save(output, format="PNG", optimize=True)


def build_kicad_assets(layer_output: Path, all_layers_output: Path) -> None:
    crop_box = (74, 75, 1019, 766)
    fcu = load_rgb(KICAD / "report_views" / "pcb_named_nets_top_copper.png").crop(crop_box)
    bcu = load_rgb(KICAD / "report_views" / "pcb_named_nets_bottom_copper.png").crop(crop_box)

    full_w = fcu.width + bcu.width
    label_h = 64
    canvas_h = label_h + fcu.height
    canvas = Image.new("RGB", (full_w, canvas_h), "#00101f")
    draw = ImageDraw.Draw(canvas)
    label_font = font(34, bold=True)

    draw.text((24, 13), "(a) F.Cu component-side routing", fill="white", font=label_font)
    draw.text((fcu.width + 24, 13), "(b) B.Cu underside routing", fill="white", font=label_font)
    canvas.paste(fcu, (0, label_h))
    canvas.paste(bcu, (fcu.width, label_h))
    canvas.save(layer_output, format="PNG", optimize=True)

    all_layers = load_rgb(
        KICAD / "report_views" / "pcb_named_nets_all_layers.png"
    ).crop((82, 84, 1011, 758))
    all_layers_draw = ImageDraw.Draw(all_layers)
    # The working screenshot contains two oversized footprint-value fragments
    # outside the left board edge. Remove only that editor clutter and redraw
    # the visible board boundary; the copper, pads, vias, and net labels remain
    # unchanged.
    all_layers_draw.rectangle((0, 325, 32, 620), fill="#00101f")
    all_layers_draw.line((2, 0, 2, all_layers.height - 1), fill="#d93a3a", width=5)
    all_layers.save(all_layers_output, format="PNG", optimize=True)


def copy_without_metadata(source: Path, output: Path) -> None:
    image = load_rgb(source)
    image.save(output, format="PNG", optimize=True)


def crop_without_metadata(source: Path, crop_box: tuple[int, int, int, int], output: Path) -> None:
    image = load_rgb(source).crop(crop_box)
    image.save(output, format="PNG", optimize=True)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    labeled_pair(
        PHOTOS / "20260716_early_defective_uv_trial.jpg",
        (300, 20, 2480, 1480),
        "(a) Early defective UV trial",
        PHOTOS / "20260819_172806.jpg",
        (180, 0, 2420, 1456),
        "(b) Aligned two-sided fold-up artwork",
        OUT / "homefab_development_progression.png",
    )

    copy_without_metadata(
        KICAD / "schematic_render" / "mfcc_homefab_named_nets_cropped.png",
        OUT / "homefab_reconciled_schematic.png",
    )

    build_kicad_assets(
        OUT / "homefab_named_net_layers.png",
        OUT / "homefab_all_layers_working_view.png",
    )

    labeled_pair(
        PHOTOS / "20260819_192143.jpg",
        (320, 200, 1960, 1270),
        "(a) Component side",
        PHOTOS / "20260819_192240.jpg",
        (200, 220, 1750, 1230),
        "(b) Solder and interconnect side",
        OUT / "homefab_final_board_sides.png",
    )

    crop_without_metadata(
        PHOTOS / "20260819_190726_operating_on_basys3.jpg",
        (1200, 100, 4000, 1450),
        OUT / "homefab_operating_on_basys3.png",
    )

    outputs = sorted(OUT.glob("*.png"))
    checksum_path = OUT / "SHA256SUMS"
    checksum_path.write_text(
        "".join(f"{sha256(path)}  {path.name}\n" for path in outputs),
        encoding="utf-8",
    )
    for path in outputs:
        with Image.open(path) as image:
            print(f"{path.name}: {image.width}x{image.height}")


if __name__ == "__main__":
    main()
