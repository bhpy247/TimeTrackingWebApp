import 'dart:html' as html;
import 'dart:typed_data';

Future<String> saveAndShareFile(Uint8List bytes, String filename, String mimeType) async {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..setAttribute("download", filename)
    ..style.display = 'none';

  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();

  // Keep object URL alive long enough for browser to process the download
  Future.delayed(const Duration(seconds: 15), () {
    html.Url.revokeObjectUrl(url);
  });

  return 'Downloads folder ($filename)';
}

void openFileInNewTab(Uint8List bytes, String mimeType) {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');

  Future.delayed(const Duration(seconds: 60), () {
    html.Url.revokeObjectUrl(url);
  });
}

Future<void> openDownloadedFile(String filePath, {String? mimeType, Uint8List? bytes}) async {
  if (bytes != null && mimeType != null) {
    openFileInNewTab(bytes, mimeType);
  }
}

Future<void> shareDownloadedFile(
  String filePath, {
  String? subject,
  String? text,
  Uint8List? bytes,
  String? filename,
}) async {
  if (bytes != null && filename != null) {
    saveAndShareFile(bytes, filename, 'application/octet-stream');
  }
}
