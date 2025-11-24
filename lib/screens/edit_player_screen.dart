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
import 'package:provider/provider.dart'; // <-- Importante
import '../services/auth_service.dart'; // <-- Importante
import '../services/championship_service.dart';
import '../services/firestore_service.dart';

class EditPlayerScreen extends StatefulWidget {
  final String teamId;
  final String teamName;
  final DocumentSnapshot? playerDoc;

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
  final FirebaseStorage _storage = FirebaseStorage.instance;
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
  final List<String> _positionOptions = ['Fixo', 'Ala', 'Pivô'];
  final List<String> _footOptions = ['Destro', 'Canhoto', 'Ambidestro'];

  String? _photoUrl;
  File? _imageFile;
  Uint8List? _webImageBytes;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _jerseyNumberController = TextEditingController();
    _dateOfBirthController = TextEditingController();
    _heightController = TextEditingController();
    _weightController = TextEditingController();
    _instagramController = TextEditingController();
    _phoneController = TextEditingController();

    if (widget.playerDoc != null) {
      final data = widget.playerDoc!.data() as Map<String, dynamic>;
      _nameController.text = data['name'] ?? '';
      _jerseyNumberController.text = (data['jersey_number'] ?? '').toString();
      
      if (data['date_of_birth'] != null) {
        final date = (data['date_of_birth'] as Timestamp).toDate();
        _dateOfBirthController.text = DateFormat('dd/MM/yyyy').format(date);
      }

      _heightController.text = (data['height_cm'] ?? '').toString();
      _weightController.text = (data['weight_kg'] ?? '').toString();
      _instagramController.text = data['instagram'] ?? '';
      _phoneController.text = data['phone'] ?? '';
      _isStaff = data['is_staff'] ?? false;
      _isGoalkeeper = data['is_goalkeeper'] ?? false;
      _photoUrl = data['photo_url'];

      String? pos = data['position'];
      if (_positionOptions.contains(pos)) _selectedPosition = pos;
      
      String? foot = data['preferred_foot'];
      if (_footOptions.contains(foot)) _selectedFoot = foot;
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

  Future<void> _selectDate() async {
    DateTime initialDate = DateTime.now();
    if (_dateOfBirthController.text.isNotEmpty) {
      try { initialDate = DateFormat('dd/MM/yyyy').parse(_dateOfBirthController.text); } catch (_) {}
    }

    final DateTime? picked = await showDatePicker(
      context: context, initialDate: initialDate, firstDate: DateTime(1950), lastDate: DateTime.now(), locale: const Locale('pt', 'BR'),
    );

    if (picked != null) setState(() => _dateOfBirthController.text = DateFormat('dd/MM/yyyy').format(picked));
  }

  Future<void> _pickImage() async {
    if (kIsWeb) {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.single.bytes != null) {
        setState(() {
          _webImageBytes = result.files.single.bytes;
          _photoUrl = null;
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

  void _removePhoto() {
    setState(() { _photoUrl = null; _imageFile = null; _webImageBytes = null; });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Foto removida. Salve para aplicar a mudança.')));
  }

  Future<String?> _uploadImage() async {
    if (_imageFile == null && _webImageBytes == null) return _photoUrl;
    
    String fileName = 'players/${widget.playerDoc?.id ?? DateTime.now().millisecondsSinceEpoch}.jpg';
    UploadTask uploadTask;

    if (kIsWeb && _webImageBytes != null) {
      uploadTask = _storage.ref().child(fileName).putData(_webImageBytes!);
    } else if (_imageFile != null) {
      uploadTask = _storage.ref().child(fileName).putFile(_imageFile!);
    } else {
      return null;
    }

    TaskSnapshot snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }

  Future<void> _savePlayer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {}); // Loading

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
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data inválida. Use dd/mm/aaaa')));
          return;
        }
      }

      final Map<String, dynamic> playerData = {
        'name': _nameController.text.trim(),
        'jersey_number': jerseyNumber,
        'position': _isGoalkeeper ? 'Goleiro' : _selectedPosition,
        'date_of_birth': dobTimestamp,
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'preferred_foot': _selectedFoot,
        'instagram': _instagramController.text.trim(),
        'phone': _phoneController.text.trim(),
        'is_staff': _isStaff,
        'is_goalkeeper': _isGoalkeeper,
        'photo_url': uploadedPhotoUrl,
        'team_id': widget.teamId,
        'team_name': widget.teamName,
      };

      final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
      final FirestoreService service = FirestoreService();

      String result;
      if (widget.playerDoc == null) {
        result = await service.createPlayer(seasonId: seasonId, data: playerData);
      } else {
        result = await service.updatePlayer(seasonId: seasonId, playerId: widget.playerDoc!.id, data: playerData);
      }

      if (!mounted) return;
      
      if (result.startsWith("Sucesso")) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result), backgroundColor: Colors.red));
      }

    } catch (e) {
      debugPrint('Erro: $e');
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- CORREÇÃO: Usar Provider para verificar autenticação ---
    final isAuthenticated = Provider.of<AuthService>(context).isAuthenticated;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playerDoc == null ? 'Novo Jogador' : 'Editar ${_nameController.text}'),
      ),
      body: isAuthenticated // <-- Verificação correta
          ? Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    GestureDetector(
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
                            ? Icon(Icons.camera_alt, size: 50, color: Colors.grey.shade400)
                            : null,
                      ),
                    ),
                    if (_photoUrl != null || _imageFile != null || _webImageBytes != null)
                      TextButton(
                        onPressed: _removePhoto,
                        child: const Text('Remover Foto', style: TextStyle(color: Colors.red)),
                      ),
                    const SizedBox(height: 16),

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
                            decoration: InputDecoration(
                              labelText: 'Nascimento',
                              hintText: 'dd/mm/aaaa',
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(icon: const Icon(Icons.calendar_month), onPressed: _selectDate),
                            ),
                            keyboardType: TextInputType.datetime,
                            validator: (value) {
                              if (value != null && value.isNotEmpty) {
                                try { DateFormat('dd/MM/yyyy').parseStrict(value); } catch (e) { return 'Data inválida'; }
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(
                          child: SwitchListTile(
                            title: const Text('Comissão?'),
                            value: _isStaff,
                            onChanged: (bool value) {
                              setState(() {
                                _isStaff = value;
                                if (_isStaff) { _isGoalkeeper = false; _selectedPosition = null; }
                              });
                            },
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        if (!_isStaff)
                          Expanded(
                            child: SwitchListTile(
                              title: const Text('Goleiro?'),
                              value: _isGoalkeeper,
                              onChanged: (bool value) {
                                setState(() {
                                  _isGoalkeeper = value;
                                  if (_isGoalkeeper) _selectedPosition = null;
                                });
                              },
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                      ],
                    ),

                    if (!_isStaff && !_isGoalkeeper)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: DropdownButtonFormField<String>(
                          value: _selectedPosition,
                          decoration: const InputDecoration(labelText: 'Posição', border: OutlineInputBorder()),
                          items: _positionOptions.map((String pos) => DropdownMenuItem<String>(value: pos, child: Text(pos))).toList(),
                          onChanged: (newValue) => setState(() => _selectedPosition = newValue),
                          validator: (val) => val == null ? 'Selecione a posição' : null,
                        ),
                      ),
                    
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _heightController,
                            decoration: const InputDecoration(labelText: 'Altura (cm)', border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _weightController,
                            decoration: const InputDecoration(labelText: 'Peso (kg)', border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    DropdownButtonFormField<String>(
                      value: _selectedFoot,
                      decoration: const InputDecoration(labelText: 'Pé Preferido', border: OutlineInputBorder()),
                      items: _footOptions.map((String foot) => DropdownMenuItem<String>(value: foot, child: Text(foot))).toList(),
                      onChanged: (newValue) => setState(() => _selectedFoot = newValue),
                    ),
                    
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _instagramController,
                      decoration: const InputDecoration(labelText: 'Instagram (opcional)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(labelText: 'Telefone (opcional)', border: OutlineInputBorder()),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 32),
                    
                    ElevatedButton(
                      onPressed: _savePlayer,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Salvar Jogador', style: TextStyle(fontSize: 18)),
                    ),
                  ],
                ),
              ),
            )
          : const Center(child: Text('Acesso restrito. Faça login como Admin.')),
    );
  }
}