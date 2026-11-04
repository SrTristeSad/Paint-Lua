#!/usr/bin/env python3
"""Build 96px transparent PNGs from vendored Lucide SVG sources."""
from pathlib import Path
import cairosvg
ROOT=Path(__file__).resolve().parent.parent
SVG=ROOT/"assets"/"icons"/"svg"
PNG=ROOT/"assets"/"icons"/"png"
PNG.mkdir(parents=True,exist_ok=True)
paths=sorted(SVG.glob("*.svg"))
if len(paths)<38:
    raise SystemExit("Assets Lucide SVG incompletos")
for path in paths:
    cairosvg.svg2png(url=str(path),write_to=str(PNG/(path.stem+".png")),
                     output_width=96,output_height=96)
print(f"{len(paths)} SVGs convertidos em PNG")
