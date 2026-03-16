// Web: ensure file_picker platform is set so FilePicker.platform is available.

import 'package:file_picker/_internal/file_picker_web.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

void initFilePickerWeb() {
  FilePickerWeb.registerWith(webPluginRegistrar);
}
