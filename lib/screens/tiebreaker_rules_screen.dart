// lib/screens/tiebreaker_rules_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/admin_service.dart';

// Representa um critério na lista reordenável
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
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isLoading = false;
  bool _isSaving = false;

  // Lista dos critérios disponíveis (fixa, mas com descrições)
  final Map<String, TiebreakerCriterion> _availableCriteria = {
    'head_to_head': TiebreakerCriterion(key: 'head_to_head', name: 'Confronto Direto', description: 'Resultado entre as equipes empatadas (2 equipes)'),
    'disciplinary_points': TiebreakerCriterion(key: 'disciplinary_points', name: 'Menor Pontuação Disciplinar', description: 'Menos pontos (CA=10, CV=21)'),
    'wins': TiebreakerCriterion(key: 'wins', name: 'Maior Nº de Vitórias', description: 'Mais vitórias no campeonato'),
    'goal_difference': TiebreakerCriterion(key: 'goal_difference', name: 'Melhor Saldo de Gols', description: 'GP - GC'),
    'goals_against': TiebreakerCriterion(key: 'goals_against', name: 'Menor Nº Gols Sofridos', description: 'Menos gols levados'),
    'draw_sort': TiebreakerCriterion(key: 'draw_sort', name: 'Sorteio / Ordem Alfabética', description: 'Último critério padrão'),
  };

  // Estado atual da ordem (será preenchido no initState)
  List<TiebreakerCriterion> _currentOrder = [];

  @override
  void initState() {
    super.initState();
    _loadCurrentOrder();
  }

  void _loadCurrentOrder() {
     setState(() { _isLoading = true; });
     // Carrega a ordem atual do AdminService
     _currentOrder = AdminService.tiebreakerOrder
        .map((key) => _availableCriteria[key]) // Mapeia a chave para o objeto Criterion
        .where((criterion) => criterion != null) // Filtra caso haja chave inválida
        .cast<TiebreakerCriterion>() // Garante o tipo correto
        .toList();
     setState(() { _isLoading = false; });
  }

  // Função chamada quando a lista é reordenada pelo usuário
  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final TiebreakerCriterion item = _currentOrder.removeAt(oldIndex);
      _currentOrder.insert(newIndex, item);
    });
  }

  // Salva a nova ordem no Firestore
  Future<void> _saveOrder() async {
    setState(() { _isSaving = true; });
    try {
      // Mapeia a lista de objetos de volta para a lista de chaves (strings)
      final List<String> newOrderKeys = _currentOrder.map((c) => c.key).toList();

      await _firestore.collection('config').doc('tiebreaker_rules').set({
        'tiebreaker_order': newOrderKeys,
      });

      // Recarrega as regras no AdminService
      await AdminService.loadTiebreakerRules();

       if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ordem de desempate salva!')));
          Navigator.of(context).pop();
        }

    } catch (e) {
       debugPrint("Erro ao salvar ordem de desempate: $e");
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
    } finally {
       if (mounted) setState(() { _isSaving = false; });
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ordem Critérios Desempate'),
        actions: [
          IconButton(
            icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white)) : const Icon(Icons.save),
            tooltip: 'Salvar Ordem',
            onPressed: _isSaving ? null : _saveOrder,
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
                 // --- LISTA REORDENÁVEL ---
                 child: ReorderableListView(
                   children: _currentOrder.map((criterion) => ListTile(
                     // Key é ESSENCIAL para ReorderableListView
                     key: ValueKey(criterion.key),
                     leading: CircleAvatar(
                       child: Text('${_currentOrder.indexOf(criterion) + 1}º'), // Mostra a ordem atual
                       radius: 15,
                       backgroundColor: Theme.of(context).primaryColor.withOpacity(0.7),
                     ),
                     title: Text(criterion.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                     subtitle: Text(criterion.description),
                     trailing: const Icon(Icons.drag_handle), // Ícone para arrastar
                   )).toList(),
                   onReorder: _onReorder,
                 ),
                 // --- FIM DA LISTA ---
               ),
            ],
          ),
    );
  }
}