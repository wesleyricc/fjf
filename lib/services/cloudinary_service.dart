import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart'; // Importante para usar XFile

class CloudinaryService {
  // Substitua pelo seu Cloud Name
  final String cloudName = "wesleyricc"; 
  
  // Substitua pelo nome do Preset que criou (deve ser 'Unsigned')
  final String uploadPreset = "fjf_photographer_upload"; 

  // ALTERAÇÃO: Recebe XFile em vez de File
  Future<String?> uploadImage(XFile imageFile) async {
    final url = Uri.parse("https://api.cloudinary.com/v1_1/$cloudName/image/upload");

    try {
      final request = http.MultipartRequest('POST', url);

      request.fields['upload_preset'] = uploadPreset;

      // ALTERAÇÃO CRÍTICA PARA WEB:
      // Lê os bytes do arquivo em vez de tentar ler o caminho do disco
      final bytes = await imageFile.readAsBytes();
      
      request.files.add(http.MultipartFile.fromBytes(
        'file', 
        bytes, 
        filename: imageFile.name
      ));

      final response = await request.send();

      if (response.statusCode == 200) {
        final responseData = await response.stream.toBytes();
        final responseString = String.fromCharCodes(responseData);
        final jsonMap = jsonDecode(responseString);

        return jsonMap['secure_url'];
      } else {
        print("Erro Cloudinary: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      print("Erro no upload: $e");
      return null;
    }
  }
}