import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../models/fantasy_league_model.dart';
import '../../services/fantasy_auth_service.dart';
import '../../utils/app_feedback.dart';

class AdminEditSponsoredLeagueScreen extends StatefulWidget {
  final FantasyLeague? league;

  const AdminEditSponsoredLeagueScreen({super.key, this.league});

  @override
  State<AdminEditSponsoredLeagueScreen> createState() => _AdminEditSponsoredLeagueScreenState();
}

class _AdminEditSponsoredLeagueScreenState extends State<AdminEditSponsoredLeagueScreen> {
  final _nameController = TextEditingController();
  final _prizeController = TextEditingController();
  
  XFile? _imageFile;
  bool _isSaving = false;
  String? _existingImageUrl;

  @override
  void initState() {
    super.initState();
    if (widget.league != null) {
      _nameController.text = widget.league!.name;
      _prizeController.text = widget.league!.prizeDescription ?? '';
      _existingImageUrl = widget.league!.sponsorImageUrl;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _prizeController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image != null) {
      setState(() {
        _imageFile = image;
      });
    }
  }

  Future<String?> _uploadImage() async {
    if (_imageFile == null) return _existingImageUrl;

    try {
      final fileName = 'sponsor_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref().child('fantasy_leagues_sponsors').child(fileName);
      
      await ref.putData(await _imageFile!.readAsBytes());
      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint("Erro ao fazer upload da imagem: $e");
      return null;
    }
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      AppFeedback.showError(context, "O nome da liga é obrigatório!");
      return;
    }

    setState(() => _isSaving = true);

    try {
      String? finalImageUrl = await _uploadImage();

      final ownerId = Provider.of<FantasyAuthService>(context, listen: false).user?.uid ?? '';
      
      final leagueData = {
        'name': _nameController.text.trim(),
        'is_sponsored': true,
        'sponsor_image_url': finalImageUrl,
        'prize_description': _prizeController.text.trim(),
      };

      if (widget.league == null) {
        // Criar
        leagueData['owner_id'] = ownerId;
        leagueData['type'] = 'classic';
        leagueData['members'] = [];
        leagueData['invite_code'] = ''; // Ligas patrocinadas não precisam de código

        await FirebaseFirestore.instance.collection('fantasy_leagues').add(leagueData);
        if (mounted) AppFeedback.showSuccess(context, "Liga criada com sucesso!");
      } else {
        // Atualizar
        await FirebaseFirestore.instance.collection('fantasy_leagues').doc(widget.league!.id).update(leagueData);
        if (mounted) AppFeedback.showSuccess(context, "Liga atualizada com sucesso!");
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) AppFeedback.showError(context, "Erro ao salvar liga: $e");
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Excluir Liga"),
        content: const Text("Tem certeza que deseja excluir esta liga patrocinada?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Excluir")
          ),
        ],
      )
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('fantasy_leagues').doc(widget.league!.id).delete();
      if (mounted) {
        AppFeedback.showSuccess(context, "Liga excluída!");
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) AppFeedback.showError(context, "Erro ao excluir: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.league != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? "Editar Liga Patrocinada" : "Nova Liga Patrocinada"),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _delete,
            )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[400]!),
                ),
                child: _buildImagePreview(),
              ),
            ),
            const SizedBox(height: 8),
            const Center(child: Text("Toque para alterar a imagem do patrocinador", style: TextStyle(color: Colors.grey, fontSize: 12))),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: "Nome da Liga",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _prizeController,
              decoration: const InputDecoration(
                labelText: "Descrição do Prêmio (Opcional)",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _isSaving ? null : _save,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
              ),
              child: _isSaving
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text("Salvar Liga Patrocinada", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    if (_imageFile != null) {
      if (kIsWeb) {
        return ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(_imageFile!.path, fit: BoxFit.cover));
      } else {
        return ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(_imageFile!.path), fit: BoxFit.cover));
      }
    } else if (_existingImageUrl != null && _existingImageUrl!.isNotEmpty) {
      return ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(_existingImageUrl!, fit: BoxFit.cover));
    } else {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate, size: 50, color: Colors.grey),
            SizedBox(height: 8),
            Text("Adicionar Imagem", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }
  }
}
