import 'dart:convert';

import '../constants/app_constants.dart';
import 'e2e_envelope.dart';

/// True when [text] fits the sendable size budget.
///
/// Measures the ACTUAL encrypted input — the UTF-8 byte size of the JSON-encoded
/// E2E envelope — not the raw string, because JSON escaping (quotes, backslashes,
/// control chars) and multi-byte emoji/ZWJ sequences all change the encrypted
/// size. The server caps the resulting base64 ciphertext at 65536 chars;
/// [AppConstants.maxEnvelopeBytes] leaves headroom for base64 (~4/3) growth plus
/// Signal/prekey overhead.
bool isMessageWithinByteLimit(String text) =>
    utf8.encode(jsonEncode(E2eEnvelope.build(text))).length <=
    AppConstants.maxEnvelopeBytes;
