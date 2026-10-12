import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

class FirebaseStorageService {
  /// Faz o upload de um [XFile] para o [bucketUrl] e [folderPath] especificados
  /// Retorna a URL pública de download da imagem.
  static Future<String?> uploadImage({
    required XFile image,
    required String bucketUrl,
    required String folderPath,
  }) async {
    try {
      final Uint8List bytes = await image.readAsBytes();
      
      // Sanitiza o nome do arquivo para evitar problemas de URL
      final sanitizedName = image.name.replaceAll(RegExp(r'[^a-zA-Z0-9.\-]'), '_');
      final String fileName = '${DateTime.now().millisecondsSinceEpoch}_$sanitizedName';
      
      // Referência no bucket específico solicitado
      final storageRef = FirebaseStorage.instanceFor(bucket: bucketUrl)
          .ref()
          .child('$folderPath/$fileName');
      
      // Envia os bytes (compatível com Flutter Web e Mobile)
      await storageRef.putData(
        bytes, 
        SettableMetadata(contentType: image.mimeType ?? 'image/png')
      );
      
      // Retorna a URL final
      final String downloadUrl = await storageRef.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      throw Exception("Falha no upload para o Storage: $e");
    }
  }
}
