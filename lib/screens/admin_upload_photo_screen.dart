import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'; // Para kIsWeb
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/cloudinary_service.dart';

class AdminUploadPhotoScreen extends StatefulWidget {
  const AdminUploadPhotoScreen({super.key});

  @override
  State<AdminUploadPhotoScreen> createState() => _AdminUploadPhotoScreenState();
}

class _AdminUploadPhotoScreenState extends State<AdminUploadPhotoScreen> {
  final _cloudinaryService = CloudinaryService();
  final _priceController = TextEditingController(text: "10.00");
  final _folderController = TextEditingController(); // Antigo event_name, agora Tag/Pasta
  
  // Lista de imagens selecionadas
  List<XFile> _selectedFiles = [];
  // Cache de bytes para preview na Web
  Map<String, Uint8List> _webImagesBytes = {};
  
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _uploadStatus = "";

  // Selecionar MÚLTIPLAS imagens
  Future<void> _pickImages() async {
    final picker = ImagePicker();
    // Permite selecionar várias
    final List<XFile> images = await picker.pickMultiImage(imageQuality: 85);

    if (images.isNotEmpty) {
      if (kIsWeb) {
        // Para web, precisamos ler os bytes de cada uma para mostrar o preview
        for (var img in images) {
          final bytes = await img.readAsBytes();
          _webImagesBytes[img.path] = bytes;
        }
      }
      
      setState(() {
        _selectedFiles.addAll(images);
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      final file = _selectedFiles[index];
      _webImagesBytes.remove(file.path);
      _selectedFiles.removeAt(index);
    });
  }

  Future<void> _uploadAll() async {
    if (_selectedFiles.isEmpty) return;
    if (_folderController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, informe o nome da Pasta/Tag.'))
      );
      return;
    }
    
    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    int total = _selectedFiles.length;
    int successCount = 0;
    double price = double.tryParse(_priceController.text.replaceAll(',', '.')) ?? 10.0;
    String folderName = _folderController.text.trim();

    try {
      // Loop de Upload
      for (int i = 0; i < total; i++) {
        final file = _selectedFiles[i];
        
        setState(() {
          _uploadStatus = "Enviando ${i + 1} de $total...";
          _uploadProgress = (i / total);
        });

        // 1. Upload Cloudinary
        final String? imageUrl = await _cloudinaryService.uploadImage(file);

        if (imageUrl != null) {
          // 2. Salva no Firestore
          await FirebaseFirestore.instance.collection('photo_sales').add({
            'original_url': imageUrl,
            'price': price,
            'event_name': folderName, // Usado como Tag/Pasta
            'taken_at': FieldValue.serverTimestamp(),
            'photographer_id': 'admin_fjf',
            'status': 'active',
          });
          successCount++;
        }
      }

      // Finalização
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$successCount de $total fotos enviadas com sucesso!'))
        );
        setState(() {
          _selectedFiles.clear();
          _webImagesBytes.clear();
          _isUploading = false;
          _uploadStatus = "";
          _uploadProgress = 0;
          // Não limpamos a pasta nem o preço para facilitar o envio de mais lotes
        });
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Upload em Massa")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- 1. CONFIGURAÇÕES DO LOTE ---
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _folderController,
                      decoration: const InputDecoration(
                        labelText: "Nome da Pasta / Tag (Obrigatório)",
                        hintText: "Ex: Rodada 1 - Time A x Time B",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.folder),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: "Preço por foto (R\$)",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.attach_money),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // --- 2. BOTÃO DE SELEÇÃO ---
            OutlinedButton.icon(
              onPressed: _isUploading ? null : _pickImages,
              icon: const Icon(Icons.add_photo_alternate),
              label: Text(_selectedFiles.isEmpty ? "Selecionar Fotos" : "Adicionar Mais Fotos"),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16)),
            ),
            
            const SizedBox(height: 10),

            // --- 3. GRID DE PREVIEW ---
            if (_selectedFiles.isNotEmpty) ...[
               Text("${_selectedFiles.length} fotos selecionadas", style: const TextStyle(fontWeight: FontWeight.bold)),
               const SizedBox(height: 10),
               GridView.builder(
                 shrinkWrap: true,
                 physics: const NeverScrollableScrollPhysics(),
                 gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                   crossAxisCount: 3, 
                   crossAxisSpacing: 4, 
                   mainAxisSpacing: 4
                 ),
                 itemCount: _selectedFiles.length,
                 itemBuilder: (context, index) {
                   return Stack(
                     fit: StackFit.expand,
                     children: [
                       _buildThumbnail(index),
                       Positioned(
                         top: 0, right: 0,
                         child: GestureDetector(
                           onTap: _isUploading ? null : () => _removeImage(index),
                           child: Container(
                             color: Colors.red.withOpacity(0.8),
                             child: const Icon(Icons.close, color: Colors.white, size: 20),
                           ),
                         ),
                       )
                     ],
                   );
                 },
               ),
               const SizedBox(height: 20),
            ],

            // --- 4. BARRA DE PROGRESSO E AÇÃO ---
            if (_isUploading) ...[
              LinearProgressIndicator(value: _uploadProgress),
              const SizedBox(height: 8),
              Text(_uploadStatus, textAlign: TextAlign.center),
              const SizedBox(height: 20),
            ],

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
              onPressed: (_isUploading || _selectedFiles.isEmpty) ? null : _uploadAll,
              icon: const Icon(Icons.cloud_upload),
              label: Text(_isUploading ? "Processando..." : "Enviar Todas"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(int index) {
    final file = _selectedFiles[index];
    if (kIsWeb) {
      final bytes = _webImagesBytes[file.path];
      if (bytes != null) {
        return Image.memory(bytes, fit: BoxFit.cover);
      }
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else {
      return Image.file(File(file.path), fit: BoxFit.cover);
    }
  }
}