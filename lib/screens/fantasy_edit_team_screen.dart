import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Para o kIsWeb
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../viewmodels/fantasy_home_viewmodel.dart';
import '../widgets/team_logo_widget.dart'; // 🚨 Importando nosso novo widget
import '../services/analytics_service.dart'; // 🚨 RASTREAMENTO

class FantasyEditTeamScreen extends StatefulWidget {
  const FantasyEditTeamScreen({super.key});

  @override
  State<FantasyEditTeamScreen> createState() => _FantasyEditTeamScreenState();
}

class _FantasyEditTeamScreenState extends State<FantasyEditTeamScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  
  String? _selectedPresetName; 
  XFile? _imageFile;
  bool _isLoading = false;

  // Os códigos dos escudos gerados no TeamLogoWidget
  final List<String> presetLogos = [
    'preset_1', 'preset_2', 'preset_3', 
    'preset_4', 'preset_5', 'preset_6'
  ];

  @override
  void initState() {
    super.initState();
    // 🚨 Analytics: Rastreia a intenção de personalizar o time
    AnalyticsService.logCustomScreenView('Fantasy_Edit_Team_Screen');

    final team = Provider.of<FantasyHomeViewModel>(context, listen: false).team;
    _nameController = TextEditingController(text: team?.teamName ?? '');
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final viewModel = Provider.of<FantasyHomeViewModel>(context, listen: false);
    
    final success = await viewModel.updateTeamProfile(
      newName: _nameController.text.trim(),
      selectedPresetUrl: _selectedPresetName, // O ViewModel vai salvar 'preset_X' no Firebase
      imageFile: _imageFile,
    );

    if (mounted) {
      if (success) {
        // 🚨 Analytics: Sucesso ao editar perfil (maior retenção)
        AnalyticsService.logCustomScreenView('Fantasy_Edit_Team_Success');

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Perfil atualizado!'), backgroundColor: Colors.green));
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(viewModel.errorMessage ?? 'Erro'), backgroundColor: Colors.red));
      }
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final team = Provider.of<FantasyHomeViewModel>(context).team;

    return Scaffold(
      appBar: AppBar(title: const Text("Editar Meu Time")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // --- PREVIEW ---
              _buildShieldPreview(team),
              const SizedBox(height: 24),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: "Nome do Time", border: OutlineInputBorder()),
                validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null,
              ),
              const SizedBox(height: 32),

              // --- SELETOR DE PRESETS ---
              const Align(
                alignment: Alignment.centerLeft,
                child: Text("Escolha um escudo oficial:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: presetLogos.length,
                  separatorBuilder: (_,__) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final presetKey = presetLogos[index];
                    final isSelected = _selectedPresetName == presetKey;
                    return InkWell(
                      onTap: () => setState(() { _selectedPresetName = presetKey; _imageFile = null; }),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          border: Border.all(color: isSelected ? primaryColor : Colors.transparent, width: 3),
                          shape: BoxShape.circle,
                        ),
                        child: TeamLogoWidget(logoUrl: presetKey, radius: 32),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 32),
              const Text("OU", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),

              ElevatedButton.icon(
                onPressed: () async {
                  final picker = ImagePicker();
                  final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
                  if (img != null) setState(() { _imageFile = img; _selectedPresetName = null; });
                },
                icon: const Icon(Icons.photo_library),
                label: const Text("ENVIAR MINHA LOGO PERSONALIZADA"),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, minimumSize: const Size(double.infinity, 50)),
              ),

              const SizedBox(height: 60),
              if (!_isLoading)
                ElevatedButton(
                  onPressed: _saveProfile,
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 55), backgroundColor: primaryColor),
                  child: const Text("SALVAR ALTERAÇÕES", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              if (_isLoading) const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShieldPreview(team) {
    // 1. Arquivo do celular
    if (_imageFile != null) {
      return CircleAvatar(radius: 50, backgroundImage: kIsWeb ? NetworkImage(_imageFile!.path) : FileImage(File(_imageFile!.path)) as ImageProvider);
    }
    // 2. Preset sendo selecionado agora
    if (_selectedPresetName != null) {
      return TeamLogoWidget(logoUrl: _selectedPresetName!, radius: 50);
    }
    // 3. Logo atual do Firebase (pode ser preset ou http)
    return TeamLogoWidget(logoUrl: team?.customLogoUrl, radius: 50);
  }
}