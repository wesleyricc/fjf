import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/player_model.dart';
import '../../services/portal_auth_service.dart';
import '../../services/player_service.dart';
import '../../services/championship_service.dart';
import '../../theme/app_theme.dart';

class PortalProfileTab extends StatefulWidget {
  const PortalProfileTab({super.key});

  @override
  State<PortalProfileTab> createState() => _PortalProfileTabState();
}

class _PortalProfileTabState extends State<PortalProfileTab> {
  final _formKey = GlobalKey<FormState>();
  
  bool _isLoading = true;
  bool _isSaving = false;
  Player? _playerProfile;

  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _cpfController = TextEditingController();
  DateTime? _dateOfBirth;
  String? _preferredFoot;

  final List<String> _footOptions = ['Destro', 'Canhoto', 'Ambidestro'];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = Provider.of<PortalAuthService>(context, listen: false).currentPortalUser;
    if (user?.playerId != null) {
      final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
      final playerService = Provider.of<PlayerService>(context, listen: false);
      _playerProfile = await playerService.getPlayer(user!.playerId!, seasonId);
      
      if (_playerProfile != null) {
        _heightController.text = _playerProfile!.heightCm?.toString() ?? '';
        _weightController.text = _playerProfile!.weightKg?.toString() ?? '';
        _cpfController.text = user.cpf ?? '';
        _dateOfBirth = _playerProfile!.dateOfBirth;
        _preferredFoot = _footOptions.contains(_playerProfile!.preferredFoot) ? _playerProfile!.preferredFoot : null;
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    
    final user = Provider.of<PortalAuthService>(context, listen: false).currentPortalUser;
    if (user?.playerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seu perfil não está vinculado a um jogador oficial.'), backgroundColor: Colors.red));
      return;
    }

    setState(() => _isSaving = true);
    try {
      final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
      final playerService = Provider.of<PlayerService>(context, listen: false);
      
      final data = {
        'height_cm': int.tryParse(_heightController.text),
        'weight_kg': int.tryParse(_weightController.text),
        'preferred_foot': _preferredFoot,
        'date_of_birth': _dateOfBirth != null ? Timestamp.fromDate(_dateOfBirth!) : null,
      };
      
      final portalAuth = Provider.of<PortalAuthService>(context, listen: false);
      await portalAuth.updatePortalUserCpf(user!.id, _cpfController.text.trim());
      
      final result = await playerService.updatePlayer(seasonId: seasonId, playerId: user.playerId!, data: data);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result), backgroundColor: result.startsWith('Sucesso') ? Colors.green : Colors.red));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: '), backgroundColor: Colors.red));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final user = Provider.of<PortalAuthService>(context, listen: false).currentPortalUser;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CircleAvatar(
            radius: 40,
            backgroundColor: AppTheme.primaryColor,
            child: Icon(Icons.person, size: 40, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Text(user?.name ?? 'Atleta', textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          Text(user?.username ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.grey)),
          
          const SizedBox(height: 32),
          if (_playerProfile == null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(8)),
              child: const Text('Seu acesso ainda não foi vinculado ao elenco oficial. Solicite ao presidente a vinculação para editar seus dados públicos.', style: TextStyle(color: Colors.deepOrange)),
            )
          else ...[
            const Text('Ficha Pública do Jogador', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Text('Esses dados ficam visíveis para torcedores e outras equipes no aplicativo.', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _heightController,
                          decoration: const InputDecoration(labelText: 'Altura (cm)', border: OutlineInputBorder()),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _weightController,
                          decoration: const InputDecoration(labelText: 'Peso (kg)', border: OutlineInputBorder()),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _preferredFoot,
                    decoration: const InputDecoration(labelText: 'Pé Preferido', border: OutlineInputBorder()),
                    items: _footOptions.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                    onChanged: (val) => setState(() => _preferredFoot = val),
                  ),
                  const SizedBox(height: 24),
                  _isSaving
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 50),
                        ),
                        onPressed: _saveProfile,
                        child: const Text('SALVAR DADOS'),
                      ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
