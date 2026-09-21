import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scan_documnet_app/services/image_orientation.dart';

/// Builds a minimal JPEG byte stream (SOI + single APP1 EXIF segment + EOI)
/// carrying the given TIFF orientation.
Uint8List jpegWithExif(int orientation, {bool littleEndian = true}) {
  final tiff = Uint8List(8 + 2 + 12 + 4);

  if (littleEndian) {
    tiff[0] = 0x49;
    tiff[1] = 0x49;
  } else {
    tiff[0] = 0x4D;
    tiff[1] = 0x4D;
  }

  void u16(int p, int v) {
    if (littleEndian) {
      tiff[p] = v & 0xFF;
      tiff[p + 1] = (v >> 8) & 0xFF;
    } else {
      tiff[p] = (v >> 8) & 0xFF;
      tiff[p + 1] = v & 0xFF;
    }
  }

  void u32(int p, int v) {
    if (littleEndian) {
      tiff[p] = v & 0xFF;
      tiff[p + 1] = (v >> 8) & 0xFF;
      tiff[p + 2] = (v >> 16) & 0xFF;
      tiff[p + 3] = (v >> 24) & 0xFF;
    } else {
      tiff[p] = (v >> 24) & 0xFF;
      tiff[p + 1] = (v >> 16) & 0xFF;
      tiff[p + 2] = (v >> 8) & 0xFF;
      tiff[p + 3] = v & 0xFF;
    }
  }

  u16(2, 0x2A); // TIFF magic
  u32(4, 8); // IFD0 offset
  u16(8, 1); // one entry
  u16(10, 0x0112); // Orientation tag
  u16(12, 3); // SHORT
  u32(14, 1); // count
  u16(18, orientation); // value
  u32(22, 0); // next IFD

  const exifHeader = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]; // "Exif\0\0"
  final segLen = 2 + exifHeader.length + tiff.length; // includes length field itself
  final bytes = Uint8List(2 + 2 + segLen + 2);
  bytes[0] = 0xFF;
  bytes[1] = 0xD8;
  bytes[2] = 0xFF;
  bytes[3] = 0xE1;
  bytes[4] = (segLen >> 8) & 0xFF;
  bytes[5] = segLen & 0xFF;
  for (var i = 0; i < exifHeader.length; i++) {
    bytes[6 + i] = exifHeader[i];
  }
  bytes.setRange(6 + exifHeader.length, 6 + exifHeader.length + tiff.length, tiff);
  bytes[bytes.length - 2] = 0xFF;
  bytes[bytes.length - 1] = 0xD9;
  return bytes;
}

void main() {
  test('maps EXIF orientation to quarter-turn rotations', () {
    expect(jpegExifQuarterTurns(jpegWithExif(1)), 0); // normal
    expect(jpegExifQuarterTurns(jpegWithExif(3)), 2); // 180°
    expect(jpegExifQuarterTurns(jpegWithExif(6)), 1); // 90° CW
    expect(jpegExifQuarterTurns(jpegWithExif(8)), 3); // 270° CW
  });

  test('parses big-endian (Motorola) TIFF headers', () {
    expect(jpegExifQuarterTurns(jpegWithExif(6, littleEndian: false)), 1);
  });

  test('unhandled or missing orientations return no rotation', () {
    expect(jpegExifQuarterTurns(jpegWithExif(2)), 0);
    expect(jpegExifQuarterTurns(jpegWithExif(5)), 0);
    expect(jpegExifQuarterTurns(jpegWithExif(7)), 0);
  });

  test('returns zero for non-JPEG or EXIF-free JPEG data', () {
    expect(jpegExifQuarterTurns(Uint8List.fromList([0x00, 0x01, 0x02])), 0);
    expect(jpegExifQuarterTurns(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9])), 0);
  });

  test('tolerates truncated or malformed EXIF segments', () {
    expect(jpegExifQuarterTurns(jpegWithExif(6).sublist(0, 10)), 0);
    final noApp1 = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x04, 0xFF, 0xD9]);
    expect(jpegExifQuarterTurns(noApp1), 0);
  });
}