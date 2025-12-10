// lib/screens/edit_voting_nominee_screen.dart
import 'dart:typed_data'; 
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart'; 

class EditVotingNomineeScreen extends StatefulWidget {
  const EditVotingNomineeScreen({super.key});

  @override
  State<EditVotingNomineeScreen> createState() => _EditVotingNomineeScreenState();
}

class _EditVotingNomineeScreenState extends State<EditVotingNomineeScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instanceFor(bucket: "fjfapp.firebasestorage.app");

  String _selectedCategory = 'revelacao'; 
  bool _isSaving = false;

  final _descriptionController = TextEditingController(); 
  Uint8List? _videoBytes;
  String _videoName = '';
  
  DocumentSnapshot? _selectedPlayerDoc;

  // --- ALTERAÇÃO: Adicionado 'melhor_jogador' nas categorias manuais ---
  final Map<String, String> _categories = {
    'melhor_jogador': 'Melhor Jogador (Principal)',
    'revelacao': 'Revelação (Jogador)',
    'bola_cheia': 'Bola Cheia (Vídeo + Jogador)',
    'bola_murcha': 'Bola Murcha (Vídeo + Jogador)',
  };

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.video, withData: true);
      if (result != null && result.files.single.bytes != null) {
        setState(() {
          _videoBytes = result.files.single.bytes;
          _videoName = result.files.single.name;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao selecionar vídeo: $e')));
    }
  }

  Future<void> _saveForm() async {
    if (!_formKey.currentState!.validate()) return;

    bool isVideoCat = _selectedCategory == 'bola_cheia' || _selectedCategory == 'bola_murcha';
    
    if (_selectedPlayerDoc == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione o jogador responsável pelo lance/prêmio.')));
      return;
    }

    if (isVideoCat && _videoBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione um arquivo de vídeo para fazer upload.')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final data = _selectedPlayerDoc!.data() as Map<String, dynamic>;
      String name = data['name'] ?? 'Nome';
      String teamName = data['team_name'] ?? '';
      String photoUrl = data['photo_url'] ?? '';
      String originalPlayerId = _selectedPlayerDoc!.id;

      String? videoDownloadUrl;
      String description = '';

      if (isVideoCat) {
        description = _descriptionController.text.trim();
        if (description.isEmpty) description = "Lance de $name";

        final String fileName = 'voting_videos/${DateTime.now().millisecondsSinceEpoch}_$_videoName';
        final ref = _storage.ref().child(fileName);
        final metadata = SettableMetadata(contentType: 'video/${_videoName.split('.').last}');
        
        var task = await ref.putData(_videoBytes!, metadata);
        videoDownloadUrl = await task.ref.getDownloadURL();
      }

      String statsDocId;

      if (isVideoCat) {
        statsDocId = '${_selectedCategory}_${originalPlayerId}_${DateTime.now().millisecondsSinceEpoch}';
      } else {
        // Revelação e Melhor Jogador são únicos por atleta
        statsDocId = '${_selectedCategory}_$originalPlayerId';
      }

      await _firestore.collection('voting_stats').doc(statsDocId).set({
        'category': _selectedCategory,
        'original_id': originalPlayerId, 
        'name': name,
        'team_name': teamName,
        'photo_url': photoUrl,
        'video_url': videoDownloadUrl, 
        'description': description, 
        'votes': FieldValue.increment(0), 
        'created_at': FieldValue.serverTimestamp(),
        'is_manual_entry': true, 
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Candidato cadastrado com sucesso!')));
        Navigator.of(context).pop();
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isVideoCategory = _selectedCategory == 'bola_cheia' || _selectedCategory == 'bola_murcha';

    return Scaffold(
      appBar: AppBar(title: const Text('Adicionar Candidato')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                decoration: const InputDecoration(labelText: 'Categoria', border: OutlineInputBorder()),
                items: _categories.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                onChanged: _isSaving ? null : (v) {
                  setState(() {
                    _selectedCategory = v!;
                    _videoBytes = null;
                    _descriptionController.clear();
                  });
                },
              ),
              const SizedBox(height: 20),

              const Text('Selecione o Atleta:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              StreamBuilder<QuerySnapshot>(
                stream: _firestore.collection('players')
                    .where('isActive', isEqualTo: true)
                    .where('is_staff', isEqualTo: false)
                    .orderBy('name')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final players = snapshot.data!.docs;
                  return DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _selectedPlayerDoc?.id,
                    hint: const Text("Toque para selecionar..."),
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                    items: players.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return DropdownMenuItem<String>(
                        value: doc.id, 
                        child: Text("${data['name']} (${data['team_name']})", overflow: TextOverflow.ellipsis)
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedPlayerDoc = players.firstWhere((d) => d.id == val);
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 20),

              if (isVideoCategory) ...[
                const Divider(),
                const Text('Dados do Vídeo:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Título do Lance', 
                    hintText: 'Ex: Golaço de Bicicleta', 
                    border: OutlineInputBorder()
                  ),
                  validator: (v) => (isVideoCategory && v!.isEmpty) ? 'Informe um título' : null,
                ),
                const SizedBox(height: 16),
                Container(
                  height: 150,
                  decoration: BoxDecoration(color: Colors.grey[200], border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
                  child: _videoBytes == null
                      ? Center(child: TextButton.icon(icon: const Icon(Icons.video_library), label: const Text('Carregar Vídeo'), onPressed: _pickVideo))
                      : Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.check_circle, color: Colors.green, size: 40), const SizedBox(height: 8), Text(_videoName, textAlign: TextAlign.center), TextButton(onPressed: _pickVideo, child: const Text('Trocar Vídeo'))]),
                ),
              ],

              const SizedBox(height: 30),
              ElevatedButton(
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white),
                onPressed: _isSaving ? null : _saveForm,
                child: _isSaving 
                  ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(color: Colors.white), SizedBox(width: 10), Text("Salvando...")]) 
                  : const Text('SALVAR CANDIDATO', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}