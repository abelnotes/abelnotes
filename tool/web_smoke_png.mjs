// Minimal PNG reader for web_smoke.mjs: the first pixel of a 1x1 screenshot.
import { inflateSync } from 'node:zlib';

export const PNG = {
  firstPixel(buf) {
    let off = 8;
    let width = 0, colorType = 0;
    const idat = [];
    while (off < buf.length) {
      const len = buf.readUInt32BE(off);
      const type = buf.toString('ascii', off + 4, off + 8);
      const data = buf.subarray(off + 8, off + 8 + len);
      if (type === 'IHDR') {
        width = data.readUInt32BE(0);
        colorType = data[9];
      } else if (type === 'IDAT') {
        idat.push(data);
      } else if (type === 'IEND') {
        break;
      }
      off += 12 + len;
    }
    const raw = inflateSync(Buffer.concat(idat));
    // Row 0: filter byte, then pixels (RGB or RGBA); 1-pixel rows need no unfiltering
    // beyond "none" or "sub" (sub of the first pixel is the pixel itself).
    const bpp = colorType === 6 ? 4 : 3;
    void width;
    return [raw[1], raw[2], raw[3]].slice(0, bpp >= 3 ? 3 : 3);
  },
};
