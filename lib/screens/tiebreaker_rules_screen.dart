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
  bool _isLoading = true;
  bool _isSaving = false;

  // Lista dos critérios disponíveis (fixa, mas com descrições)
  final Map<String, TiebreakerCriterion> _availableCriteria = {
    'head_to_head': TiebreakerCriterion(key: 'head_to_head', name: 'Confronto Direto', description: 'Resultado entre as equipes empatadas (2 equipes)'),
    'disciplinary_points': TiebreakerCriterion(key: 'disciplinary_points', name: 'Menor Pontuação Disciplinar', description: 'Menos pontos (CA=10, CV=21)'),
    'wins': TiebreakerCriterion(key: 'wins', name: 'Maior Nº de Vitórias', description: 'Total de vitórias na 1ª Fase'),
    'goal_difference': TiebreakerCriterion(key: 'goal_difference', name: 'Melhor Saldo de Gols', description: 'Gols Pró menos Gols Contra'),
    'goals_against': TiebreakerCriterion(key: 'goals_against', name: 'Menor Nº Gols Sofridos', description: 'Menos gols tomados'),
    'draw_sort': TiebreakerCriterion(key: 'draw_sort', name: 'Sorteio', description: 'Último critério padrão'),
  };

  // Estado atual da ordem (será preenchido no initState)
  List<TiebreakerCriterion> _currentOrder = [];

  @override
  void initState() {
    super.initState();
    _loadCriteria();
  }

  // --- FUNÇÃO ATUALIZADA ---
  Future<void> _loadCriteria() async {
    setState(() => _isLoading = true);
    
    // --- INÍCIO DA CORREÇÃO ---
    // Chamada corrigida de 'loadTiebreakerRules' para 'loadTiebreakerOrder'
    await AdminService.loadTiebreakerOrder();
    // --- FIM DA CORREÇÃO ---

    // Mapeia a ordem salva (List<String>) para a lista de objetos (List<TiebreakerCriterion>)
    _currentOrder = AdminService.tiebreakerOrder.map((key) {
      return _availableCriteria[key];
    }).whereType<TiebreakerCriterion>().toList(); // 'whereType' remove nulos

    // Adiciona critérios que possam ser novos e não estão na ordem salva
    for (var criterion in _availableCriteria.values) {
      if (!_currentOrder.any((c) => c.key == criterion.key)) {
        _currentOrder.add(criterion);
      }
    }
    
    if(mounted) setState(() => _isLoading = false);
  }
  // --- FIM DA FUNÇÃO ---

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final TiebreakerCriterion item = _currentOrder.removeAt(oldIndex);
      _currentOrder.insert(newIndex, item);
    });
  }

  Future<void> _saveOrder() async {
    setState(() => _isSaving = true);
    
    try {
      // Converte a lista de objetos de volta para uma lista de chaves (Strings)
      final List<String> newOrderKeys = _currentOrder.map((c) => c.key).toList();
      
      await _firestore.collection('config').doc('tiebreaker_rules').set({
        'order': newOrderKeys,
      });

      // Atualiza o cache local do AdminService
      AdminService.tiebreakerOrder = newOrderKeys;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ordem de desempate salva com sucesso!')),
        );
        Navigator.of(context).pop();
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ordem de Desempate'),
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
                       child: Text('${_currentOrder.indexOf(criterion) + 1}º'),
                       radius: 15,
                       backgroundColor: Theme.of(context).primaryColor.withOpacity(0.7),
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