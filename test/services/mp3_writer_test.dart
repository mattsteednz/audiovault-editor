import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault_editor/services/writers/mp3_writer.dart';

void main() {
  group('Mp3Writer syncsafe integers', () {
    test('round-trips small value', () {
      final buf = Uint8List(4);
      Mp3Writer.syncsafeEncode(127, buf, 0);
      expect(Mp3Writer.syncsafeDecode(buf, 0), 127);
    });

    test('round-trips large value', () {
      final buf = Uint8List(4);
      Mp3Writer.syncsafeEncode(268435455, buf, 0); // max 28-bit syncsafe
      expect(Mp3Writer.syncsafeDecode(buf, 0), 268435455);
    });

    test('round-trips zero', () {
      final buf = Uint8List(4);
      Mp3Writer.syncsafeEncode(0, buf, 0);
      expect(Mp3Writer.syncsafeDecode(buf, 0), 0);
    });

    test('encodes to correct bytes for value 1000', () {
      // 1000 in syncsafe: 1000 = 0b1111101000
      // split into 7-bit groups: 0b0000111 0b1101000 = 7, 104
      final buf = Uint8List(4);
      Mp3Writer.syncsafeEncode(1000, buf, 0);
      expect(buf[2], 7);
      expect(buf[3], 104);
    });

    test('offset parameter is respected', () {
      final buf = Uint8List(8);
      Mp3Writer.syncsafeEncode(500, buf, 4);
      expect(Mp3Writer.syncsafeDecode(buf, 4), 500);
      // bytes before offset are untouched
      expect(buf[0], 0);
      expect(buf[1], 0);
    });
  });
}
