import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<void> saveAndShareFile(Uint8List bytes, String filename, String mimeType) async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File(p.join(directory.path, filename));
  await file.writeAsBytes(bytes);
}
