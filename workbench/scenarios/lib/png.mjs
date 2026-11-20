import { inflateSync } from 'node:zlib';

function paeth(a, b, c) {
  const p = a + b - c;
  const distances = [Math.abs(p - a), Math.abs(p - b), Math.abs(p - c)];
  return distances[0] <= distances[1] && distances[0] <= distances[2] ? a : distances[1] <= distances[2] ? b : c;
}

export function hasVisibleInk(png) {
  // Chromium screenshots are non-interlaced 8-bit RGB or RGBA PNGs. Decode
  // only that bounded contract, using built-ins instead of an image package.
  if (!png.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) throw new Error('Expected PNG screenshot');
  let width, height, channels;
  const parts = [];
  for (let offset = 8; offset + 12 <= png.length;) {
    const length = png.readUInt32BE(offset);
    const type = png.toString('ascii', offset + 4, offset + 8);
    const data = png.subarray(offset + 8, offset + 8 + length);
    if (data.length !== length) throw new Error('Truncated PNG');
    if (type === 'IHDR') {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      channels = data[9] === 2 ? 3 : data[9] === 6 ? 4 : 0;
      if (!width || !height || width * height > 10000000 || data[8] !== 8 || data[12] !== 0 || !channels) throw new Error('Unsupported screenshot PNG');
    }
    if (type === 'IDAT') parts.push(data);
    offset += length + 12;
  }
  if (!channels || !parts.length) throw new Error('Missing PNG pixels');
  const stride = width * channels;
  const raw = inflateSync(Buffer.concat(parts), { maxOutputLength: (stride + 1) * height });
  if (raw.length !== (stride + 1) * height) throw new Error('Invalid PNG scanlines');
  let previous = Buffer.alloc(stride);
  let first;
  let changed = 0;
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    if (filter > 4) throw new Error('Invalid PNG filter');
    const row = Buffer.alloc(stride);
    for (let x = 0; x < stride; x++) {
      const left = x >= channels ? row[x - channels] : 0;
      const up = previous[x];
      const upperLeft = x >= channels ? previous[x - channels] : 0;
      const predictor = [0, left, up, Math.floor((left + up) / 2), paeth(left, up, upperLeft)][filter];
      row[x] = (raw[y * (stride + 1) + 1 + x] + predictor) & 255;
    }
    first ??= [...row.subarray(0, 3)];
    for (let x = 0; x < stride; x += channels) {
      if (Math.max(...first.map((value, channel) => Math.abs(row[x + channel] - value))) > 24) changed++;
    }
    previous = row;
  }
  return changed >= 8;
}
