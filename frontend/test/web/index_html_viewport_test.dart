import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('index.html uses overlays-content for virtual keyboard overlay', () {
    final html = File('web/index.html').readAsStringSync();
    expect(
      html,
      contains('interactive-widget=overlays-content'),
      reason:
          'Keyboard should overlay the Flutter canvas instead of resizing layout viewport',
    );
  });
}
