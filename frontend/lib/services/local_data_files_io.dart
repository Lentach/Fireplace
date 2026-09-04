import 'dart:io';

import 'package:flutter/foundation.dart';

import 'encryption/content_db.dart';

/// Native: delete the SQLCipher content store, WAL and shm included.
///
/// Only Android ships, and only there does a directory exist to look in — on
/// a test host `getApplicationSupportDirectory` has no platform channel, so
/// asking would throw and report a failed arm for a store that was never
/// created.
Future<bool> deleteLocalMessageStoreFiles() async {
  if (kIsWeb || !Platform.isAndroid) return true;
  return DriftRecordDb.deleteDatabaseFiles();
}
