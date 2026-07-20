import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../../utils/bolao_constants.dart';

class AdminBolaoBonusTab extends StatefulWidget {
  const AdminBolaoBonusTab({super.key});

  @override
  State<AdminBolaoBonusTab> createState() => _AdminBolaoBonusTabState();
}

class _AdminBolaoBonusTabState extends State<AdminBolaoBonusTab> {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  bool _isLoading = false;

  String? _officialChampion;
  String? _officialRunnerUp;
  List<String> _officialBestOffense = []; 
  List<String> _officialWorstDefense = []; 
  String? _officialDisappointment;

  Future<void> _processFinalBonuses() async {
    if (_officialChampion == null || _officialRunnerUp == null || _officialBestOffense.isEmpty || _officialWorstDefense.isEmpty || _officialDisappointment == null) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Preencha todos os prêmios antes de processar!"), backgroundColor: Colors.red));
       return;
    }
    setState(() => _isLoading = true);
    try {
      final callable = _functions.httpsCallable('calculateBonusPoints');
      await callable.call({
        'officialChampion': _officialChampion,
        'officialRunnerUp': _officialRunnerUp,
        'officialBestOffense': _officialBestOffense,
        'officialWorstDefense': _officialWorstDefense,
        'officialDisappointment': _officialDisappointment,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🏆 Campeões Definidos! Ranking Finalizado!"), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e"), backgroundColor: Colors.red));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildAdminBonusDropdown(String label, String? currentValue, Function(String?) onChanged) {
    final List<String> availableTeams = BolaoConstants.teamsFlagsMap.keys.where((k) => k != 'A Definir' && !k.contains('Grupo')).toList()..sort();
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: DropdownButtonFormField<String>(
        value: currentValue,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        items: availableTeams.map((team) {
          return DropdownMenuItem(
            value: team,
            child: Row(
              children: [
                Text(BolaoConstants.teamsFlagsMap[team] ?? '❓', style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(team),
              ],
            ),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildAdminMultiBonusSelector({
    required String label,
    required List<String> currentValues,
    required Function(List<String>) onChanged,
  }) {
    final List<String> availableTeams = BolaoConstants.teamsFlagsMap.keys.where((k) => k != 'A Definir' && !k.contains('Grupo')).toList()..sort();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(4)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6.0,
              runSpacing: 6.0,
              children: currentValues.map((team) {
                return Chip(
                  label: Text(team, style: const TextStyle(fontSize: 12)),
                  backgroundColor: Colors.purple.shade100,
                  deleteIconColor: Colors.purple,
                  onDeleted: () {
                    final newValues = List<String>.from(currentValues)..remove(team);
                    onChanged(newValues);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            DropdownButton<String>(
              isExpanded: true,
              hint: const Text("Adicionar time..."),
              value: null,
              items: availableTeams.where((t) => !currentValues.contains(t)).map((team) {
                return DropdownMenuItem(
                  value: team,
                  child: Row(
                    children: [
                      Text(BolaoConstants.teamsFlagsMap[team] ?? '❓', style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 8),
                      Text(team),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  final newValues = List<String>.from(currentValues)..add(val);
                  onChanged(newValues);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: const Text("🏆 Definir Campeões e Bônus (Fim da Copa)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
      leading: const Icon(Icons.emoji_events, color: Colors.purple),
      backgroundColor: Colors.purple.shade50,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildAdminBonusDropdown("O Grande Campeão", _officialChampion, (val) => setState(() => _officialChampion = val)),
              _buildAdminBonusDropdown("O Vice-Campeão", _officialRunnerUp, (val) => setState(() => _officialRunnerUp = val)),
              
              _buildAdminMultiBonusSelector(
                label: "Melhor Ataque (Mais Gols)",
                currentValues: _officialBestOffense,
                onChanged: (vals) => setState(() => _officialBestOffense = vals),
              ),
              _buildAdminMultiBonusSelector(
                label: "Pior Defesa (Saco de Pancadas)",
                currentValues: _officialWorstDefense,
                onChanged: (vals) => setState(() => _officialWorstDefense = vals),
              ),

              _buildAdminBonusDropdown("A Grande Decepção", _officialDisappointment, (val) => setState(() => _officialDisappointment = val)),
              
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white, padding: const EdgeInsets.all(12)),
                  onPressed: _isLoading ? null : _processFinalBonuses,
                  icon: const Icon(Icons.calculate),
                  label: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("PROCESSAR PONTUAÇÃO FINAL"),
                ),
              )
            ],
          ),
        )
      ],
    );
  }
}
