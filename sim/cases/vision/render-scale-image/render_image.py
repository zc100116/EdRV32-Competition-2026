"""Convert the RTL DDR framebuffer dump to a lossless PNG."""

import sys

from PIL import Image


if __name__ == "__main__":
    Image.open(sys.argv[1]).save(sys.argv[2])
