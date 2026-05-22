import 'package:fireplace/utils/portrait_lock_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('portrait never shows overlay', () {
    expect(
      shouldShowRotateOverlay(
        orientation: Orientation.portrait,
        logicalSize: const Size(390, 844),
      ),
      isFalse,
    );
  });

  test('phone landscape shows overlay', () {
    expect(
      shouldShowRotateOverlay(
        orientation: Orientation.landscape,
        logicalSize: const Size(844, 390),
      ),
      isTrue,
    );
  });

  test('desktop landscape does not show overlay', () {
    expect(
      shouldShowRotateOverlay(
        orientation: Orientation.landscape,
        logicalSize: const Size(1920, 1080),
      ),
      isFalse,
    );
  });

  test('iPad landscape shows overlay', () {
    expect(
      shouldShowRotateOverlay(
        orientation: Orientation.landscape,
        logicalSize: const Size(1180, 820),
      ),
      isTrue,
    );
  });
}
