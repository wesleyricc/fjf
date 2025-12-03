import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/championship_service.dart';
import '../services/firestore_service.dart';
import '../models/match_event.dart';

class ScoutCardDialog extends StatefulWidget {
  final DocumentSnapshot match;
  final List<DocumentSnapshot> homePlayers;
  final List<DocumentSnapshot> awayPlayers;
  final MatchEventType cardType; // yellowCard ou redCard

  const ScoutCardDialog({
    super.key,
    required this.match,
    required this.homePlayers,
    required this.awayPlayers,
    required this.cardType,
  });

  @override
  State<ScoutCardDialog> createState() => _ScoutCardDialogState();
}

class _ScoutCardDialogState extends State<ScoutCardDialog> {
  final FirestoreService _firestoreService = FirestoreService();
  
  String? _selectedTeamId;
  String? _selectedPlayerId;
  String? _selectedPlayerName;
  final _minuteController = TextEditingController();
  String _selectedPeriod = '1T';
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final homeId = widget.match['team_home_id'];
    final awayId = widget.match['team_away_id'];
    final homeName = widget.match['team_home_name'];
    final awayName = widget.match['team_away_name'];
    
    final bool isRed = widget.cardType == MatchEventType.redCard;
    final Color color = isRed ? Colors.red : Colors.amber[800]!;
    final String title = isRed ? "CARTÃO VERMELHO" : "CARTÃO AMARELO";

    // Lista de jogadores (aqui INCLUI Staff, pois técnico toma cartão)
    List<DocumentSnapshot> activePlayers = [];
    if (_selectedTeamId == homeId) activePlayers = widget.homePlayers;
    else if (_selectedTeamId == awayId) activePlayers = widget.awayPlayers;

    return AlertDialog(
      title: Text('Novo: $title', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Time
            DropdownButtonFormField<String>(
              value: _selectedTeamId,
              isExpanded: true,
              hint: const Text('Selecione a Equipe'),
              decoration: const InputDecoration(labelText: 'Equipe', border: OutlineInputBorder()),
              items: [
                DropdownMenuItem(value: homeId, child: Text(homeName, overflow: TextOverflow.ellipsis)),
                DropdownMenuItem(value: awayId, child: Text(awayName, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: _isSaving ? null : (v) => setState(() { 
                _selectedTeamId = v; 
                _selectedPlayerId = null; 
              }),
            ),
            const SizedBox(height: 16),
            
            // 2. Jogador/Staff
            DropdownButtonFormField<String>(
              value: _selectedPlayerId,
              isExpanded: true,
              hint: const Text('Selecione o Atleta/Membro'),
              decoration: const InputDecoration(labelText: 'Quem recebeu?', border: OutlineInputBorder()),
              items: activePlayers.map((p) {
                final d = p.data() as Map<String, dynamic>;
                final bool isStaff = d['is_staff'] == true;
                return DropdownMenuItem(
                  value: p.id, 
                  child: Text(
                    isStaff 
                        ? "${d['name']} (Comissão)" 
                        : "${d['jersey_number'] ?? '-'} ${d['name']}",
                    overflow: TextOverflow.ellipsis
                  ),
                );
              }).toList(),
              onChanged: (_selectedTeamId == null || _isSaving) ? null : (v) {
                 final p = activePlayers.firstWhere((doc) => doc.id == v);
                 final d = p.data() as Map<String, dynamic>;
                 setState(() {
                   _selectedPlayerId = v;
                   _selectedPlayerName = d['name'];
                 });
              },
            ),
            const SizedBox(height: 16),
            
            // 3. Tempo
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
          style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
          onPressed: _isSaving ? null : _saveCard,
          child: _isSaving 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
              : const Text('Confirmar'),
        ),
      ],
    );
  }

  Future<void> _saveCard() async {
    if (_selectedPlayerId == null || _minuteController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preencha os dados.')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
      final int minute = int.tryParse(_minuteController.text) ?? 0;

      final event = MatchEvent(
        id: '', 
        type: widget.cardType, 
        playerId: _selectedPlayerId!, 
        playerName: _selectedPlayerName ?? 'Atleta', 
        teamId: _selectedTeamId!, 
        minute: minute, 
        period: _selectedPeriod, 
        timestamp: DateTime.now()
      );

      await _firestoreService.addMatchEvent(seasonId: seasonId, matchId: widget.match.id, event: event);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cartão registrado!')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }
}