#!/usr/bin/env python3
"""Tiles design/screenshots/*.png into one image for a quick look.

Usage: Scripts/contact-sheet.py <output.jpg> [glob] [columns] [thumb width] [--as-is]
Landscape captures from the UI walkthrough are stored unrotated, so each tall image is turned
on its side. Pass --as-is for captures that really are portrait, such as iPhone ones.
"""
import glob
import os
import sys

from PIL import Image, ImageDraw

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
arguments = [argument for argument in sys.argv[1:] if argument != "--as-is"]
as_is = "--as-is" in sys.argv[1:]
output = arguments[0]
pattern = arguments[1] if len(arguments) > 1 else "*.png"
columns = int(arguments[2]) if len(arguments) > 2 else 4
width = int(arguments[3]) if len(arguments) > 3 else 500

files = sorted(glob.glob(os.path.join(root, "design", "screenshots", pattern)))
if not files:
    sys.exit("no screenshots match " + pattern)

thumbs = []
for path in files:
    image = Image.open(path).convert("RGB")
    if image.height > image.width and not as_is:
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
