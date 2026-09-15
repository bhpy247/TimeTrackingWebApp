import 'dart:io';
import 'dart:typed_data';
import 'package:open_file_plus/open_file_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<Directory> _getDestinationDirectory() async {
  if (Platform.isAndroid) {
    // 1. Try standard Android public Download folder
    final primaryDownload = Directory('/storage/emulated/0/Download');
    if (await primaryDownload.exists()) {
      return primaryDownload;
    }

    // 2. Try path_provider downloads directory
    try {
      final downloadDir = await getDownloadsDirectory();
      if (downloadDir != null && await downloadDir.exists()) {
        return downloadDir;
      }
    } catch (_) {}

    // 3. Try external storage app download directory
    try {
      final extDirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
      if (extDirs != null && extDirs.isNotEmpty && await extDirs.first.exists()) {
        return extDirs.first;
      }
    } catch (_) {}

    // 4. Try general external storage directory
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null && await extDir.exists()) {
        return extDir;
      }
    } catch (_) {}
  } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    try {
      final downloadDir = await getDownloadsDirectory();
      if (downloadDir != null && await downloadDir.exists()) {
        return downloadDir;
      }
    } catch (_) {}
  }

  // Fallback to application documents
  return await getApplicationDocumentsDirectory();
}

Future<String> saveAndShareFile(Uint8List bytes, String filename, String mimeType) async {
  final directory = await _getDestinationDirectory();
  final filePath = p.join(directory.path, filename);
  final file = File(filePath);
  await file.writeAsBytes(bytes);
  return filePath;
}

void openFileInNewTab(Uint8List bytes, String mimeType) {
  // Web specific - no-op on native platforms
}

Future<void> openDownloadedFile(String filePath, {String? mimeType, Uint8List? bytes}) async {
  try {
    await OpenFile.open(filePath, type: mimeType);
  } catch (e) {
    // Fallback to share sheet if direct open fails
    await shareDownloadedFile(filePath);
  }
}

Future<void> shareDownloadedFile(
  String filePath, {
  String? subject,
  String? text,
  Uint8List? bytes,
  String? filename,
}) async {
  try {
    final xfile = XFile(filePath);
    await Share.shareXFiles([xfile], text: text, subject: subject);
  } catch (_) {}
}
