import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/championship_service.dart';
import '../services/match_service.dart'; 
import '../models/match_event.dart';

class ScoutGoalDialog extends StatefulWidget {
  final DocumentSnapshot match;
  final List<DocumentSnapshot> homePlayers;
  final List<DocumentSnapshot> awayPlayers;
  final MatchEvent? eventToEdit;
  final MatchEvent? linkedAssistEvent; // Assistência vinculada (vinda da Timeline)
  final String? preSelectedTeamId;
  final String? preSelectedPlayerId;

  const ScoutGoalDialog({
    super.key,
    required this.match,
    required this.homePlayers,
    required this.awayPlayers,
    this.eventToEdit,
    this.linkedAssistEvent,
    this.preSelectedTeamId,
    this.preSelectedPlayerId,
  });

  @override
  State<ScoutGoalDialog> createState() => _ScoutGoalDialogState();
}

class _ScoutGoalDialogState extends State<ScoutGoalDialog> {
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
  void initState() {
    super.initState();
    // Preenchimento se for edição
    if (widget.eventToEdit != null) {
      final e = widget.eventToEdit!;
      _selectedTeamId = e.teamId;
      _scorerId = e.playerId;
      _scorerName = e.playerName;
      _concededById = e.concededByPlayerId;
      _minuteController.text = e.minute.toString();
      _selectedPeriod = e.period;
      
      // Se tivermos encontrado uma assistência vinculada na timeline
      if (widget.linkedAssistEvent != null) {
        _assistId = widget.linkedAssistEvent!.playerId;
        _assistName = widget.linkedAssistEvent!.playerName;
      }
    } else {
      if (widget.preSelectedTeamId != null) _selectedTeamId = widget.preSelectedTeamId;
      if (widget.preSelectedPlayerId != null) {
        _scorerId = widget.preSelectedPlayerId;
        final playersList = _selectedTeamId == widget.match['team_home_id'] ? widget.homePlayers : widget.awayPlayers;
        final doc = playersList.where((d) => d.id == _scorerId).firstOrNull;
        if (doc != null) {
          final data = doc.data() as Map<String, dynamic>;
          _scorerName = data['name'];
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final homeId = widget.match['team_home_id'];
    final awayId = widget.match['team_away_id'];
    final homeName = widget.match['team_home_name'];
    final awayName = widget.match['team_away_name'];

    List<DocumentSnapshot> scoringTeamPlayers = [];
    List<DocumentSnapshot> opposingTeamPlayers = [];

    if (_selectedTeamId == homeId) {
      scoringTeamPlayers = widget.homePlayers;
      opposingTeamPlayers = widget.awayPlayers;
    } else if (_selectedTeamId == awayId) {
      scoringTeamPlayers = widget.awayPlayers;
      opposingTeamPlayers = widget.homePlayers;
    }

    // Filtra apenas jogadores de linha/goleiros (remove Staff)
    final scoringCandidates = scoringTeamPlayers.where((doc) {
       final data = doc.data() as Map<String, dynamic>;
       return data['is_staff'] != true;
    }).toList();

    // Ordena por número da camisa
    scoringCandidates.sort((a,b) {
      final dA = a.data() as Map; final dB = b.data() as Map;
      return (dA['jersey_number']??99).compareTo(dB['jersey_number']??99);
    });

    // Lista de candidatos a assistência (exclui o autor do gol)
    final assistCandidates = (_scorerId != null) 
        ? scoringCandidates.where((doc) => doc.id != _scorerId).toList()
        : [];

    return AlertDialog(
      title: Text(widget.eventToEdit == null ? 'Registrar Gol' : 'Editar Gol'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. TIME
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
                  // Se mudou o time e não é o mesmo da edição original, reseta campos
                  if (v != widget.eventToEdit?.teamId) {
                    _scorerId = null;
                    _assistId = null;
                    _concededById = null;
                    
                    // Tenta auto-selecionar o goleiro adversário
                    final opponents = (v == homeId) ? widget.awayPlayers : widget.homePlayers;
                    try {
                      final gk = opponents.firstWhere((p) => (p.data() as Map)['is_goalkeeper'] == true);
                      _concededById = gk.id;
                    } catch (_) {}
                  }
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
                   // Se o autor do gol for o mesmo da assistência selecionada, limpa a assistência
                   if (_assistId == v) _assistId = null;
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

            // 4. GOL SOFRIDO (GOLEIRO)
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
              : Text(widget.eventToEdit == null ? 'CONFIRMAR' : 'ATUALIZAR'),
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
      final matchService = Provider.of<MatchService>(context, listen: false);
      
      final int minute = int.tryParse(_minuteController.text) ?? 0;
      final DateTime now = DateTime.now();

      // --- 1. OBJETO DO GOL ---
      final newGoalEvent = MatchEvent(
        id: widget.eventToEdit?.id ?? '', // Se ID vazio, o service cria um novo
        type: MatchEventType.goal,
        playerId: _scorerId!,
        playerName: _scorerName ?? 'Atleta',
        teamId: _selectedTeamId!,
        minute: minute,
        period: _selectedPeriod,
        timestamp: widget.eventToEdit?.timestamp ?? now,
        concededByPlayerId: _concededById, 
      );

      // --- 2. OBJETO DA ASSISTÊNCIA (SE HOUVER) ---
      MatchEvent? newAssistEvent;
      if (_assistId != null) {
        newAssistEvent = MatchEvent(
          id: widget.linkedAssistEvent?.id ?? '', // Se ID vazio, cria novo
          type: MatchEventType.assist,
          playerId: _assistId!,
          playerName: _assistName ?? 'Atleta',
          teamId: _selectedTeamId!,
          minute: minute,
          period: _selectedPeriod,
          // Pequeno ajuste no timestamp para garantir ordem correta se criado junto
          timestamp: widget.linkedAssistEvent?.timestamp ?? now.add(const Duration(milliseconds: 50)),
        );
      }

      // --- 3. EXECUÇÃO NO SERVIÇO ---
      
      // Cenário A: Novo Registro
      if (widget.eventToEdit == null) {
        // Salva o Gol
        await matchService.addMatchEvent(seasonId: seasonId, matchId: widget.match.id, event: newGoalEvent);
        
        // Salva a Assistência (se existir)
        if (newAssistEvent != null) {
          await matchService.addMatchEvent(seasonId: seasonId, matchId: widget.match.id, event: newAssistEvent);
        }
        
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gol registrado!')));
      } 
      
      // Cenário B: Edição
      else {
        // Atualiza o Gol
        await matchService.updateMatchEvent(
          seasonId: seasonId, 
          matchId: widget.match.id, 
          oldEvent: widget.eventToEdit!, 
          newEvent: newGoalEvent
        );

        // Gerencia Assistência
        if (newAssistEvent != null) {
          if (widget.linkedAssistEvent != null) {
            // Caso 1: Já tinha e continua tendo (Update)
            await matchService.updateMatchEvent(
              seasonId: seasonId, 
              matchId: widget.match.id, 
              oldEvent: widget.linkedAssistEvent!, 
              newEvent: newAssistEvent
            );
          } else {
            // Caso 2: Não tinha e agora tem (Add)
            await matchService.addMatchEvent(seasonId: seasonId, matchId: widget.match.id, event: newAssistEvent);
          }
        } else {
          // Caso 3: Tinha e removeu (Delete)
          if (widget.linkedAssistEvent != null) {
            await matchService.deleteMatchEvent(
              seasonId: seasonId, 
              matchId: widget.match.id, 
              event: widget.linkedAssistEvent!
            );
          }
        }
        
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lance atualizado!')));
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