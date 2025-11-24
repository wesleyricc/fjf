import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart'; // <-- Importante
import '../services/admin_service.dart';
import '../services/championship_service.dart'; // <-- Importante
import '../services/firestore_service.dart'; // <-- Importante

class TiebreakerCriterion {
  final String key;
  final String name;
  final String description;

  TiebreakerCriterion({required this.key, required this.name, required this.description});
}

class TiebreakerRulesScreen extends StatefulWidget {
  const TiebreakerRulesScreen({super.key});

  @override
  State<TiebreakerRulesScreen> createState() => _TiebreakerRulesScreenState();
}

class _TiebreakerRulesScreenState extends State<TiebreakerRulesScreen> {
  bool _isLoading = false;
  bool _isSaving = false;

  // Lista dos critérios disponíveis
  final Map<String, TiebreakerCriterion> _availableCriteria = {
    'head_to_head': TiebreakerCriterion(key: 'head_to_head', name: 'Confronto Direto', description: 'Resultado entre as equipes empatadas'),
    'disciplinary_points': TiebreakerCriterion(key: 'disciplinary_points', name: 'Menor Pontuação Disciplinar', description: 'Menos pontos (CA=10, CV=21)'),
    'wins': TiebreakerCriterion(key: 'wins', name: 'Maior Nº de Vitórias', description: 'Quem venceu mais'),
    'goal_difference': TiebreakerCriterion(key: 'goal_difference', name: 'Melhor Saldo de Gols', description: 'Gols Pró - Gols Contra'),
    'goals_against': TiebreakerCriterion(key: 'goals_against', name: 'Menor Nº de Gols Sofridos', description: 'Defesa menos vazada'),
    'draw_sort': TiebreakerCriterion(key: 'draw_sort', name: 'Sorteio', description: 'Último recurso'),
  };

  List<TiebreakerCriterion> _currentOrder = [];

  @override
  void initState() {
    super.initState();
    _loadCurrentOrder();
  }

  void _loadCurrentOrder() {
    // Carrega da memória do AdminService (que já está atualizado pelo ChampionshipService)
    List<String> orderKeys = AdminService.tiebreakerOrder;
    
    // Converte chaves para objetos
    _currentOrder = orderKeys
        .map((key) => _availableCriteria[key])
        .where((c) => c != null)
        .cast<TiebreakerCriterion>()
        .toList();
        
    // Adiciona quaisquer critérios faltantes no final (segurança)
    for (var key in _availableCriteria.keys) {
      if (!_currentOrder.any((c) => c.key == key)) {
        _currentOrder.add(_availableCriteria[key]!);
      }
    }
  }

  // Helper para salvar no local certo
  DocumentReference _getSettingsDocRef(String seasonId, String docId) {
    if (seasonId == FirestoreService.LEGACY_ID) {
      return FirebaseFirestore.instance.collection('config').doc(docId);
    } else {
      return FirebaseFirestore.instance
          .collection('championships')
          .doc(seasonId)
          .collection('settings')
          .doc(docId);
    }
  }

  Future<void> _saveOrder() async {
    setState(() => _isSaving = true);
    
    // 1. Pega Temporada
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    try {
      List<String> newOrderKeys = _currentOrder.map((c) => c.key).toList();
      
      // 2. Salva no documento correto
      await _getSettingsDocRef(seasonId, 'tiebreaker_rules').set({
        'order': newOrderKeys,
      }, SetOptions(merge: true));

      // 3. Atualiza memória local e serviço
      AdminService.tiebreakerOrder = newOrderKeys;
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ordem salva com sucesso!')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _currentOrder.removeAt(oldIndex);
      _currentOrder.insert(newIndex, item);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Critérios de Desempate'),
        actions: [
          IconButton(
            icon: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.save),
            onPressed: _isSaving || _isLoading ? null : _saveOrder,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
            children: [
               Padding(
                 padding: const EdgeInsets.all(16.0),
                 child: Text(
                   'Arraste os critérios para definir a ordem de desempate (após Pontos). O primeiro da lista tem maior prioridade.',
                   style: Theme.of(context).textTheme.bodyMedium,
                 ),
               ),
               Expanded(
                 child: ReorderableListView(
                   children: _currentOrder.map((criterion) => ListTile(
                     key: ValueKey(criterion.key),
                     leading: CircleAvatar(
                       radius: 15,
                       backgroundColor: Theme.of(context).primaryColor.withOpacity(0.7),
                       child: Text('${_currentOrder.indexOf(criterion) + 1}º', style: const TextStyle(color: Colors.white, fontSize: 12)),
                     ),
                     title: Text(criterion.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                     subtitle: Text(criterion.description),
                     trailing: const Icon(Icons.drag_handle),
                   )).toList(),
                   onReorder: _onReorder,
                 ),
               ),
            ],
          ),
    );
  }
}