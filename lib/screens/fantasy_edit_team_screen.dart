import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; 
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb, Uint8List;

import '../services/fantasy_service.dart';
import '../services/fantasy_auth_service.dart';

class FantasyEditTeamScreen extends StatefulWidget {
  const FantasyEditTeamScreen({super.key});

  @override
  State<FantasyEditTeamScreen> createState() => _FantasyEditTeamScreenState();
}

class _FantasyEditTeamScreenState extends State<FantasyEditTeamScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _teamNameController = TextEditingController();
  final TextEditingController _ownerNameController = TextEditingController();
  
  String _selectedShield = '1'; 
  bool _isLoading = true;
  
  // Upload de Imagem
  String? _customLogoUrl;
  File? _imageFile;
  Uint8List? _webImageBytes;
  bool _isUploadingImage = false;

  // Lista expandida de escudos
  final List<Map<String, dynamic>> _availableShields = [
    // Clássicos
    {'id': '1', 'color': Colors.blue, 'icon': Icons.shield},
    {'id': '2', 'color': Colors.red, 'icon': Icons.shield},
    {'id': '3', 'color': Colors.green, 'icon': Icons.shield},
    {'id': '4', 'color': Colors.orange, 'icon': Icons.shield},
    {'id': '5', 'color': Colors.purple, 'icon': Icons.shield},
    // Esportivos (Futebol)
    {'id': '6', 'color': Colors.black, 'icon': Icons.sports_soccer}, // Bola
    {'id': '7', 'color': Colors.teal, 'icon': FontAwesomeIcons.shieldHalved}, // Escudo Dividido
    {'id': '8', 'color': Colors.amber, 'icon': FontAwesomeIcons.shieldCat}, // Escudo Estilo Brasão
    {'id': '9', 'color': Colors.indigo, 'icon': FontAwesomeIcons.futbol}, // Bola Futebol
    {'id': '10', 'color': Colors.deepOrange, 'icon': FontAwesomeIcons.userShield}, // Escudo com Jogador
    {'id': '11', 'color': Colors.blueGrey, 'icon': FontAwesomeIcons.shirt}, // Camisa
    {'id': '12', 'color': Colors.brown, 'icon': FontAwesomeIcons.trophy}, // Troféu
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCurrentData();
    });
  }

  @override
  void dispose() {
    _teamNameController.dispose();
    _ownerNameController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentData() async {
    final authService = Provider.of<FantasyAuthService>(context, listen: false);
    final fantasyService = Provider.of<FantasyService>(context, listen: false);

    if (authService.user != null) {
      final team = await fantasyService.streamMyTeam(authService.user!.uid).first;
      
      if (team != null && mounted) {
        setState(() {
          _teamNameController.text = team.teamName;
          _ownerNameController.text = team.ownerName;
          _selectedShield = team.shieldType;
          _customLogoUrl = team.customLogoUrl; // Carrega logo customizada
          _isLoading = false;
        });
        return;
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);

      if (image != null) {
        if (kIsWeb) {
          final bytes = await image.readAsBytes();
          setState(() {
            _webImageBytes = bytes;
            _imageFile = null;
            _customLogoUrl = null; // Limpa URL antiga para mostrar preview
          });
        } else {
          setState(() {
            _imageFile = File(image.path);
            _webImageBytes = null;
            _customLogoUrl = null;
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao selecionar imagem: $e')));
    }
  }

  Future<String?> _uploadImage(String userId) async {
    if (_imageFile == null && _webImageBytes == null) return _customLogoUrl;

    try {
      final String fileName = 'fantasy_logos/$userId.jpg';
      final Reference ref = FirebaseStorage.instance.ref().child(fileName);
      
      // CORREÇÃO AQUI: Tipo correto é SettableMetadata
      final SettableMetadata metadata = SettableMetadata(contentType: 'image/jpeg');
      
      UploadTask uploadTask;
      if (kIsWeb && _webImageBytes != null) {
        uploadTask = ref.putData(_webImageBytes!, metadata);
      } else if (_imageFile != null) {
        uploadTask = ref.putFile(_imageFile!, metadata);
      } else {
        return null;
      }

      final TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint("Erro no upload: $e");
      return null;
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final authService = Provider.of<FantasyAuthService>(context, listen: false);
    final fantasyService = Provider.of<FantasyService>(context, listen: false);
    final String userId = authService.user!.uid;

    // 1. Upload da Logo (se houver)
    String? finalLogoUrl = _customLogoUrl;
    if (_imageFile != null || _webImageBytes != null) {
      setState(() => _isUploadingImage = true);
      finalLogoUrl = await _uploadImage(userId);
      setState(() => _isUploadingImage = false);
    }

    // 2. Salva no Firestore
    final result = await fantasyService.updateTeamProfile(
      userId: userId,
      teamName: _teamNameController.text.trim(),
      ownerName: _ownerNameController.text.trim(),
      shieldType: _selectedShield,
      customLogoUrl: finalLogoUrl, // Salva a URL
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (result == "Sucesso") {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Perfil atualizado!"), backgroundColor: Colors.green));
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Editar Equipe"),
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _isLoading ? null : _saveProfile)
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // --- ÁREA DE LOGO CUSTOMIZADA ---
                Center(
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.grey[200],
                      backgroundImage: _getPreviewImage(),
                      child: (_imageFile == null && _webImageBytes == null && _customLogoUrl == null)
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.camera_alt, color: Colors.grey),
                                SizedBox(height: 4),
                                Text("Logo", style: TextStyle(fontSize: 10, color: Colors.grey))
                              ],
                            )
                          : null,
                    ),
                  ),
                ),
                if (_isUploadingImage) const Center(child: LinearProgressIndicator()),
                
                TextButton(
                  onPressed: () => setState(() {
                    _customLogoUrl = null; 
                    _imageFile = null; 
                    _webImageBytes = null;
                  }),
                  child: const Text("Remover Logo Personalizada", style: TextStyle(color: Colors.red)),
                ),

                const SizedBox(height: 20),
                const Center(child: Text("OU escolha um escudo padrão:", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
                const SizedBox(height: 10),

                // --- GALERIA DE ESCUDOS ---
                SizedBox(
                  height: 70,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _availableShields.length,
                    itemBuilder: (ctx, i) {
                      final shield = _availableShields[i];
                      final isSelected = shield['id'] == _selectedShield && _customLogoUrl == null && _imageFile == null && _webImageBytes == null;
                      
                      return GestureDetector(
                        onTap: () => setState(() {
                          _selectedShield = shield['id'];
                          // Se selecionar um padrão, limpamos o customizado (visual apenas, o save trata)
                          _customLogoUrl = null;
                          _imageFile = null;
                          _webImageBytes = null;
                        }),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: isSelected ? Border.all(color: Colors.green, width: 3) : null,
                          ),
                          child: CircleAvatar(
                            backgroundColor: shield['color'],
                            child: Icon(shield['icon'], color: Colors.white),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 30),

                TextFormField(
                  controller: _teamNameController,
                  decoration: const InputDecoration(labelText: "Nome do Time", border: OutlineInputBorder(), prefixIcon: Icon(Icons.flag)),
                  validator: (v) => v!.isEmpty ? "Informe o nome do time" : null,
                ),
                
                const SizedBox(height: 20),
                
                TextFormField(
                  controller: _ownerNameController,
                  decoration: const InputDecoration(labelText: "Nome do Técnico (Você)", border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
                  validator: (v) => v!.isEmpty ? "Informe seu nome" : null,
                ),

                const SizedBox(height: 30),
                
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _saveProfile,
                    child: const Text("SALVAR ALTERAÇÕES", style: TextStyle(color: Colors.white)),
                  ),
                )
              ],
            ),
          ),
    );
  }

  ImageProvider? _getPreviewImage() {
    if (_webImageBytes != null) return MemoryImage(_webImageBytes!);
    if (_imageFile != null) return FileImage(_imageFile!);
    if (_customLogoUrl != null && _customLogoUrl!.isNotEmpty) return CachedNetworkImageProvider(_customLogoUrl!);
    return null;
  }
}