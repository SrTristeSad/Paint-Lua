#!/usr/bin/env python3
"""Comparar duas capturas na MESMA resolução e escala; não certifica equivalência por si só."""
import argparse
import json
import math
from pathlib import Path
from PIL import Image, ImageChops, ImageEnhance, ImageStat

def compare(reference, actual, output_dir):
    with Image.open(reference) as img:
        ref = img.convert("RGB")
    with Image.open(actual) as img:
        got = img.convert("RGB")
    if ref.size != got.size:
        raise ValueError(f"Resoluções diferentes: referência={ref.size}; reprodução={got.size}")
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    delta = ImageChops.difference(ref, got)
    stats = ImageStat.Stat(delta)
    exact = sum(1 for rgb in delta.getdata() if rgb == (0, 0, 0))
    total = ref.size[0] * ref.size[1]
    mae = sum(stats.mean) / 3.0
    rmse = math.sqrt(sum(stats.rms[i] ** 2 for i in range(3)) / 3.0)
    metrics = {
        "width": ref.width,
        "height": ref.height,
        "identical_pixels": exact,
        "total_pixels": total,
        "identical_fraction": exact / total,
        "mae_rgb_0_to_255": mae,
        "rmse_rgb_0_to_255": rmse,
        "source_reference": str(reference),
        "source_actual": str(actual),
        "note": "Sem garantia de fidelidade visual; exige auditoria humana e proveniência da referência."
    }
    Image.blend(ref, got, 0.5).save(output_dir / "overlay.png")
    ImageEnhance.Contrast(delta).enhance(3).save(output_dir / "difference.png")
    (output_dir / "metrics.json").write_text(
        json.dumps(metrics, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return metrics

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--actual", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    try:
        metrics = compare(args.reference, args.actual, args.output_dir)
    except (ValueError, OSError) as err:
        parser.error(str(err))
    print(json.dumps(metrics, indent=2, ensure_ascii=False))

if __name__ == "__main__":
    main()
