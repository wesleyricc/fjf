// lib/screens/edit_player_screen.dart
import 'dart:typed_data'; // <-- NOVO
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart'; // <-- NOVO
import 'package:firebase_storage/firebase_storage.dart'; // <-- NOVO
import 'package:cached_network_image/cached_network_image.dart'; // <-- NOVO

class EditPlayerScreen extends StatefulWidget {
  final String teamId;
  final String teamName;
  final DocumentSnapshot? playerDoc; // Nulo se for 'Criar'

  const EditPlayerScreen({
    super.key, 
    required this.teamId,
    required this.teamName,
    this.playerDoc,
  });

  @override
  State<EditPlayerScreen> createState() => _EditPlayerScreenState();
}

class _EditPlayerScreenState extends State<EditPlayerScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // --- NOVO: Firebase Storage ---
  final FirebaseStorage _storage = FirebaseStorage.instanceFor(bucket: "fjfapp.firebasestorage.app");

  // Controladores
  late TextEditingController _nameController;
  late TextEditingController _numberController;
  
  // Posição
  bool _isGoalkeeper = false;
  final List<String> _positionOptions = ['Fixo', 'Ala', 'Pivô'];
  String? _selectedPosition;
  
  // Bio
  DateTime? _selectedDateOfBirth; 
  late TextEditingController _heightController;
  late TextEditingController _weightController;
  final List<String> _footOptions = ['Destro', 'Canhoto', 'Ambidestro'];
  String? _selectedPreferredFoot;

  bool _isActive = true;
  bool _isStaff = false;
  bool _isSaving = false; // Renomeado de _isUploadingOrSaving para clareza

  // --- NOVO: Estado da Imagem ---
  Uint8List? _pickedImageBytes;
  String _pickedImageName = '';
  String? _existingPhotoUrl;
  // --- FIM ---

  @override
  void initState() {
    super.initState();
    final data = widget.playerDoc?.data() as Map<String, dynamic>?;

    _nameController = TextEditingController(text: data?['name'] ?? '');
    _numberController = TextEditingController(text: data?['jersey_number']?.toString() ?? '');
    _isActive = data?['isActive'] ?? true;
    _isStaff = data?['is_staff'] ?? false;
    
    _isGoalkeeper = data?['is_goalkeeper'] ?? false;
    _selectedPosition = data?['position'];
    
    if (_isGoalkeeper) {
      _selectedPosition = null;
    } else if (data?['position'] == null) {
       _selectedPosition = 'Ala';
    }
    
    if (data?['date_of_birth'] != null && data?['date_of_birth'] is Timestamp) {
      _selectedDateOfBirth = (data!['date_of_birth'] as Timestamp).toDate();
    }
    
    _heightController = TextEditingController(text: data?['height_cm']?.toString() ?? '');
    _weightController = TextEditingController(text: data?['weight_kg']?.toString() ?? '');
    _selectedPreferredFoot = data?['preferred_foot'];
    if (_selectedPreferredFoot == null && !_isGoalkeeper && !_isStaff) {
      _selectedPreferredFoot = 'Destro';
    }

    // --- NOVO: Carrega foto existente ---
    _existingPhotoUrl = data?['photo_url'];
    // --- FIM ---
  }

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _pickDateOfBirth() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateOfBirth ?? DateTime(2000),
      firstDate: DateTime(1960),
      lastDate: DateTime.now(),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null && picked != _selectedDateOfBirth) {
      setState(() {
        _selectedDateOfBirth = picked;
      });
    }
  }

  // --- NOVA FUNÇÃO: _pickImage ---
  Future<void> _pickImage() async {
    if (_isSaving) return;
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result != null && result.files.single.bytes != null) {
        setState(() {
          _pickedImageBytes = result.files.single.bytes;
          _pickedImageName = result.files.single.name;
          _existingPhotoUrl = null; // Remove a foto antiga da pré-visualização
        });
      }
    } catch (e) {
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao selecionar imagem: $e')));
    }
  }
  // --- FIM DA NOVA FUNÇÃO ---

  // --- NOVA FUNÇÃO: _buildImagePreview ---
  Widget _buildImagePreview() {
    if (_pickedImageBytes != null) {
      // 1. Preview da Nova Imagem (em bytes)
      return CircleAvatar(
        radius: 50,
        backgroundImage: MemoryImage(_pickedImageBytes!),
      );
    }
    if (_existingPhotoUrl != null && _existingPhotoUrl!.isNotEmpty) {
      // 2. Preview da Imagem Antiga (da URL)
      return CircleAvatar(
        radius: 50,
        backgroundColor: Colors.grey[200],
        backgroundImage: CachedNetworkImageProvider(_existingPhotoUrl!),
        onBackgroundImageError: (e, s) {
          debugPrint('Erro ao carregar imagem: $e');
        },
      );
    }
    // 3. Placeholder
    return CircleAvatar(
      radius: 50,
      backgroundColor: Colors.grey[200],
      child: const Icon(Icons.person, size: 60, color: Colors.grey),
    );
  }
  // --- FIM DA NOVA FUNÇÃO ---


  Future<void> _savePlayer() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (!_isGoalkeeper && !_isStaff && _selectedPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecione a Posição (Fixo, Ala ou Pivô).')),
      );
      return;
    }
    
    setState(() { _isSaving = true; });

    String? finalPhotoUrl = _existingPhotoUrl;

    try {
      // --- ETAPA 1: FAZER UPLOAD DA IMAGEM (se houver) ---
      if (_pickedImageBytes != null) {
        debugPrint("Iniciando upload de foto do jogador...");
        final String fileName = '${DateTime.now().millisecondsSinceEpoch}_$_pickedImageName';
        // Salva na pasta do time para organizar
        final String storagePath = 'player_photos/${widget.teamId}/$fileName'; 
        final ref = _storage.ref().child(storagePath);
        
        final metadata = SettableMetadata(contentType: 'image/${fileName.split('.').last}');
        UploadTask uploadTask = ref.putData(_pickedImageBytes!, metadata);
        TaskSnapshot snapshot = await uploadTask;
        finalPhotoUrl = await snapshot.ref.getDownloadURL();
        debugPrint("Upload de foto concluído: $finalPhotoUrl");
        
        // Se o upload deu certo E existia uma foto antiga, delete a antiga
        if (_existingPhotoUrl != null && _existingPhotoUrl!.isNotEmpty) {
           try {
             await _storage.refFromURL(_existingPhotoUrl!).delete();
           } catch (e) {
              debugPrint("Aviso: Falha ao deletar foto antiga: $e (Pode já ter sido removida)");
           }
        }
      }
      // --- FIM DA ETAPA 1 ---

      // --- ETAPA 2: PREPARAR DADOS DO FIRESTORE ---
      final String name = _nameController.text.trim();
      final int? number = int.tryParse(_numberController.text);
      
      final int? height = int.tryParse(_heightController.text);
      final int? weight = int.tryParse(_weightController.text);
      
      final Timestamp? dobTimestamp = _selectedDateOfBirth != null
          ? Timestamp.fromDate(_selectedDateOfBirth!)
          : null;

      Map<String, dynamic> playerData = {
        'name': name,
        'jersey_number': number,
        'team_id': widget.teamId,
        'team_name': widget.teamName,
        'isActive': _isActive,
        'is_staff': _isStaff,
        'is_goalkeeper': _isGoalkeeper,
        'position': _isGoalkeeper || _isStaff ? null : _selectedPosition,
        
        'date_of_birth': dobTimestamp,
        'height_cm': height,
        'weight_kg': weight,
        'preferred_foot': _isGoalkeeper || _isStaff ? null : _selectedPreferredFoot,

        'photo_url': finalPhotoUrl, // <-- NOVO CAMPO SALVO

        // Estatísticas
        'goals': widget.playerDoc != null ? (widget.playerDoc!['goals'] ?? 0) : 0,
        'assists': widget.playerDoc != null ? (widget.playerDoc!['assists'] ?? 0) : 0,
        'yellow_cards': widget.playerDoc != null ? (widget.playerDoc!['yellow_cards'] ?? 0) : 0,
        'red_cards': widget.playerDoc != null ? (widget.playerDoc!['red_cards'] ?? 0) : 0,
        'total_yellow_cards': widget.playerDoc != null ? (widget.playerDoc!['total_yellow_cards'] ?? 0) : 0,
        'total_red_cards': widget.playerDoc != null ? (widget.playerDoc!['total_red_cards'] ?? 0) : 0,
        'goals_conceded': widget.playerDoc != null ? (widget.playerDoc!['goals_conceded'] ?? 0) : 0,
        'man_of_the_match_awards': widget.playerDoc != null ? (widget.playerDoc!['man_of_the_match_awards'] ?? 0) : 0,
        'is_suspended': widget.playerDoc != null ? (widget.playerDoc!['is_suspended'] ?? false) : false,
      };

      // --- ETAPA 3: SALVAR NO FIRESTORE ---
      if (widget.playerDoc == null) {
        await _firestore.collection('players').add(playerData);
      } else {
        await widget.playerDoc!.reference.update(playerData);
      }
      
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Jogador ${widget.playerDoc == null ? 'salvo' : 'atualizado'} com sucesso!')),
        );
      }
    } catch (e) {
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Erro ao salvar jogador: $e')),
         );
       }
    } finally {
      if (mounted) setState(() { _isSaving = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playerDoc == null ? 'Novo Jogador' : 'Editar Jogador'),
        actions: [
          IconButton(
            icon: _isSaving ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2) : const Icon(Icons.save),
            onPressed: _isSaving ? null : _savePlayer,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Text('Time: ${widget.teamName}', style: Theme.of(context).textTheme.titleMedium),
            const Divider(height: 24),
            
            // --- NOVO: SEÇÃO DE FOTO ---
            Center(child: _buildImagePreview()),
            const SizedBox(height: 8),
            Center(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.photo_camera, size: 18),
                label: Text(_existingPhotoUrl != null ? 'Trocar Foto' : 'Selecionar Foto'),
                onPressed: _isSaving ? null : _pickImage,
              ),
            ),
            const SizedBox(height: 24),
            // --- FIM DA SEÇÃO DE FOTO ---

            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nome Completo', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null,
              enabled: !_isSaving,
            ),
            const SizedBox(height: 16),

            SwitchListTile(
              title: const Text('Faz parte da Comissão Técnica?'),
              value: _isStaff,
              onChanged: _isSaving ? null : (value) => setState(() => _isStaff = value),
            ),
            
            if (!_isStaff) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _numberController,
                decoration: const InputDecoration(labelText: 'Número da Camisa', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                enabled: !_isSaving,
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('É Goleiro?'),
                        value: _isGoalkeeper,
                        onChanged: _isSaving ? null : (value) {
                          setState(() {
                            _isGoalkeeper = value;
                            if (value) _selectedPosition = null; 
                            else _selectedPosition = 'Ala';
                          });
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: DropdownButtonFormField<String>(
                          value: _selectedPosition,
                          decoration: InputDecoration(
                            labelText: 'Posição de Linha',
                            border: const OutlineInputBorder(),
                            filled: _isGoalkeeper, 
                            fillColor: Colors.grey[200],
                          ),
                          onChanged: _isGoalkeeper || _isSaving ? null : (String? newValue) {
                            setState(() {
                              _selectedPosition = newValue;
                            });
                          },
                          items: _positionOptions.map<DropdownMenuItem<String>>((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _isSaving ? null : _pickDateOfBirth,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Data de Nascimento',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          _selectedDateOfBirth == null
                              ? 'Selecione a data'
                              : DateFormat('dd/MM/yyyy').format(_selectedDateOfBirth!),
                          style: TextStyle(
                            color: _selectedDateOfBirth == null ? Colors.grey[600] : (Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedPreferredFoot,
                      decoration: const InputDecoration(
                        labelText: 'Pé Preferido',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: _isSaving ? null : (String? newValue) {
                        setState(() {
                          _selectedPreferredFoot = newValue;
                        });
                      },
                      items: _footOptions.map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _heightController,
                      decoration: const InputDecoration(labelText: 'Altura (cm)', border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      enabled: !_isSaving,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _weightController,
                      decoration: const InputDecoration(labelText: 'Peso (kg)', border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      enabled: !_isSaving,
                    ),
                  ),
                ],
              ),
            ],
            
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Membro Ativo?'),
              subtitle: const Text('Desmarque para dispensar o membro.'),
              value: _isActive,
              onChanged: _isSaving ? null : (value) => setState(() => _isActive = value),
            ),
          ],
        ),
      ),
    );
  }
}