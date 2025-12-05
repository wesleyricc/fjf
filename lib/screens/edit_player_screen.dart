import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart'; 
import 'package:flutter/services.dart'; 
import 'package:provider/provider.dart';

// Services & Models
import '../services/auth_service.dart';
import '../services/championship_service.dart';
import '../services/firestore_service.dart';
import '../models/player_model.dart'; // <-- Model

class EditPlayerScreen extends StatefulWidget {
  final String teamId;
  final String teamName;
  final Player? player; // <-- Recebe Model

  // Mantemos compatibilidade com chamadas antigas se necessário (mas playerDoc foi removido)
  // Se player for null, é criação.

  const EditPlayerScreen({
    super.key,
    required this.teamId,
    required this.teamName,
    this.player,
  });

  @override
  State<EditPlayerScreen> createState() => _EditPlayerScreenState();
}

class _EditPlayerScreenState extends State<EditPlayerScreen> {
  final FirebaseStorage _storage = FirebaseStorage.instanceFor(bucket: "fjfapp.firebasestorage.app");
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _jerseyNumberController;
  late TextEditingController _dateOfBirthController;
  late TextEditingController _heightController;
  late TextEditingController _weightController;
  late TextEditingController _instagramController;
  late TextEditingController _phoneController;

  bool _isStaff = false;
  bool _isGoalkeeper = false;
  String? _selectedPosition; 
  String? _selectedFoot;
  String? _selectedStaffRole;

  final List<String> _positionOptions = ['Fixo', 'Ala', 'Pivô'];
  final List<String> _footOptions = ['Destro', 'Canhoto', 'Ambidestro'];
  final List<String> _staffRoleOptions = ['Técnico', 'Auxiliar Técnico', 'Atendente', 'Analista', 'Massagista', 'Preparador Físico'];

  String? _photoUrl;
  File? _imageFile;
  Uint8List? _webImageBytes;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.player?.name ?? '');
    _jerseyNumberController = TextEditingController(text: widget.player?.jerseyNumber?.toString() ?? '');
    
    _dateOfBirthController = TextEditingController();
    if (widget.player?.dateOfBirth != null) {
      _dateOfBirthController.text = DateFormat('dd/MM/yyyy').format(widget.player!.dateOfBirth!);
    }

    _heightController = TextEditingController(text: widget.player?.heightCm?.toString() ?? '');
    _weightController = TextEditingController(text: widget.player?.weightKg?.toString() ?? '');
    // Campos opcionais que não estavam no model, mantemos vazios ou adicionamos ao model futuramente
    _instagramController = TextEditingController();
    _phoneController = TextEditingController();

    if (widget.player != null) {
      _isStaff = widget.player!.isStaff;
      _isGoalkeeper = widget.player!.isGoalkeeper;
      _photoUrl = widget.player!.photoUrl;
      
      if (_isStaff) {
        _selectedStaffRole = widget.player!.staffRole;
      } else {
        if (_positionOptions.contains(widget.player!.position)) {
          _selectedPosition = widget.player!.position;
        }
      }
      if (_footOptions.contains(widget.player!.preferredFoot)) {
        _selectedFoot = widget.player!.preferredFoot;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _jerseyNumberController.dispose();
    _dateOfBirthController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _instagramController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // --- LÓGICA DE IMAGEM ---
  Future<void> _pickImage() async {
    if (kIsWeb) {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.single.bytes != null) {
        setState(() {
          _webImageBytes = result.files.single.bytes;
          _photoUrl = null; // Invalida URL antiga para mostrar a nova local
        });
      }
    } else {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
          _photoUrl = null;
        });
      }
    }
  }

  Future<String?> _uploadImage() async {
    if (_imageFile == null && _webImageBytes == null) return _photoUrl;
    
    // Nome do arquivo: ID do jogador (se existir) ou Timestamp
    final String fileId = widget.player?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    String fileName = 'players/$fileId.jpg';
    
    try {
      UploadTask uploadTask;
      final ref = _storage.ref().child(fileName);
      final metadata = SettableMetadata(contentType: 'image/jpeg');

      if (kIsWeb && _webImageBytes != null) {
        uploadTask = ref.putData(_webImageBytes!, metadata);
      } else if (_imageFile != null) {
        uploadTask = ref.putFile(_imageFile!, metadata);
      } else {
        return null;
      }

      TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint("Erro upload: $e");
      return null;
    }
  }

  // --- SALVAR ---
  Future<void> _savePlayer() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isStaff && _selectedStaffRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione a função.')));
      return;
    }

    setState(() => _isUploading = true);

    try {
      String? uploadedPhotoUrl = await _uploadImage();

      final int? jerseyNumber = int.tryParse(_jerseyNumberController.text);
      final int? heightCm = int.tryParse(_heightController.text);
      final int? weightKg = int.tryParse(_weightController.text);

      Timestamp? dobTimestamp;
      if (_dateOfBirthController.text.isNotEmpty) {
        try {
          final date = DateFormat('dd/MM/yyyy').parse(_dateOfBirthController.text);
          dobTimestamp = Timestamp.fromDate(date);
        } catch (_) {}
      }

      final Map<String, dynamic> playerData = {
        'name': _nameController.text.trim(),
        'jersey_number': jerseyNumber,
        'position': _isStaff ? null : (_isGoalkeeper ? 'Goleiro' : _selectedPosition),
        'date_of_birth': dobTimestamp,
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'preferred_foot': _selectedFoot,
        'instagram': _instagramController.text.trim(),
        'phone': _phoneController.text.trim(),
        'is_staff': _isStaff,
        'staff_role': _isStaff ? _selectedStaffRole : null,
        'is_goalkeeper': _isGoalkeeper,
        'photo_url': uploadedPhotoUrl,
        'team_id': widget.teamId,
        'team_name': widget.teamName,
      };

      final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
      final FirestoreService service = FirestoreService();

      String result;
      if (widget.player == null) {
        result = await service.createPlayer(seasonId: seasonId, data: playerData);
      } else {
        result = await service.updatePlayer(seasonId: seasonId, playerId: widget.player!.id, data: playerData);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
        if (result.startsWith("Sucesso")) Navigator.pop(context);
      }

    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if(mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _selectDate() async {
    DateTime initial = DateTime(2000);
    if (_dateOfBirthController.text.isNotEmpty) {
      try { initial = DateFormat('dd/MM/yyyy').parse(_dateOfBirthController.text); } catch (_) {}
    }
    final DateTime? picked = await showDatePicker(
      context: context, initialDate: initial, firstDate: DateTime(1950), lastDate: DateTime.now(), locale: const Locale('pt', 'BR')
    );
    if (picked != null) setState(() => _dateOfBirthController.text = DateFormat('dd/MM/yyyy').format(picked));
  }

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = Provider.of<AuthService>(context).isAuthenticated;
    if (!isAuthenticated) return const Scaffold(body: Center(child: Text("Acesso Negado")));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.player == null ? 'Novo Jogador' : 'Editar ${_nameController.text}'),
        actions: [
          IconButton(
            icon: _isUploading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save),
            onPressed: _isUploading ? null : _savePlayer,
          )
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // Foto
            Center(
              child: GestureDetector(
                onTap: _pickImage,
                child: CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage: _imageFile != null
                      ? FileImage(_imageFile!) as ImageProvider
                      : _webImageBytes != null
                          ? MemoryImage(_webImageBytes!)
                          : (_photoUrl != null && _photoUrl!.isNotEmpty)
                              ? CachedNetworkImageProvider(_photoUrl!) as ImageProvider
                              : null,
                  child: (_imageFile == null && _webImageBytes == null && (_photoUrl == null || _photoUrl!.isEmpty))
                      ? Icon(Icons.camera_alt, size: 40, color: Colors.grey.shade400)
                      : null,
                ),
              ),
            ),
            if (_photoUrl != null || _imageFile != null || _webImageBytes != null)
              Center(
                child: TextButton(
                  onPressed: () => setState(() { _photoUrl = null; _imageFile = null; _webImageBytes = null; }),
                  child: const Text('Remover Foto', style: TextStyle(color: Colors.red)),
                ),
              ),
            const SizedBox(height: 20),

            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nome Completo', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _jerseyNumberController,
                    decoration: const InputDecoration(labelText: 'Nº Camisa', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _dateOfBirthController,
                    readOnly: true,
                    onTap: _selectDate,
                    decoration: const InputDecoration(labelText: 'Nascimento', border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tipo de Membro
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Membro da Comissão Técnica?'),
                    subtitle: const Text('Técnico, Auxiliar, etc.'),
                    value: _isStaff,
                    onChanged: (val) => setState(() { _isStaff = val; if (_isStaff) { _isGoalkeeper = false; _selectedPosition = null; } else { _selectedStaffRole = null; } }),
                  ),
                  if (!_isStaff)
                    SwitchListTile(
                      title: const Text('É Goleiro?'),
                      value: _isGoalkeeper,
                      onChanged: (val) => setState(() { _isGoalkeeper = val; if (_isGoalkeeper) _selectedPosition = null; }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (_isStaff)
              DropdownButtonFormField<String>(
                value: _selectedStaffRole,
                decoration: const InputDecoration(labelText: 'Função', border: OutlineInputBorder()),
                items: _staffRoleOptions.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                onChanged: (v) => setState(() => _selectedStaffRole = v),
              ),

            if (!_isStaff && !_isGoalkeeper)
              DropdownButtonFormField<String>(
                value: _selectedPosition,
                decoration: const InputDecoration(labelText: 'Posição', border: OutlineInputBorder()),
                items: _positionOptions.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                onChanged: (v) => setState(() => _selectedPosition = v),
              ),

            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: TextFormField(controller: _heightController, decoration: const InputDecoration(labelText: 'Altura (cm)', border: OutlineInputBorder()), keyboardType: TextInputType.number)),
                const SizedBox(width: 16),
                Expanded(child: TextFormField(controller: _weightController, decoration: const InputDecoration(labelText: 'Peso (kg)', border: OutlineInputBorder()), keyboardType: TextInputType.number)),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedFoot,
              decoration: const InputDecoration(labelText: 'Pé Preferido', border: OutlineInputBorder()),
              items: _footOptions.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
              onChanged: (v) => setState(() => _selectedFoot = v),
            ),
          ],
        ),
      ),
    );
  }
}