"""Generate first-pass inventory icons for the equipment slots (#73).

Simple flat-shaded silhouette icons matching each gear piece's palette swatch.
Placeholder art, flagged for a later art pass alongside the procedural GLBs.
256x256 PNGs with transparent background, written to sprites/ui/items/.

Run: python3 tools/build_equipment_icons.py
"""

import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "sprites", "ui", "items")
S = 256

OLIVE = (96, 112, 64, 255)
TAN = (188, 150, 100, 255)
CHARCOAL = (60, 62, 70, 255)
BLACK = (40, 42, 48, 255)
EDGE = (24, 26, 30, 255)


def new_img():
	img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
	return img, ImageDraw.Draw(img)


def save(img, name):
	path = os.path.join(OUT, name + ".png")
	img.save(path)
	print("ICON %s" % path)


def helmet():
	img, d = new_img()
	d.pieslice([48, 56, 208, 216], 180, 360, fill=OLIVE, outline=EDGE, width=4)
	d.rectangle([48, 134, 208, 152], fill=OLIVE, outline=EDGE, width=4)
	d.rectangle([40, 138, 216, 156], fill=(70, 84, 48, 255), outline=EDGE, width=4)
	save(img, "marine_helmet")


def cap():
	img, d = new_img()
	d.pieslice([64, 70, 192, 198], 180, 360, fill=TAN, outline=EDGE, width=4)
	d.ellipse([60, 128, 224, 168], fill=(150, 118, 78, 255), outline=EDGE, width=4)
	save(img, "recon_cap")


def vest():
	img, d = new_img()
	d.polygon([(78, 56), (178, 56), (196, 96), (196, 208), (60, 208), (60, 96)],
		fill=CHARCOAL, outline=EDGE)
	d.line([(128, 56), (128, 208)], fill=EDGE, width=4)
	d.rectangle([92, 120, 164, 168], fill=(48, 50, 56, 255), outline=EDGE, width=3)
	save(img, "tac_vest")


def backpack():
	img, d = new_img()
	d.rounded_rectangle([72, 64, 184, 208], radius=18, fill=TAN, outline=EDGE, width=4)
	d.rounded_rectangle([84, 72, 172, 120], radius=12, fill=(160, 126, 84, 255), outline=EDGE, width=3)
	d.line([(96, 64), (96, 40)], fill=EDGE, width=6)
	d.line([(160, 64), (160, 40)], fill=EDGE, width=6)
	save(img, "field_backpack")


def boots():
	img, d = new_img()
	for ox in (28, 116):
		d.rectangle([ox + 30, 70, ox + 70, 168], fill=BLACK, outline=EDGE, width=4)
		d.polygon([(ox + 30, 168), (ox + 96, 168), (ox + 96, 200), (ox + 30, 200)],
			fill=(28, 30, 34, 255), outline=EDGE)
	save(img, "combat_boots")


def main():
	os.makedirs(OUT, exist_ok=True)
	helmet()
	cap()
	vest()
	backpack()
	boots()
	print("ALL ICONS BUILT")


main()
