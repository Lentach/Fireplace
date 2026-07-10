import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'approved ping sound is a short, unclipped WAV with a silent tail',
    () async {
      final data = await rootBundle.load('assets/sounds/ping_alert.wav');
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final view = ByteData.sublistView(bytes);

      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(view.getUint16(22, Endian.little), 1); // mono
      expect(view.getUint32(24, Endian.little), 48000);
      expect(view.getUint16(34, Endian.little), 16);

      final dataBytes = view.getUint32(40, Endian.little);
      final sampleCount = dataBytes ~/ 2;
      expect(sampleCount / 48000, closeTo(0.42, 0.001));

      var peak = 0;
      for (var offset = 44; offset < 44 + dataBytes; offset += 2) {
        final sample = view.getInt16(offset, Endian.little).abs();
        if (sample > peak) peak = sample;
      }
      expect(peak, greaterThan(0));
      expect(peak, lessThan(32767));

      // The approved render fades to exact silence instead of cutting a live
      // oscillator at EOF, which would create an audible click.
      for (
        var offset = bytes.length - 200;
        offset < bytes.length;
        offset += 2
      ) {
        expect(view.getInt16(offset, Endian.little), 0);
      }
    },
  );
}
