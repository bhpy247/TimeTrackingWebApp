import 'dart:typed_data';

Future<String> saveAndShareFile(Uint8List bytes, String filename, String mimeType) async {
  throw UnsupportedError('Saving files is not supported on this platform.');
}

void openFileInNewTab(Uint8List bytes, String mimeType) {
  throw UnsupportedError('Opening files is not supported on this platform.');
}

Future<void> openDownloadedFile(String filePath, {String? mimeType, Uint8List? bytes}) async {
  throw UnsupportedError('Opening files is not supported on this platform.');
}

Future<void> shareDownloadedFile(
  String filePath, {
  String? subject,
  String? text,
  Uint8List? bytes,
  String? filename,
}) async {
  throw UnsupportedError('Sharing files is not supported on this platform.');
}
