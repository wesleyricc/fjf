import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/admin_service.dart';
import '../services/championship_service.dart';

class TournamentFormatScreen extends StatefulWidget {
  const TournamentFormatScreen({super.key});

  @override
  State<TournamentFormatScreen> createState() => _TournamentFormatScreenState();
}

class _TournamentFormatScreenState extends State<TournamentFormatScreen> {
  String _selectedFormat = 'model_1';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedFormat = AdminService.tournamentFormat;
  }

  Future<void> _saveFormat() async {
    setState(() => _isSaving = true);
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    try {
      await FirebaseFirestore.instance
          .collection('championships')
          .doc(seasonId)
          .collection('settings')
          .doc('app_settings')
          .set({
            'tournament_format': _selectedFormat,
          }, SetOptions(merge: true));

      // Atualiza memória local
      AdminService.tournamentFormat = _selectedFormat;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Formato atualizado com sucesso!')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Forma de Disputa'),
        actions: [
          IconButton(
            icon: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.save),
            onPressed: _isSaving ? null : _saveFormat,
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildFormatCard(
              value: 'model_1',
              title: 'Modelo 1 - Clássico (Atual)',
              description: '• 1ª Fase: Turno único.\n• Classificação: Os 4 primeiros avançam.\n• Mata-Mata: Semifinal (1ºx4º, 2ºx3º) -> Final.',
              isRecommended: false,
            ),
            const SizedBox(height: 16),
            _buildFormatCard(
              value: 'model_2',
              title: 'Modelo 2 - Com Playoffs',
              description: '• 1ª Fase: Turno único.\n• Classificação: 1º e 2º vão direto pra Semifinal.\n• Playoffs: Do 3º ao 6º disputam vaga (3ºx6º, 4ºx5º).\n• Mata-Mata: Playoff -> Semifinal -> Final.',
              isRecommended: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatCard({
    required String value,
    required String title,
    required String description,
    required bool isRecommended,
  }) {
    final isSelected = _selectedFormat == value;
    final primaryColor = Theme.of(context).primaryColor;

    return GestureDetector(
      onTap: () => setState(() => _selectedFormat = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? primaryColor : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: primaryColor.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4))]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: isSelected ? primaryColor : Colors.grey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isSelected ? primaryColor : Colors.black87)),
                ),
                if (isRecommended)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(4)),
                    child: const Text('NOVO', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const Divider(height: 24),
            Text(description, style: TextStyle(color: Colors.grey[800], height: 1.5)),
          ],
        ),
      ),
    );
  }
}