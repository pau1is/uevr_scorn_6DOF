"""grid.py out.png a.png b.png ... -> tile screenshots (640x360 each, 3 per row) for quick visual comparison. Needs pillow."""
import sys
from PIL import Image
out, files = sys.argv[1], sys.argv[2:]
ims = [Image.open(f).resize((640, 360)) for f in files]
cols = min(3, len(ims)); rows = (len(ims) + cols - 1) // cols
g = Image.new("RGB", (640 * cols, 360 * rows))
for i, im in enumerate(ims):
    g.paste(im, ((i % cols) * 640, (i // cols) * 360))
g.save(out)
print(out)
