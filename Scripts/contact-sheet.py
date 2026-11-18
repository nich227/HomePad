#!/usr/bin/env python3
"""Tiles design/screenshots/*.png into one image for a quick look.

Usage: Scripts/contact-sheet.py <output.jpg> [glob] [columns] [thumb width]
Landscape captures from the UI walkthrough are stored unrotated, so each is turned upright.
"""
import glob
import os
import sys

from PIL import Image, ImageDraw

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
output = sys.argv[1]
pattern = sys.argv[2] if len(sys.argv) > 2 else "*.png"
columns = int(sys.argv[3]) if len(sys.argv) > 3 else 4
width = int(sys.argv[4]) if len(sys.argv) > 4 else 500

files = sorted(glob.glob(os.path.join(root, "design", "screenshots", pattern)))
if not files:
    sys.exit("no screenshots match " + pattern)

thumbs = []
for path in files:
    image = Image.open(path).convert("RGB")
    if image.height > image.width:
        image = image.rotate(90, expand=True)
    height = int(image.height * width / image.width)
    thumbs.append((os.path.basename(path), image.resize((width, height))))

height = max(thumb.height for _, thumb in thumbs)
rows = (len(thumbs) + columns - 1) // columns
sheet = Image.new("RGB", (columns * (width + 8) + 8, rows * (height + 28) + 8), (40, 40, 40))
draw = ImageDraw.Draw(sheet)
for index, (name, thumb) in enumerate(thumbs):
    x = 8 + (index % columns) * (width + 8)
    y = 8 + (index // columns) * (height + 28)
    sheet.paste(thumb, (x, y))
    draw.text((x + 4, y + height + 6), name, fill=(255, 255, 255))
sheet.save(output, quality=82)
print(output, sheet.size, len(thumbs), "images")
