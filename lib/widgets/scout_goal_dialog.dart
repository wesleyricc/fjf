import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/championship_service.dart';
import '../services/firestore_service.dart';
import '../models/match_event.dart';

class ScoutGoalDialog extends StatefulWidget {
  final DocumentSnapshot match;
  final List<DocumentSnapshot> homePlayers;
  final List<DocumentSnapshot> awayPlayers;

  const ScoutGoalDialog({
    super.key,
    required this.match,
    required this.homePlayers,
    required this.awayPlayers,
  });

  @override
  State<ScoutGoalDialog> createState() => _ScoutGoalDialogState();
}

class _ScoutGoalDialogState extends State<ScoutGoalDialog> {
  final FirestoreService _firestoreService = FirestoreService();
  
  String? _selectedTeamId;
  String? _scorerId;
  String? _scorerName;
  String? _assistId;
  String? _assistName;
  String? _concededById;
  
  final _minuteController = TextEditingController();
  String _selectedPeriod = '1T';
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final homeId = widget.match['team_home_id'];
    final awayId = widget.match['team_away_id'];
    final homeName = widget.match['team_home_name'];
    final awayName = widget.match['team_away_name'];

    // Define as listas baseadas no time selecionado
    List<DocumentSnapshot> scoringTeamPlayers = [];
    List<DocumentSnapshot> opposingTeamPlayers = [];

    if (_selectedTeamId == homeId) {
      scoringTeamPlayers = widget.homePlayers;
      opposingTeamPlayers = widget.awayPlayers;
    } else if (_selectedTeamId == awayId) {
      scoringTeamPlayers = widget.awayPlayers;
      opposingTeamPlayers = widget.homePlayers;
    }

    // Filtra quem pode fazer gol (remove Staff)
    final scoringCandidates = scoringTeamPlayers.where((doc) {
       final data = doc.data() as Map<String, dynamic>;
       return data['is_staff'] != true;
    }).toList();

    // Filtra possíveis assistentes (remove quem fez o gol)
    final assistCandidates = (_scorerId != null) 
        ? scoringCandidates.where((doc) => doc.id != _scorerId).toList()
        : [];

    return AlertDialog(
      title: const Text('Registrar Gol'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. SELEÇÃO DE TIME
            DropdownButtonFormField<String>(
              value: _selectedTeamId,
              isExpanded: true,
              hint: const Text('Equipe que marcou'),
              decoration: const InputDecoration(labelText: 'Time do Gol', border: OutlineInputBorder()),
              items: [
                DropdownMenuItem(value: homeId, child: Text(homeName, overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: awayId, child: Text(awayName, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: _isSaving ? null : (v) {
                setState(() {
                  _selectedTeamId = v;
                  _scorerId = null;
                  _assistId = null;
                  _concededById = null;
                  
                  // Tenta pré-selecionar goleiro adversário (para facilitar)
                  final opponents = (v == homeId) ? widget.awayPlayers : widget.homePlayers;
                  try {
                    final gk = opponents.firstWhere((p) => (p.data() as Map)['is_goalkeeper'] == true);
                    _concededById = gk.id;
                  } catch (_) {}
                });
              },
            ),
            const SizedBox(height: 16),
            
            // 2. AUTOR DO GOL
            DropdownButtonFormField<String>(
              value: _scorerId,
              isExpanded: true,
              hint: const Text('Quem fez o gol?'),
              decoration: const InputDecoration(labelText: 'Autor do Gol', border: OutlineInputBorder()),
              items: scoringCandidates.map((p) {
                final d = p.data() as Map<String, dynamic>;
                return DropdownMenuItem(
                  value: p.id,
                  child: Text("${d['jersey_number'] ?? '-'} ${d['name']}", overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (_selectedTeamId == null || _isSaving) ? null : (v) {
                 final p = scoringCandidates.firstWhere((doc) => doc.id == v);
                 final d = p.data() as Map<String, dynamic>;
                 setState(() {
                   _scorerId = v;
                   _scorerName = d['name'];
                   _assistId = null; // Reseta assistência se mudar o autor
                 });
              },
            ),
            const SizedBox(height: 16),

            // 3. ASSISTÊNCIA
            DropdownButtonFormField<String>(
              value: _assistId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Assistência (Opcional)', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: null, child: Text('Sem assistência')),
                ...assistCandidates.map((p) {
                  final d = p.data() as Map<String, dynamic>;
                  return DropdownMenuItem(
                    value: p.id,
                    child: Text("${d['jersey_number'] ?? '-'} ${d['name']}", overflow: TextOverflow.ellipsis),
                  );
                }),
              ],
              onChanged: (_scorerId == null || _isSaving) ? null : (v) {
                 if (v != null) {
                   final p = assistCandidates.firstWhere((doc) => doc.id == v);
                   final d = p.data() as Map<String, dynamic>;
                   _assistName = d['name'];
                 }
                 setState(() => _assistId = v);
              },
            ),
            const SizedBox(height: 16),

            // 4. GOLEIRO (GOL SOFRIDO)
            DropdownButtonFormField<String>(
              value: _concededById,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Goleiro (Gol Sofrido)', border: OutlineInputBorder()),
              items: opposingTeamPlayers
                .where((p) => (p.data() as Map)['is_staff'] != true)
                .map((p) {
                  final d = p.data() as Map<String, dynamic>;
                  final isGk = d['is_goalkeeper'] == true;
                  return DropdownMenuItem(
                    value: p.id, 
                    child: Row(
                      children: [
                       if(isGk) ...[
                         const Icon(Icons.pan_tool_outlined, size: 14, color: Colors.grey),
                         const SizedBox(width: 4),
                       ],
                       Expanded(child: Text("${d['jersey_number'] ?? '-'} ${d['name']}", overflow: TextOverflow.ellipsis)),
                    ])
                  );
              }).toList(),
              onChanged: (_selectedTeamId == null || _isSaving) ? null : (v) => setState(() => _concededById = v),
            ),
            const SizedBox(height: 16),

            // 5. TEMPO
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _minuteController, 
                    decoration: const InputDecoration(labelText: 'Minuto', border: OutlineInputBorder()), 
                    keyboardType: TextInputType.number,
                    enabled: !_isSaving,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedPeriod, 
                    items: const [
                      DropdownMenuItem(value: '1T', child: Text('1º T')), 
                      DropdownMenuItem(value: '2T', child: Text('2º T'))
                    ], 
                    onChanged: _isSaving ? null : (v) => setState(() => _selectedPeriod = v!), 
                    decoration: const InputDecoration(border: OutlineInputBorder())
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(), 
          child: const Text('Cancelar')
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
          onPressed: _isSaving ? null : _saveGoal,
          child: _isSaving 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
              : const Text('CONFIRMAR'),
        ),
      ],
    );
  }

  Future<void> _saveGoal() async {
    if (_selectedTeamId == null || _scorerId == null || _minuteController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preencha os dados obrigatórios.')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
      final int minute = int.tryParse(_minuteController.text) ?? 0;
      final DateTime now = DateTime.now();

      // 1. Evento GOL
      final goalEvent = MatchEvent(
        id: '', 
        type: MatchEventType.goal,
        playerId: _scorerId!,
        playerName: _scorerName ?? 'Atleta',
        teamId: _selectedTeamId!,
        minute: minute,
        period: _selectedPeriod,
        timestamp: now,
        concededByPlayerId: _concededById, 
      );

      await _firestoreService.addMatchEvent(seasonId: seasonId, matchId: widget.match.id, event: goalEvent);

      // 2. Evento ASSISTÊNCIA (se houver)
      if (_assistId != null) {
        final assistEvent = MatchEvent(
          id: '',
          type: MatchEventType.assist,
          playerId: _assistId!,
          playerName: _assistName ?? 'Atleta',
          teamId: _selectedTeamId!,
          minute: minute,
          period: _selectedPeriod,
          timestamp: now.add(const Duration(milliseconds: 100)), // Leve delay para ordenação
        );
        await _firestoreService.addMatchEvent(seasonId: seasonId, matchId: widget.match.id, event: assistEvent);
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gol registrado!')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }
}