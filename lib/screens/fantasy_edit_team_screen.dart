import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';

import '../viewmodels/fantasy_home_viewmodel.dart';
import '../services/migration_service.dart';

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

class FantasyEditTeamScreen extends StatefulWidget {
  const FantasyEditTeamScreen({super.key});

  @override
  State<FantasyEditTeamScreen> createState() => _FantasyEditTeamScreenState();
}

class _FantasyEditTeamScreenState extends State<FantasyEditTeamScreen> {
  final _formKey = GlobalKey<FormState>();
  final MigrationService _migrationService = MigrationService();
  late TextEditingController _nameController;
  
  String? _selectedLogoUrl;
  XFile? _imageFile;
  bool _isLoading = false;

  // 🚨 DEFINA AQUI AS URLs DAS OPÇÕES PRÉ-DEFINIDAS NO NOVO STORAGE 🚨
  final List<String> presetLogos = [
    // Ex: https://firebasestorage.googleapis.com/v0/b/acefjf.firebasestorage.app/o/fantasy_presets%2Flogo_shield_1.png?alt=media
    'logo_shield_1', 
    'logo_shield_2',
    'logo_shield_3',
    'logo_shield_4',
    'logo_shield_5',
    'logo_shield_6',
  ];

  @override
  void initState() {
    super.initState();
    final team = Provider.of<FantasyHomeViewModel>(context, listen: false).team;
    _nameController = TextEditingController(text: team?.teamName ?? '');
    _selectedLogoUrl = team?.customLogoUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image != null) {
      setState(() {
        _imageFile = image;
        _selectedLogoUrl = null; // Limpa a seleção do carrossel
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final viewModel = Provider.of<FantasyHomeViewModel>(context, listen: false);
    
    // Converte os nomes curtos para URLs completas do novo bucket ACEFJF
    String? finalPresetUrl;
    if (_selectedLogoUrl != null && !(_selectedLogoUrl!.startsWith('http'))) {
        // Gera a URL completa usando o padrão ACEFJF
        finalPresetUrl = 'https://firebasestorage.googleapis.com/v0/b/acefjf.firebasestorage.app/o/fantasy_presets%2F$_selectedLogoUrl.png?alt=media';
    } else if (_selectedLogoUrl != null) {
        finalPresetUrl = _selectedLogoUrl; // Mantém se já for URL (pode ser storage antigo ou novo)
    }

    final success = await viewModel.updateTeamProfile(
      newName: _nameController.text.trim(),
      selectedPresetUrl: finalPresetUrl,
      imageFile: _imageFile,
    );

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Perfil atualizado!'), backgroundColor: Colors.green));
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(viewModel.errorMessage ?? 'Erro ao salvar'), backgroundColor: Colors.red));
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final team = Provider.of<FantasyHomeViewModel>(context).team;

    return Scaffold(
      appBar: AppBar(title: const Text("Editar Meu Time"), elevation: 0),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- PREVIEW DO ESCUDO ATUAL ---
                  Center(child: _buildShieldPreview(primaryColor, team)),
                  const SizedBox(height: 32),

                  // --- NOME DO TIME ---
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(labelText: "Nome do Time", prefixIcon: const Icon(Icons.sports_soccer), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Nome obrigatório';
                      if (value.length > 25) return 'Máximo 25 caracteres';
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // --- BOTÃO ENVIAR IMAGEM ---
                  TextButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.add_a_photo, size: 20),
                    label: const Text("Enviar imagem do meu celular", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.blueGrey,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  
                  if (_imageFile != null) 
                    Padding(padding: const EdgeInsets.only(top: 8.0), child: Center(child: Text("Imagem selecionada: ${_imageFile!.name}", style: const TextStyle(fontSize: 11, color: Colors.grey)))),

                  const Divider(height: 50),

                  // --- CARROSSEL DE OPÇÕES PRE-DEFINIDAS ---
                  const Text("Ou escolha um escudo pré-definido:", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54)),
                  const SizedBox(height: 16),
                  Container(
                    height: 90,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: presetLogos.length,
                      separatorBuilder: (_,__) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final String logoKey = presetLogos[index];
                        // Gera a URL completa usando o padrão ACEFJF para carregar o preset
                        final String presetImageUrl = 'https://firebasestorage.googleapis.com/v0/b/acefjf.firebasestorage.app/o/fantasy_presets%2F$logoKey.png?alt=media';
                        
                        final bool isSelected = (_selectedLogoUrl == logoKey && _imageFile == null);

                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedLogoUrl = logoKey;
                                  _imageFile = null; // Limpa upload se escolheu preset
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: isSelected ? primaryColor : Colors.grey.shade300, width: isSelected ? 3 : 1),
                                  boxShadow: isSelected ? [BoxShadow(color: primaryColor.withOpacity(0.2), blurRadius: 4)] : null,
                                ),
                                child: CachedNetworkImage(
                                  imageUrl: presetImageUrl, 
                                  height: 60, width: 60, fit: BoxFit.contain,
                                  placeholder: (_,__) => const CircularProgressIndicator(strokeWidth: 2),
                                  errorWidget: (_,__,___) => Icon(Icons.shield, color: Colors.grey.shade300, size: 40),
                                ),
                              ),
                            ),
                            if (isSelected) 
                              Positioned(top: 0, right: 0, child: Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(color: primaryColor, shape: BoxShape.circle), child: const Icon(Icons.check, color: Colors.white, size: 16))),
                          ],
                        );
                      },
                    ),
                  ),
                  
                  const SizedBox(height: 120), // Espaço para o botão
                ],
              ),
            ),
          ),
          
          // --- BOTÃO SALVAR FIXO NO RODAPÉ ---
          if (!_isLoading)
            Positioned(
              bottom: 24, left: 24, right: 24,
              child: ElevatedButton.icon(
                onPressed: _saveProfile,
                icon: const Icon(Icons.save),
                label: const Text("SALVAR ALTERAÇÕES", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor, foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 5,
                ),
              ),
            ),
          
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  Widget _buildShieldPreview(Color primaryColor, team) {
    if (_imageFile != null) {
      // Preview da imagem do celular (usando FileImage híbrido)
      final provider = kIsWeb ? NetworkImage(_imageFile!.path) : FileImage(File(_imageFile!.path)) as ImageProvider;
      return Container(
        height: 120, width: 120,
        decoration: BoxDecoration(color: Colors.grey.shade200, shape: BoxShape.circle, border: Border.all(color: primaryColor, width: 3), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))]),
        child: ClipOval(child: Image(image: provider, fit: BoxFit.cover)),
      );
    }
    
    // Preview da seleção do carrossel ou logo atual do time
    String? finalImageUrl;
    if (_selectedLogoUrl != null && !(_selectedLogoUrl!.startsWith('http'))) {
        // Se for um preset do carrossel (nome curto), gera a URL do bucket ACEFJF
        finalImageUrl = 'https://firebasestorage.googleapis.com/v0/b/acefjf.firebasestorage.app/o/fantasy_presets%2F$_selectedLogoUrl.png?alt=media';
    } else {
        finalImageUrl = _selectedLogoUrl; // Mantém a URL existente do time
    }

    return Container(
      height: 120, width: 120,
      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: primaryColor, width: 3), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))]),
      child: ClipOval(
        child: finalImageUrl != null
            ? CachedNetworkImage(
                imageUrl: finalImageUrl, fit: BoxFit.contain,
                placeholder: (_,__) => const CircularProgressIndicator(strokeWidth: 2),
                errorWidget: (_,__,___) => Icon(Icons.shield, size: 60, color: Colors.grey.shade400),
              )
            : Icon(Icons.shield, size: 60, color: Colors.grey.shade400),
      ),
    );
  }
}