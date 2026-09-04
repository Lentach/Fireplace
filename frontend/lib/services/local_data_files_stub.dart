/// Web: the message store is not a file. Everything lives in the origin's
/// browser storage, which `utils/origin_storage_wipe.dart` destroys.
Future<bool> deleteLocalMessageStoreFiles() async => true;
