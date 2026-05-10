import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/championship_service.dart';
import '../services/match_service.dart';
import '../models/match_event.dart';

class ScoutCardDialog extends StatefulWidget {
  final DocumentSnapshot match;
  final List<DocumentSnapshot> homePlayers;
  final List<DocumentSnapshot> awayPlayers;
  final MatchEventType cardType; 
  final MatchEvent? eventToEdit;

  const ScoutCardDialog({
    super.key,
    required this.match,
    required this.homePlayers,
    required this.awayPlayers,
    required this.cardType,
    this.eventToEdit,
  });

  @override
  State<ScoutCardDialog> createState() => _ScoutCardDialogState();
}

class _ScoutCardDialogState extends State<ScoutCardDialog> {
  String? _selectedTeamId;
  String? _selectedPlayerId; // Único ID
  String? _selectedPlayerName;
  
  final _minuteController = TextEditingController();
  String _selectedPeriod = '1T';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.eventToEdit != null) {
      final e = widget.eventToEdit!;
      _selectedTeamId = e.teamId;
      _selectedPlayerId = e.playerId;
      _selectedPlayerName = e.playerName;
      _minuteController.text = e.minute.toString();
      _selectedPeriod = e.period;
    }
  }

  @override
  Widget build(BuildContext context) {
    final homeId = widget.match['team_home_id'];
    final awayId = widget.match['team_away_id'];
    final homeName = widget.match['team_home_name'];
    final awayName = widget.match['team_away_name'];
    
    final currentType = widget.eventToEdit?.type ?? widget.cardType;
    
    // 🚨 DESIGN INTELIGENTE PARA CADA SCOUT 🚨
    String title;
    Color color;

    switch (currentType) {
      case MatchEventType.redCard:
        title = "CARTÃO VERMELHO";
        color = Colors.red;
        break;
      case MatchEventType.yellowCard:
        title = "CARTÃO AMARELO";
        color = Colors.amber[800]!;
        break;
      case MatchEventType.penaltyMissed:
        title = "PÊNALTI PERDIDO";
        color = Colors.deepPurple;
        break;
      case MatchEventType.penaltySaved:
        title = "PÊNALTI DEFENDIDO";
        color = Colors.teal;
        break;
      case MatchEventType.shotOnPost:
        title = "NA TRAVE";
        color = Colors.brown;
        break;
      default:
        title = "EVENTO";
        color = Colors.blue;
    }

    final bool isEditing = widget.eventToEdit != null;

    List<DocumentSnapshot> activePlayers = [];
    if (_selectedTeamId == homeId) activePlayers = widget.homePlayers;
    else if (_selectedTeamId == awayId) activePlayers = widget.awayPlayers;

    // Ordenação alfabética ou por número
    activePlayers.sort((a,b) {
      final dA = a.data() as Map; final dB = b.data() as Map;
      return (dA['jersey_number']??99).compareTo(dB['jersey_number']??99);
    });

    return AlertDialog(
      title: Text(isEditing ? 'Editar $title' : 'Registrar $title', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. SELEÇÃO DE TIME
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
                if (!isEditing || v != widget.eventToEdit?.teamId) {
                  _selectedPlayerId = null;
                  _selectedPlayerName = null;
                }
              }),
            ),
            const SizedBox(height: 16),
            
            // 2. SELEÇÃO DE JOGADOR (ÚNICO)
            DropdownButtonFormField<String>(
              value: _selectedPlayerId,
              isExpanded: true,
              hint: const Text('Selecione o Atleta'),
              decoration: const InputDecoration(labelText: 'Atleta envolvido', border: OutlineInputBorder()),
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
            
            // 3. TEMPO DE JOGO
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
        TextButton(onPressed: _isSaving ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
          onPressed: _isSaving ? null : _saveCard,
          child: _isSaving 
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
              : Text(isEditing ? 'Atualizar' : 'Confirmar'),
        ),
      ],
    );
  }

  Future<void> _saveCard() async {
    if (_selectedPlayerId == null || _minuteController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preencha todos os campos.')));
      return;
    }

    setState(() => _isSaving = true);

    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    final matchService = Provider.of<MatchService>(context, listen: false);
    
    final int minute = int.tryParse(_minuteController.text) ?? 0;
    final DateTime now = DateTime.now();

    final event = MatchEvent(
      id: widget.eventToEdit?.id ?? '', 
      type: widget.eventToEdit?.type ?? widget.cardType, 
      playerId: _selectedPlayerId!, 
      playerName: _selectedPlayerName ?? 'Atleta', 
      teamId: _selectedTeamId!, 
      minute: minute, 
      period: _selectedPeriod, 
      timestamp: widget.eventToEdit?.timestamp ?? now
    );

    try {
      if (widget.eventToEdit == null) {
        // CREATE
        await matchService.addMatchEvent(seasonId: seasonId, matchId: widget.match.id, event: event);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scout registrado!')));
      } else {
        // UPDATE
        await matchService.updateMatchEvent(
          seasonId: seasonId, 
          matchId: widget.match.id, 
          oldEvent: widget.eventToEdit!, 
          newEvent: event
        );
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scout atualizado!')));
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }
}