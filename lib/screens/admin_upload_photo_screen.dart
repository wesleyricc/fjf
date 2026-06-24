import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io' show File;

// IMPORTAÇÃO DO SEU SERVIÇO
import '../services/cloudinary_service.dart';

class AdminUploadPhotoScreen extends StatefulWidget {
  const AdminUploadPhotoScreen({super.key});

  @override
  State<AdminUploadPhotoScreen> createState() => _AdminUploadPhotoScreenState();
}

class _AdminUploadPhotoScreenState extends State<AdminUploadPhotoScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _eventNameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController(text: '10.00');
  
  // Instância do seu serviço do Cloudinary
  final CloudinaryService _cloudinaryService = CloudinaryService();

  List<XFile> _selectedImages = [];
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  Future<void> _pickImages() async {
    final ImagePicker picker = ImagePicker();
    final List<XFile> images = await picker.pickMultiImage();
    if (images.isNotEmpty) {
      setState(() {
        _selectedImages.addAll(images);
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

 // 🚨 SEGURANÇA MÁXIMA (MALHA ANTI-IA): Gera a URL de preview com marcas repetidas!
  String _generatePreviewUrl(String originalUrl) {
    if (originalUrl.contains('/upload/')) {
      // O que está acontecendo aqui:
      // 1. q_30,w_600: Baixa qualidade e resolução menor.
      // 2. l_text:Arial_35_bold:FJF%20PREVIEW%20%20%20%20 : O texto "FJF PREVIEW" (com espaços no fim para dar um respiro entre as repetições).
      // 3. co_white,o_50,a_-30: Cor branca, opacidade em 50%, inclinado a -30 graus.
      // 4. fl_tiled: 🚨 O MÁGICO! Ele clona esse texto e forra a imagem inteira com ele.
      return originalUrl.replaceFirst(
        '/upload/', 
        '/upload/q_30,w_600/l_text:Arial_35_bold:FJF%20PREVIEW%20%20%20%20,co_white,o_50,a_-30,fl_tiled/'
      );
    }
    return originalUrl;
  }

  Future<void> _uploadAll() async {
    if (!_formKey.currentState!.validate() || _selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Preencha os campos e selecione fotos.")),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    final String eventName = _eventNameController.text.trim();
    final double price = double.tryParse(_priceController.text.replaceAll(',', '.')) ?? 10.0;
    final int currentYear = DateTime.now().year;
    
    // Gerar um ID único e amigável para a pasta (Álbum)
    final String albumId = "${eventName.replaceAll(' ', '-').toLowerCase()}-$currentYear";
    
    String? firstPhotoCoverUrl;
    int successCount = 0;

    try {
      for (int i = 0; i < _selectedImages.length; i++) {
        final image = _selectedImages[i];
        
        // ==========================================================
        // 1. CHAMA O SEU SERVICE DO CLOUDINARY
        // ==========================================================
        final originalUrl = await _cloudinaryService.uploadImage(image);
        
        if (originalUrl != null) {
          final previewUrl = _generatePreviewUrl(originalUrl);
          
          if (firstPhotoCoverUrl == null) {
            firstPhotoCoverUrl = previewUrl; // Salva a 1ª foto para ser a capa do álbum
          }

          // 2. Salva na coleção photo_sales (Fotos individuais - Usado na Paginação)
          await FirebaseFirestore.instance.collection('photo_sales').add({
            'event_name': eventName,
            'original_url': originalUrl,
            'preview_url': previewUrl,
            'price': price,
            'taken_at': FieldValue.serverTimestamp(),
            'created_at': FieldValue.serverTimestamp(),
          });
          successCount++;
        }

        setState(() {
          _uploadProgress = (i + 1) / _selectedImages.length;
        });
      }

      // ==========================================================
      // 3. CRIA/ATUALIZA O ÍNDICE DO ÁLBUM (Otimização da Loja)
      // ==========================================================
      if (firstPhotoCoverUrl != null) {
        await FirebaseFirestore.instance.collection('photo_albums').doc(albumId).set({
          'name': eventName,
          'year': currentYear,
          'coverUrl': firstPhotoCoverUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)); // Merge evita sobrescrever álbuns já existentes (caso você adicione fotos depois)
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$successCount fotos enviadas para o álbum $eventName!")),
        );
        setState(() {
          _selectedImages.clear();
          _eventNameController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro fatal no envio: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  // Helper para preview da imagem selecionada (suporte nativo para Web e Mobile)
  Widget _buildImagePreview(XFile image) {
    if (kIsWeb) {
      return Image.network(image.path, fit: BoxFit.cover);
    } else {
      return Image.file(File(image.path), fit: BoxFit.cover);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Enviar Fotos (Admin)")),
      body: _isUploading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(value: _uploadProgress, color: const Color(0xFF32BCAD)),
                  const SizedBox(height: 20),
                  Text("Enviando... ${(_uploadProgress * 100).toInt()}%", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  const Text("Não feche o aplicativo ou a guia do navegador.", style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _eventNameController,
                      decoration: const InputDecoration(
                        labelText: "Nome do Evento / Álbum",
                        hintText: "Ex: Final Sub-15",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.event),
                      ),
                      validator: (v) => v == null || v.isEmpty ? "Informe o nome do evento" : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: "Preço por Foto (R\$)",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.attach_money),
                      ),
                      validator: (v) => v == null || v.isEmpty ? "Informe o preço" : null,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _pickImages,
                      icon: const Icon(Icons.add_photo_alternate),
                      label: const Text("Selecionar Fotos"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_selectedImages.isNotEmpty) ...[
                      Text("${_selectedImages.length} fotos selecionadas", style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 120,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _selectedImages.length,
                          itemBuilder: (context, index) {
                            return Stack(
                              children: [
                                Container(
                                  width: 100,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: _buildImagePreview(_selectedImages[index]),
                                ),
                                Positioned(
                                  top: 0, right: 8,
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                    child: IconButton(
                                      icon: const Icon(Icons.remove_circle, color: Colors.red),
                                      onPressed: () => _removeImage(index),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                  ),
                                )
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: _uploadAll,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF32BCAD),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text("INICIAR UPLOAD", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ]
                  ],
                ),
              ),
            ),
    );
  }
}