import 'dart:typed_data'; 
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart'; 
import '../../services/championship_service.dart';
import '../../services/media_service.dart';

class EditMediaScreen extends StatefulWidget {
  final DocumentSnapshot? mediaDoc; 

  const EditMediaScreen({super.key, this.mediaDoc});

  @override
  State<EditMediaScreen> createState() => _EditMediaScreenState();
}

class _EditMediaScreenState extends State<EditMediaScreen> {
  final _formKey = GlobalKey<FormState>();
  // OTIMIZAÇÃO: Usa a instância padrão do Storage
  final FirebaseStorage _storage = FirebaseStorage.instance;

  late TextEditingController _titleController;
  late TextEditingController _targetUrlController;
  late TextEditingController _orderController;
  late TextEditingController _authorController;

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
    _authorController = TextEditingController(text: data?['author'] ?? '');
    _existingImageUrl = data?['imageUrl'];

    if (widget.mediaDoc == null) {
      _fetchNextOrderNumber();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _targetUrlController.dispose();
    _orderController.dispose();
    _authorController.dispose();
    super.dispose();
  }

  Future<void> _fetchNextOrderNumber() async {
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    final mediaService = Provider.of<MediaService>(context, listen: false);
    
    setState(() { _isLoadingNextOrder = true; });
    final nextOrder = await mediaService.getNextMediaOrder(seasonId); 
    _orderController.text = nextOrder.toString();
    setState(() { _isLoadingNextOrder = false; });
  }

  Future<void> _pickImage() async {
    if (_isUploading) return;
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true, 
      );
      if (result != null && result.files.single.bytes != null) {
        setState(() {
          _pickedImageBytes = result.files.single.bytes;
          _pickedImageName = result.files.single.name;
          _existingImageUrl = null; 
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

    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    final mediaService = Provider.of<MediaService>(context, listen: false);

    String finalImageUrl = _existingImageUrl ?? '';

    try {
      if (_pickedImageBytes != null) {
        final String fileName = '${DateTime.now().millisecondsSinceEpoch}_$_pickedImageName';
        final String storagePath = 'news_media/$fileName';
        final ref = _storage.ref().child(storagePath);
        
        final metadata = SettableMetadata(contentType: 'image/${fileName.split('.').last}');
        UploadTask uploadTask = ref.putData(_pickedImageBytes!, metadata);
        TaskSnapshot snapshot = await uploadTask;
        finalImageUrl = await snapshot.ref.getDownloadURL(); 
      }

      final String title = _titleController.text;
      final String targetUrl = _targetUrlController.text;
      final String author = _authorController.text;
      final int order = int.tryParse(_orderController.text) ?? 1;

      String result;
      if (widget.mediaDoc == null) {
        result = await mediaService.createMediaItem(
          seasonId: seasonId,
          title: title,
          targetUrl: targetUrl,
          imageUrl: finalImageUrl,
          order: order,
          author: author,
        );
      } else {
        if (_pickedImageBytes != null && _existingImageUrl != null && _existingImageUrl!.isNotEmpty) {
           try {
             await _storage.refFromURL(_existingImageUrl!).delete();
           } catch (e) {
              debugPrint("Aviso: Falha ao deletar imagem antiga: $e");
           }
        }
        
        result = await mediaService.updateMediaItem(
          seasonId: seasonId,
          docId: widget.mediaDoc!.id,
          title: title,
          targetUrl: targetUrl,
          imageUrl: finalImageUrl,
          order: order,
          author: author,
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
      return Image.memory(
        _pickedImageBytes!,
        width: double.infinity, height: 150, fit: BoxFit.cover,
      );
    }
    if (_existingImageUrl != null) {
      return CachedNetworkImage(
        imageUrl: _existingImageUrl!,
        width: double.infinity, height: 150, fit: BoxFit.cover,
        placeholder: (c,u) => const SizedBox(height: 150, child: Center(child: CircularProgressIndicator())),
        errorWidget: (c,u,e) => const SizedBox(height: 150, child: Center(child: Icon(Icons.broken_image, color: Colors.red))),
      );
    }
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
            _buildImagePreview(),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.image),
              label: Text(_existingImageUrl != null ? 'Trocar Imagem' : 'Selecionar Imagem'),
              onPressed: _isUploading ? null : _pickImage,
            ),
            const Divider(height: 24),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Título da Mídia', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null,
              enabled: !_isUploading,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _authorController,
              decoration: const InputDecoration(labelText: 'Autor da Notícia', hintText: 'Ex: Agora na Cidade', border: OutlineInputBorder()),
              enabled: !_isUploading,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _targetUrlController,
              decoration: const InputDecoration(labelText: 'URL de Destino (link)', hintText: 'https://youtube.com/...', border: OutlineInputBorder()),
              keyboardType: TextInputType.url,
              validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null,
              enabled: !_isUploading,
            ),
            const SizedBox(height: 16),
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