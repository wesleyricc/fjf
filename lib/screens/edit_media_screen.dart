// lib/screens/edit_media_screen.dart
import 'dart:typed_data'; // Para PWA
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import '../services/firestore_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class EditMediaScreen extends StatefulWidget {
  final DocumentSnapshot? mediaDoc; // Null se for 'Criar', preenchido se for 'Editar'

  const EditMediaScreen({super.key, this.mediaDoc});

  @override
  State<EditMediaScreen> createState() => _EditMediaScreenState();
}

class _EditMediaScreenState extends State<EditMediaScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseStorage _storage = FirebaseStorage.instanceFor(bucket: "fjfapp.appspot.com");

  // Controladores
  late TextEditingController _titleController;
  late TextEditingController _targetUrlController;
  late TextEditingController _orderController;

  // Estado da Imagem
  Uint8List? _pickedImageBytes;
  String _pickedImageName = '';
  String? _existingImageUrl;
  bool _isUploading = false;
  bool _isLoadingNextOrder = false;

  @override
  void initState() {
    super.initState();
    final data = widget.mediaDoc?.data() as Map<String, dynamic>?;

    _titleController = TextEditingController(text: data?['title'] ?? '');
    _targetUrlController = TextEditingController(text: data?['targetUrl'] ?? '');
    _orderController = TextEditingController(text: data?['order']?.toString() ?? '');
    _existingImageUrl = data?['imageUrl'];

    // Se for 'Criar' (mediaDoc == null), busca a próxima ordem
    if (widget.mediaDoc == null) {
      _fetchNextOrderNumber();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _targetUrlController.dispose();
    _orderController.dispose();
    super.dispose();
  }

  Future<void> _fetchNextOrderNumber() async {
    setState(() { _isLoadingNextOrder = true; });
    final nextOrder = await _firestoreService.getNextMediaOrder();
    _orderController.text = nextOrder.toString();
    setState(() { _isLoadingNextOrder = false; });
  }

  Future<void> _pickImage() async {
    if (_isUploading) return;
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true, // Força PWA a ler bytes
      );
      if (result != null && result.files.single.bytes != null) {
        setState(() {
          _pickedImageBytes = result.files.single.bytes;
          _pickedImageName = result.files.single.name;
          _existingImageUrl = null; // Remove a imagem antiga da pré-visualização
        });
      }
    } catch (e) {
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao selecionar imagem: $e')));
    }
  }

  Future<void> _saveForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (_pickedImageBytes == null && _existingImageUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, selecione uma imagem.')));
      return;
    }

    setState(() { _isUploading = true; });

    String finalImageUrl = _existingImageUrl ?? '';

    try {
      // 1. Se uma nova imagem foi selecionada, faça o upload dela
      if (_pickedImageBytes != null) {
        debugPrint("Iniciando upload de imagem da mídia...");
        final String fileName = '${DateTime.now().millisecondsSinceEpoch}_$_pickedImageName';
        final String storagePath = 'news_media/$fileName';
        final ref = _storage.ref().child(storagePath);
        
        final metadata = SettableMetadata(contentType: 'image/${fileName.split('.').last}');
        UploadTask uploadTask = ref.putData(_pickedImageBytes!, metadata);
        TaskSnapshot snapshot = await uploadTask;
        finalImageUrl = await snapshot.ref.getDownloadURL(); // Pega a nova URL
        debugPrint("Upload de mídia concluído: $finalImageUrl");
      }

      // 2. Prepara os dados para o Firestore
      final String title = _titleController.text;
      final String targetUrl = _targetUrlController.text;
      final int order = int.tryParse(_orderController.text) ?? 1;

      String result;
      if (widget.mediaDoc == null) {
        // --- MODO CRIAÇÃO ---
        result = await _firestoreService.createMediaItem(
          title: title,
          targetUrl: targetUrl,
          imageUrl: finalImageUrl,
          order: order,
        );
      } else {
        // --- MODO ATUALIZAÇÃO ---
        // Se uma nova imagem foi upada E existia uma antiga, delete a antiga
        if (_pickedImageBytes != null && _existingImageUrl != null && _existingImageUrl!.isNotEmpty) {
           try {
             await _storage.refFromURL(_existingImageUrl!).delete();
           } catch (e) {
              debugPrint("Aviso: Falha ao deletar imagem antiga: $e");
           }
        }
        
        result = await _firestoreService.updateMediaItem(
          docId: widget.mediaDoc!.id,
          title: title,
          targetUrl: targetUrl,
          imageUrl: finalImageUrl,
          order: order,
        );
      }
      
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
         if (result.startsWith('Sucesso')) {
            Navigator.of(context).pop();
         }
      }

    } catch (e) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
    } finally {
       if (mounted) setState(() { _isUploading = false; });
    }
  }

  Widget _buildImagePreview() {
    if (_pickedImageBytes != null) {
      // 1. Preview da Nova Imagem (em bytes)
      return Image.memory(
        _pickedImageBytes!,
        width: double.infinity, height: 150, fit: BoxFit.cover,
      );
    }
    if (_existingImageUrl != null) {
      // 2. Preview da Imagem Antiga (da URL)
      return CachedNetworkImage(
        imageUrl: _existingImageUrl!,
        width: double.infinity, height: 150, fit: BoxFit.cover,
        placeholder: (c,u) => const SizedBox(height: 150, child: Center(child: CircularProgressIndicator())),
        errorWidget: (c,u,e) => const SizedBox(height: 150, child: Center(child: Icon(Icons.broken_image, color: Colors.red))),
      );
    }
    // 3. Placeholder
    return Container(
      height: 150,
      width: double.infinity,
      color: Colors.grey[200],
      child: const Center(child: Text('Nenhuma imagem selecionada.', style: TextStyle(color: Colors.grey))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mediaDoc == null ? 'Criar Mídia' : 'Editar Mídia'),
        actions: [
          IconButton(
            icon: _isUploading 
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white))
              : const Icon(Icons.save),
            onPressed: _isUploading ? null : _saveForm,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // Preview da Imagem
            _buildImagePreview(),
            const SizedBox(height: 8),
            // Botão Selecionar Imagem
            ElevatedButton.icon(
              icon: const Icon(Icons.image),
              label: Text(_existingImageUrl != null ? 'Trocar Imagem' : 'Selecionar Imagem'),
              onPressed: _isUploading ? null : _pickImage,
            ),
            const Divider(height: 24),
            // Título
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Título da Mídia', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null,
              enabled: !_isUploading,
            ),
            const SizedBox(height: 16),
            // URL de Destino
            TextFormField(
              controller: _targetUrlController,
              decoration: const InputDecoration(labelText: 'URL de Destino (link)', hintText: 'https://youtube.com/...', border: OutlineInputBorder()),
              keyboardType: TextInputType.url,
              validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null,
              enabled: !_isUploading,
            ),
            const SizedBox(height: 16),
            // Ordem
            TextFormField(
              controller: _orderController,
              decoration: InputDecoration(
                labelText: 'Ordem',
                border: const OutlineInputBorder(),
                suffixIcon: _isLoadingNextOrder ? const Padding(padding: EdgeInsets.all(10.0), child: CircularProgressIndicator(strokeWidth: 2)) : null,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null,
              enabled: !_isUploading && !_isLoadingNextOrder,
            ),
          ],
        ),
      ),
    );
  }
}