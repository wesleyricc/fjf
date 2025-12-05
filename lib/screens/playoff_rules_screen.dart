import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart'; 
import '../services/admin_service.dart';
import '../services/championship_service.dart'; 

class PlayoffRulesScreen extends StatefulWidget {
  const PlayoffRulesScreen({super.key});

  @override
  State<PlayoffRulesScreen> createState() => _PlayoffRulesScreenState();
}

class _PlayoffRulesScreenState extends State<PlayoffRulesScreen> {
  bool _isLoading = false;
  bool _isSaving = false;

  // Estados
  late String _semiRule;
  late String _thirdRule;
  late String _finalRule;

  // Opções
  final List<DropdownMenuItem<String>> _ruleOptions = const [
    DropdownMenuItem(value: 'penalties', child: Text('Pênaltis Direto')),
    DropdownMenuItem(value: 'extra_time_penalties', child: Text('Prorrogação + Pênaltis')),
    DropdownMenuItem(value: 'extra_time_standing', child: Text('Prorrogação + Melhor Classif.')),
  ];

  @override
  void initState() {
    super.initState();
    // Inicializa com os valores já carregados no AdminService
    _semiRule = AdminService.semifinalTiebreaker;
    _thirdRule = AdminService.thirdPlaceTiebreaker;
    _finalRule = AdminService.finalTiebreaker;
  }

  // Helper de roteamento (PADRONIZADO)
  DocumentReference _getSettingsDocRef(String seasonId, String docId) {
    // Aponta sempre para a subcoleção da temporada atual
    return FirebaseFirestore.instance
        .collection('championships')
        .doc(seasonId)
        .collection('settings')
        .doc(docId);
  }

  Future<void> _saveRules() async {
    setState(() => _isSaving = true);
    
    // 1. Pega Temporada
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    try {
      // 2. Salva no doc correto
      await _getSettingsDocRef(seasonId, 'playoff_rules').set({
        'semifinal_tiebreaker': _semiRule,
        'third_place_tiebreaker': _thirdRule,
        'final_tiebreaker': _finalRule,
      }, SetOptions(merge: true));

      // 3. Atualiza memória (Cache local para uso imediato)
      AdminService.semifinalTiebreaker = _semiRule;
      AdminService.thirdPlaceTiebreaker = _thirdRule;
      AdminService.finalTiebreaker = _finalRule;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Regras de mata-mata salvas!')));
        Navigator.of(context).pop();
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
        title: const Text('Regras de Mata-Mata'),
        actions: [
          IconButton(
            icon: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.save),
            onPressed: _isSaving ? null : _saveRules,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildRuleSelector('Semifinal', _semiRule, (value) {
                  if (value != null) setState(() => _semiRule = value);
                }),
                const SizedBox(height: 20),
                _buildRuleSelector('Disputa de 3º Lugar', _thirdRule, (value) {
                   if (value != null) setState(() => _thirdRule = value);
                }),
                const SizedBox(height: 20),
                 _buildRuleSelector('Final', _finalRule, (value) {
                   if (value != null) setState(() => _finalRule = value);
                }),
              ],
            ),
    );
  }

  Widget _buildRuleSelector(String title, String currentValue, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      value: currentValue,
      items: _ruleOptions,
      onChanged: _isSaving ? null : onChanged,
      decoration: InputDecoration(
        labelText: 'Critério de Desempate - $title',
        border: const OutlineInputBorder(),
      ),
    );
  }
}