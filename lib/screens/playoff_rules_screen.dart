// lib/screens/playoff_rules_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/admin_service.dart';

class PlayoffRulesScreen extends StatefulWidget {
  const PlayoffRulesScreen({super.key});

  @override
  State<PlayoffRulesScreen> createState() => _PlayoffRulesScreenState();
}

class _PlayoffRulesScreenState extends State<PlayoffRulesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;
  bool _isSaving = false;

  // Estados para guardar as seleções
  late String _semiRule;
  late String _thirdRule;
  late String _finalRule;

  // Opções disponíveis
  final List<DropdownMenuItem<String>> _ruleOptions = const [
    DropdownMenuItem(value: 'penalties', child: Text('Pênaltis Direto')),
    DropdownMenuItem(value: 'extra_time_penalties', child: Text('Prorrogação + Pênaltis')),
    DropdownMenuItem(value: 'extra_time_standing', child: Text('Prorrogação + Melhor Classif.')),
  ];

  @override
  void initState() {
    super.initState();
    // Inicializa com os valores carregados pelo AdminService
    _semiRule = AdminService.semifinalTiebreaker;
    _thirdRule = AdminService.thirdPlaceTiebreaker;
    _finalRule = AdminService.finalTiebreaker;
    // Poderia adicionar _loadCurrentRules() se quisesse buscar de novo
  }

  Future<void> _saveRules() async {
    setState(() { _isSaving = true; });
    try {
      await _firestore.collection('config').doc('playoff_rules').set({
        'semifinal_tiebreaker': _semiRule,
        'third_place_tiebreaker': _thirdRule,
        'final_tiebreaker': _finalRule,
      });

      await AdminService.loadPlayoffRules(); // Recarrega no serviço

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Regras de desempate playoff salvas!')));
        Navigator.of(context).pop();
      }
    } catch (e) { /* ... tratamento de erro ... */ }
    finally { if (mounted) setState(() { _isSaving = false; }); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Regras Desempate Mata-Mata'),
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

  // Widget auxiliar para criar o seletor
  Widget _buildRuleSelector(String title, String currentValue, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      value: currentValue,
      items: _ruleOptions,
      onChanged: _isSaving ? null : onChanged, // Desabilita se estiver salvando
      decoration: InputDecoration(
        labelText: 'Critério de Desempate - $title',
        border: const OutlineInputBorder(),
      ),
    );
  }
}