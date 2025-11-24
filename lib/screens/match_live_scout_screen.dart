import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
// import 'package:intl/intl.dart';
import '../services/championship_service.dart';
import '../services/firestore_service.dart';
import '../services/admin_service.dart'; 
import '../models/match_event.dart';

class MatchLiveScoutScreen extends StatefulWidget {
  final DocumentSnapshot match;
  const MatchLiveScoutScreen({super.key, required this.match});

  @override
  State<MatchLiveScoutScreen> createState() => _MatchLiveScoutScreenState();
}

class _MatchLiveScoutScreenState extends State<MatchLiveScoutScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  
  List<DocumentSnapshot> _homePlayers = [];
  List<DocumentSnapshot> _awayPlayers = [];
  bool _isLoadingPlayers = true;

  @override
  void initState() {
    super.initState();
    _fetchPlayers();
  }

  Future<void> _fetchPlayers() async {
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    final homeId = widget.match['team_home_id'];
    final awayId = widget.match['team_away_id'];
    
    Query playersQuery;
    if (seasonId == FirestoreService.LEGACY_ID) {
      playersQuery = FirebaseFirestore.instance.collection('players');
    } else {
      playersQuery = FirebaseFirestore.instance.collection('championships').doc(seasonId).collection('player_stats');
    }

    final homeSnap = await playersQuery.where('team_id', isEqualTo: homeId).where('isActive', isEqualTo: true).get();
    final awaySnap = await playersQuery.where('team_id', isEqualTo: awayId).where('isActive', isEqualTo: true).get();

    // --- LÓGICA DE ORDENAÇÃO ---
    List<DocumentSnapshot> sortPlayers(List<DocumentSnapshot> list) {
      list.sort((a, b) {
        final da = a.data() as Map<String, dynamic>;
        final db = b.data() as Map<String, dynamic>;

        // 1. Staff vai para o final
        final bool isStaffA = da['is_staff'] ?? false;
        final bool isStaffB = db['is_staff'] ?? false;
        if (!isStaffA && isStaffB) return -1;
        if (isStaffA && !isStaffB) return 1;

        // 2. Ordena por Número da Camisa (Crescente)
        final int numA = da['jersey_number'] ?? 999;
        final int numB = db['jersey_number'] ?? 999;
        int numComp = numA.compareTo(numB);
        if (numComp != 0) return numComp;

        // 3. Desempate por Nome
        return (da['name'] ?? '').toString().compareTo((db['name'] ?? '').toString());
      });
      return list;
    }
    // ---------------------------

    if(mounted) {
      setState(() {
        _homePlayers = sortPlayers(homeSnap.docs);
        _awayPlayers = sortPlayers(awaySnap.docs);
        _isLoadingPlayers = false;
      });
    }
  }

  Future<void> _showGoalWizard() async {
    String? selectedTeamId;
    String? scorerId;
    String? scorerName;
    String? assistId;
    String? assistName;
    String? concededById;
    
    final minuteController = TextEditingController();
    String selectedPeriod = '1T';

    final homeId = widget.match['team_home_id'];
    final awayId = widget.match['team_away_id'];
    final homeName = widget.match['team_home_name'];
    final awayName = widget.match['team_away_name'];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          List<DocumentSnapshot> scoringTeamPlayers = [];
          List<DocumentSnapshot> opposingTeamPlayers = [];

          if (selectedTeamId == homeId) {
            scoringTeamPlayers = _homePlayers;
            opposingTeamPlayers = _awayPlayers;
          } else if (selectedTeamId == awayId) {
            scoringTeamPlayers = _awayPlayers;
            opposingTeamPlayers = _homePlayers;
          }

          // --- FILTRO DE COMISSÃO TÉCNICA (Staff não faz gol) ---
          final scoringCandidates = scoringTeamPlayers.where((doc) {
             final data = doc.data() as Map<String, dynamic>;
             return data['is_staff'] != true;
          }).toList();
          // ------------------------------------------------------

          // Filtra possíveis assistentes (remove autor do gol)
          List<DocumentSnapshot> assistCandidates = [];
          if (scorerId != null) {
            assistCandidates = scoringCandidates.where((doc) => doc.id != scorerId).toList();
          }

          return AlertDialog(
            title: const Text('Registrar Gol'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // TIME QUE FEZ O GOL
                  DropdownButtonFormField<String>(
                    value: selectedTeamId,
                    isExpanded: true, // Evita overflow no nome do time
                    hint: const Text('Equipe que marcou'),
                    decoration: const InputDecoration(labelText: 'Time do Gol', border: OutlineInputBorder()),
                    items: [
                      DropdownMenuItem(value: homeId, child: Text(homeName, overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: awayId, child: Text(awayName, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) {
                      setDialogState(() {
                        selectedTeamId = v;
                        scorerId = null;
                        assistId = null;
                        concededById = null;
                        
                        // Prepara lista adversária para buscar goleiro
                        if (v == homeId) opposingTeamPlayers = _awayPlayers;
                        else opposingTeamPlayers = _homePlayers;
                        
                        // Tenta pré-selecionar goleiro adversário
                        try {
                          // Aqui mantemos o staff na lista 'opposingTeamPlayers' apenas para garantir,
                          // mas o filtro de goleiro abaixo já deve pegar o certo.
                          final gk = opposingTeamPlayers.firstWhere((p) => p['is_goalkeeper'] == true);
                          concededById = gk.id;
                        } catch (_) {}
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // AUTOR DO GOL
                  DropdownButtonFormField<String>(
                    value: scorerId,
                    isExpanded: true, // --- CORREÇÃO DE OVERFLOW ---
                    hint: const Text('Quem fez o gol?'),
                    decoration: const InputDecoration(labelText: 'Autor do Gol', border: OutlineInputBorder()),
                    // Usa a lista filtrada (sem staff)
                    items: scoringCandidates.map((p) {
                      final d = p.data() as Map<String, dynamic>;
                      return DropdownMenuItem(
                        value: p.id,
                        child: Text("${d['jersey_number'] ?? '-'} ${d['name']}", overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: selectedTeamId == null ? null : (v) {
                       final p = scoringCandidates.firstWhere((doc) => doc.id == v);
                       scorerName = p['name'];
                       setDialogState(() {
                         scorerId = v;
                         assistId = null;
                       });
                    },
                  ),
                  const SizedBox(height: 16),

                  // ASSISTÊNCIA
                  DropdownButtonFormField<String>(
                    value: assistId,
                    isExpanded: true, // --- CORREÇÃO DE OVERFLOW ---
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
                    onChanged: scorerId == null ? null : (v) {
                       if (v != null) {
                         final p = assistCandidates.firstWhere((doc) => doc.id == v);
                         assistName = p['name'];
                       }
                       setDialogState(() => assistId = v);
                    },
                  ),
                  const SizedBox(height: 16),

                  // GOLEIRO (GOL SOFRIDO)
                  DropdownButtonFormField<String>(
                    value: concededById,
                    isExpanded: true, // --- CORREÇÃO DE OVERFLOW ---
                    decoration: const InputDecoration(labelText: 'Goleiro Adversário (Gol Sofrido)', border: OutlineInputBorder()),
                    // Aqui filtramos Staff também, pois treinador não toma gol (geralmente)
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
                             Expanded(
                               child: Text(
                                 "${d['jersey_number'] ?? '-'} ${d['name']}",
                                 overflow: TextOverflow.ellipsis,
                               ),
                             ),
                          ])
                        );
                    }).toList(),
                    onChanged: selectedTeamId == null ? null : (v) => setDialogState(() => concededById = v),
                  ),
                  const SizedBox(height: 16),

                  // TEMPO
                  Row(
                    children: [
                      Expanded(child: TextFormField(controller: minuteController, decoration: const InputDecoration(labelText: 'Minuto', border: OutlineInputBorder()), keyboardType: TextInputType.number)),
                      const SizedBox(width: 10),
                      Expanded(child: DropdownButtonFormField<String>(value: selectedPeriod, items: const [DropdownMenuItem(value: '1T', child: Text('1º T')), DropdownMenuItem(value: '2T', child: Text('2º T'))], onChanged: (v) => setDialogState(() => selectedPeriod = v!), decoration: const InputDecoration(border: OutlineInputBorder()))),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                onPressed: () async {
                  if (selectedTeamId == null || scorerId == null || minuteController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preencha os dados obrigatórios.')));
                    return;
                  }
                  
                  final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
                  final int minute = int.tryParse(minuteController.text) ?? 0;
                  final DateTime now = DateTime.now();

                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registrando...')));

                  // 1. Evento GOL
                  final goalEvent = MatchEvent(
                    id: '', 
                    type: MatchEventType.goal,
                    playerId: scorerId!,
                    playerName: scorerName ?? 'Atleta',
                    teamId: selectedTeamId!,
                    minute: minute,
                    period: selectedPeriod,
                    timestamp: now,
                    concededByPlayerId: concededById, 
                  );

                  await _firestoreService.addMatchEvent(seasonId: seasonId, matchId: widget.match.id, event: goalEvent);

                  // 2. Evento ASSISTÊNCIA
                  if (assistId != null) {
                    final assistEvent = MatchEvent(
                      id: '',
                      type: MatchEventType.assist,
                      playerId: assistId!,
                      playerName: assistName ?? 'Atleta',
                      teamId: selectedTeamId!,
                      minute: minute,
                      period: selectedPeriod,
                      timestamp: now.add(const Duration(milliseconds: 100)),
                    );
                    await _firestoreService.addMatchEvent(seasonId: seasonId, matchId: widget.match.id, event: assistEvent);
                  }
                },
                child: const Text('CONFIRMAR'),
              ),
            ],
          );
        }
      ),
    );
  }

  Future<void> _showCardWizard(MatchEventType type) async {
    String? selectedTeamId;
    String? selectedPlayerId;
    String? selectedPlayerName;
    final minuteController = TextEditingController();
    String selectedPeriod = '1T';

    final homeId = widget.match['team_home_id'];
    final awayId = widget.match['team_away_id'];
    final homeName = widget.match['team_home_name'];
    final awayName = widget.match['team_away_name'];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          List<DocumentSnapshot> activePlayers = [];
          if (selectedTeamId == homeId) activePlayers = _homePlayers;
          if (selectedTeamId == awayId) activePlayers = _awayPlayers;
          // Nota: Para cartões, NÃO filtramos staff (Comissão técnica pode tomar cartão)

          return AlertDialog(
            title: Text('Novo: ${type == MatchEventType.yellowCard ? "CARTÃO AMARELO" : "CARTÃO VERMELHO"}', style: TextStyle(color: type == MatchEventType.redCard ? Colors.red : Colors.orange[800])),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedTeamId,
                    isExpanded: true, // --- CORREÇÃO OVERFLOW ---
                    hint: const Text('Selecione a Equipe'),
                    decoration: const InputDecoration(labelText: 'Equipe', border: OutlineInputBorder()),
                    items: [
                      DropdownMenuItem(value: homeId, child: Text(homeName, overflow: TextOverflow.ellipsis)),
                      DropdownMenuItem(value: awayId, child: Text(awayName, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setDialogState(() { selectedTeamId = v; selectedPlayerId = null; }),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedPlayerId,
                    isExpanded: true, // --- CORREÇÃO OVERFLOW ---
                    hint: const Text('Selecione o Atleta'),
                    decoration: const InputDecoration(labelText: 'Atleta', border: OutlineInputBorder()),
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
                    onChanged: selectedTeamId == null ? null : (v) {
                       final p = activePlayers.firstWhere((doc) => doc.id == v);
                       selectedPlayerName = p['name'];
                       setDialogState(() => selectedPlayerId = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: TextFormField(controller: minuteController, decoration: const InputDecoration(labelText: 'Minuto', border: OutlineInputBorder()), keyboardType: TextInputType.number)),
                      const SizedBox(width: 10),
                      Expanded(child: DropdownButtonFormField<String>(value: selectedPeriod, items: const [DropdownMenuItem(value: '1T', child: Text('1º T')), DropdownMenuItem(value: '2T', child: Text('2º T'))], onChanged: (v) => setDialogState(() => selectedPeriod = v!), decoration: const InputDecoration(border: OutlineInputBorder()))),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: type == MatchEventType.redCard ? Colors.red : Colors.amber[800], foregroundColor: Colors.white),
                onPressed: () async {
                  if (selectedPlayerId == null || minuteController.text.isEmpty) return;
                  final event = MatchEvent(id: '', type: type, playerId: selectedPlayerId!, playerName: selectedPlayerName ?? 'Atleta', teamId: selectedTeamId!, minute: int.tryParse(minuteController.text) ?? 0, period: selectedPeriod, timestamp: DateTime.now());
                  final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registrando Cartão...')));
                  await _firestoreService.addMatchEvent(seasonId: seasonId, matchId: widget.match.id, event: event);
                },
                child: const Text('Confirmar'),
              ),
            ],
          );
        }
      ),
    );
  }

  Widget _buildActionButton(String label, Color color, IconData icon, MatchEventType type) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: color, 
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          icon: Icon(icon, size: 18),
          label: Text(label),
          onPressed: () => _buildActionPressed(type),
        ),
      ),
    );
  }
  
  void _buildActionPressed(MatchEventType type) {
    if (type == MatchEventType.goal || type == MatchEventType.assist) {
      // Como unificamos, o botão de Goal chama o wizard completo
      // O botão de Assist pode ser redundante agora, ou abrir o mesmo wizard já com foco na assist (opcional)
      _showGoalWizard();
    } else {
      _showCardWizard(type);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seasonId = Provider.of<ChampionshipService>(context).currentSeasonId;
    final matchRef = seasonId == FirestoreService.LEGACY_ID 
        ? FirebaseFirestore.instance.collection('matches').doc(widget.match.id)
        : FirebaseFirestore.instance.collection('championships').doc(seasonId).collection('matches').doc(widget.match.id);

    return Scaffold(
      appBar: AppBar(title: const Text('Assistente de Súmula')),
      body: Column(
        children: [
          StreamBuilder<DocumentSnapshot>(
            stream: matchRef.snapshots(),
            builder: (context, snapshot) {
              if(!snapshot.hasData) return const SizedBox.shrink();
              final data = snapshot.data!.data() as Map<String, dynamic>;
              return Container(
                color: Colors.grey[200],
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(child: Text(data['team_home_name'], textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text("${data['score_home'] ?? 0} x ${data['score_away'] ?? 0}", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                    ),
                    Expanded(child: Text(data['team_away_name'], textAlign: TextAlign.left, style: const TextStyle(fontWeight: FontWeight.bold))),
                  ],
                ),
              );
            }
          ),

          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    icon: const Icon(Icons.sports_soccer, size: 30),
                    label: const Text('REGISTRAR GOL', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    onPressed: _showGoalWizard,
                  ),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  _buildActionButton('AMARELO', Colors.amber[700]!, Icons.style, MatchEventType.yellowCard),
                  _buildActionButton('VERMELHO', Colors.red, Icons.style, MatchEventType.redCard),
                ]),
              ],
            ),
          ),
          
          const Divider(thickness: 2),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text("LOG DO JOGO (TIMELINE)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: matchRef.collection('timeline').orderBy('timestamp', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final events = snapshot.data!.docs;
                if (events.isEmpty) return const Center(child: Text("Nenhum evento registrado.", style: TextStyle(color: Colors.grey)));

                return ListView.builder(
                  itemCount: events.length,
                  itemBuilder: (ctx, index) {
                    final doc = events[index];
                    final evt = MatchEvent.fromMap(doc.id, doc.data() as Map<String, dynamic>);
                    
                    IconData icon; Color color;
                    switch(evt.type) {
                      case MatchEventType.goal: icon=Icons.sports_soccer; color=Colors.green; break;
                      case MatchEventType.yellowCard: icon=Icons.style; color=Colors.amber; break;
                      case MatchEventType.redCard: icon=Icons.style; color=Colors.red; break;
                      default: icon=Icons.assistant; color=Colors.blue;
                    }

                    String displayTitle = "${evt.minute}' ${evt.period} - ${evt.type.name.toUpperCase().replaceAll('GOAL','GOL').replaceAll('YELLOWCARD','AMARELO').replaceAll('REDCARD','VERMELHO').replaceAll('ASSIST','ASSISTÊNCIA')}";
                    if (evt.type == MatchEventType.goal && evt.concededByPlayerId != null) {
                      displayTitle += " (GS)";
                    }

                    return ListTile(
                      leading: CircleAvatar(backgroundColor: color.withOpacity(0.2), child: Icon(icon, color: color, size: 20)),
                      title: Text(displayTitle),
                      subtitle: Text("${evt.playerName} (${evt.teamId == widget.match['team_home_id'] ? widget.match['team_home_name'] : widget.match['team_away_name']})"),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () async {
                           final confirm = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: const Text("Desfazer?"), content: const Text("Isso reverterá o placar e as estatísticas."), actions: [TextButton(onPressed: ()=>Navigator.pop(c,true), child: const Text("Sim"))]));
                           if (confirm == true) {
                             await _firestoreService.deleteMatchEvent(seasonId: seasonId, matchId: widget.match.id, event: evt);
                           }
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}