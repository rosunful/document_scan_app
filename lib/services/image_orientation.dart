import 'dart:typed_data';

/// Extracts the EXIF orientation value from JPEG bytes and maps it to the
/// number of 90° clockwise rotations needed to make the stored pixels match
/// what the OS / Flutter displays (Flutter applies EXIF orientation when it
/// renders `Image.file`/`Image.memory`, but image codecs such as OpenCV do
/// not).
///
/// Returns 0 when there is no EXIF block, no orientation tag, or the bytes
/// are not a JPEG — i.e. no rotation is needed.
int jpegExifQuarterTurns(Uint8List bytes) {
  // JPEG SOI: 0xFF 0xD8
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return 0;

  var pos = 2;
  while (pos + 4 <= bytes.length) {
    if (bytes[pos] != 0xFF) {
      pos++;
      continue;
    }
    final marker = bytes[pos + 1];

    // Stand-alone markers (no length field).
    if (marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD7)) {
      pos += 2;
      continue;
    }
    // SOS / EOI — the EXIF APP1 segment always precedes these.
    if (marker == 0xDA || marker == 0xD9) break;

    if (pos + 4 > bytes.length) break;
    final segLen = (bytes[pos + 2] << 8) | bytes[pos + 3];
    if (segLen < 2) break;

    if (marker == 0xE1 && segLen >= 8 && pos + 10 <= bytes.length) {
      if (bytes[4 + pos] == 0x45 && // 'E'
          bytes[5 + pos] == 0x78 && // 'x'
          bytes[6 + pos] == 0x69 && // 'i'
          bytes[7 + pos] == 0x66 && // 'f'
          bytes[8 + pos] == 0x00 &&
          bytes[9 + pos] == 0x00) {
        return _orientationToTurns(bytes, pos + 10);
      }
    }

    pos += 2 + segLen;
  }
  return 0;
}

int _orientationToTurns(Uint8List b, int tiffStart) {
  if (tiffStart + 8 > b.length) return 0;

  final little = b[tiffStart] == 0x49 && b[tiffStart + 1] == 0x49;

  int u16(int p) =>
      little ? b[p] | (b[p + 1] << 8) : (b[p] << 8) | b[p + 1];
  int u32(int p) => little
      ? b[p] | (b[p + 1] << 8) | (b[p + 2] << 16) | (b[p + 3] << 24)
      : (b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3];

  if (u16(tiffStart + 2) != 0x2A) return 0;

  final ifd0 = tiffStart + u32(tiffStart + 4);
  if (ifd0 + 2 > b.length) return 0;

  final count = u16(ifd0);
  for (var i = 0; i < count; i++) {
    final e = ifd0 + 2 + i * 12;
    if (e + 12 > b.length) break;
    if (u16(e) != 0x0112) continue; // Orientation tag
    final type = u16(e + 2);
    final v = type == 3 ? u16(e + 8) : u32(e + 8);
    // EXIF orientation -> 90° clockwise rotations to normalize.
    return switch (v) {
      3 => 2, // 180°
      6 => 1, // 90° CW
      8 => 3, // 270° CW
      _ => 0,
    };
  }
  return 0;
}