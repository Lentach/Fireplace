import 'package:fireplace/widgets/input/recording_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RecordingControllerState', () {
    test('kMinVoiceRecordingMs is 500ms from actual recording start', () {
      expect(RecordingControllerState.kMinVoiceRecordingMs, 500);
    });
  });

  group('MicRecordingPermissionDenied', () {
    test('is distinct from generic Exception for start-recording catch', () {
      expect(const MicRecordingPermissionDenied(), isA<Exception>());
      expect(const MicRecordingPermissionDenied(), isNot(isA<StateError>()));
    });
  });
}
