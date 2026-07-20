import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Para o kIsWeb
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../viewmodels/fantasy_home_viewmodel.dart';
import '../../widgets/team_logo_widget.dart'; // 🚨 Importando nosso novo widget
import '../../services/analytics_service.dart'; // 🚨 RASTREAMENTO

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
    'preset_1', 'preset_2', 'preset_3', 'preset_4',
    'preset_5', 'preset_6', 'preset_7', 'preset_8'
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
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Editar Equipe", style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Background Header
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: primaryColor,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  // Shield Preview Card
                  Center(
                    child: GestureDetector(
                      onTap: () => _showShieldSelectionMenu(context, primaryColor),
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))
                              ],
                            ),
                            child: _buildShieldPreview(team),
                          ),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: primaryColor,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                          )
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Information Card
                  Card(
                    elevation: 2,
                    shadowColor: Colors.black12,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Informações Básicas", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              labelText: "Nome da Equipe",
                              prefixIcon: Icon(Icons.shield, color: primaryColor),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                              filled: true,
                              fillColor: Colors.grey[100],
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'O nome da equipe é obrigatório' : null,
                          ),
                        ],
                      ),
                    ),
                  ),


                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))],
          ),
          child: ElevatedButton(
            onPressed: _isLoading ? null : _saveProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              disabledBackgroundColor: primaryColor.withValues(alpha: 0.5),
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            child: _isLoading 
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : const Text("SALVAR ALTERAÇÕES", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ),
        ),
      ),
    );
  }

  Widget _buildShieldPreview(team) {
    const double rad = 55;
    if (_imageFile != null) {
      return CircleAvatar(radius: rad, backgroundImage: kIsWeb ? NetworkImage(_imageFile!.path) : FileImage(File(_imageFile!.path)) as ImageProvider);
    }
    if (_selectedPresetName != null) {
      return TeamLogoWidget(logoUrl: _selectedPresetName!, radius: rad);
    }
    return TeamLogoWidget(logoUrl: team?.customLogoUrl, radius: rad);
  }

  void _showShieldSelectionMenu(BuildContext context, Color primaryColor) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Alterar Escudo da Equipe", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text("Escolha uma das opções oficiais abaixo:", style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    alignment: WrapAlignment.center,
                    children: presetLogos.map((presetKey) {
                      final isSelected = _selectedPresetName == presetKey;
                      return InkWell(
                        onTap: () {
                          setState(() { _selectedPresetName = presetKey; _imageFile = null; });
                          Navigator.pop(ctx);
                        },
                        borderRadius: BorderRadius.circular(40),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isSelected ? primaryColor.withValues(alpha: 0.1) : Colors.transparent,
                            border: Border.all(color: isSelected ? primaryColor : Colors.grey.shade300, width: isSelected ? 3 : 1),
                            shape: BoxShape.circle,
                          ),
                          child: TeamLogoWidget(logoUrl: presetKey, radius: 32),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  const Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text("OU", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))),
                      Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final picker = ImagePicker();
                      final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
                      if (img != null) {
                        setState(() { _imageFile = img; _selectedPresetName = null; });
                      }
                    },
                    icon: const Icon(Icons.upload_file),
                    label: const Text("ENVIAR FOTO DA GALERIA"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryColor,
                      side: BorderSide(color: primaryColor.withValues(alpha: 0.5), width: 1.5),
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}