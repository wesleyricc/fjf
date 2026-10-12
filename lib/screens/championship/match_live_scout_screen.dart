import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../services/championship_service.dart';
import '../../services/match_service.dart';
import '../../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../../models/match_event.dart';
import '../../models/player_model.dart';
import '../../widgets/scout_timeline_widget.dart';

class MatchLiveScoutScreen extends StatefulWidget {
  final DocumentSnapshot match;
  const MatchLiveScoutScreen({super.key, required this.match});

  @override
  State<MatchLiveScoutScreen> createState() => _MatchLiveScoutScreenState();
}

class _MatchLiveScoutScreenState extends State<MatchLiveScoutScreen> {
  List<DocumentSnapshot> _homePlayers = [];
  List<DocumentSnapshot> _awayPlayers = [];
  bool _isLoadingPlayers = true;

  // --- STATE MACHINE DO WIZARD INVERTIDO ---
  MatchEventType? _activeAction;
  int _wizardStep =
      0; // 0=Inativo, 1=Selec. Autor, 2=Selec. Assist (Gols), 3=Confirmar Tempo
  DocumentSnapshot? _primaryPlayer;
  String? _primaryTeamId;
  DocumentSnapshot? _assistPlayer;
  String? _concededById;
  String? _concededByName;

  final _minuteController = TextEditingController();
  String _selectedPeriod = '1T';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logCustomScreenView('Match_Live_Scout_Screen',
        parameters: {'match_id': widget.match.id});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  Future<void> _loadData() async {
    final service = Provider.of<ChampionshipService>(context, listen: false);
    final data = widget.match.data() as Map<String, dynamic>;
    final homeId = data['team_home_id'];
    final awayId = data['team_away_id'];

    try {
      await Future.wait([
        service.fetchRoster(homeId),
        service.fetchRoster(awayId),
      ]);

      if (!mounted) return;

      final all = service.allPlayers;

      int sortFunc(Player a, Player b) {
        if (!a.isStaff && b.isStaff) return -1;
        if (a.isStaff && !b.isStaff) return 1;
        int nA = a.jerseyNumber ?? 999;
        int nB = b.jerseyNumber ?? 999;
        if (nA != nB) return nA.compareTo(nB);
        return a.name.compareTo(b.name);
      }

      final homeList = all.where((p) => p.teamId == homeId).toList()
        ..sort(sortFunc);
      final awayList = all.where((p) => p.teamId == awayId).toList()
        ..sort(sortFunc);

      setState(() {
        _homePlayers = homeList.map((p) => _mockSnapshot(p)).toList();
        _awayPlayers = awayList.map((p) => _mockSnapshot(p)).toList();
        _isLoadingPlayers = false;
      });
    } catch (e) {
      debugPrint("Erro ao carregar jogadores para Scout: $e");
      if (mounted) setState(() => _isLoadingPlayers = false);
    }
  }

  DocumentSnapshot _mockSnapshot(Player p) {
    return MockDocumentSnapshot(p.id, {
      'name': p.name,
      'jersey_number': p.jerseyNumber,
      'is_staff': p.isStaff,
      'is_goalkeeper': p.isGoalkeeper,
      'team_id': p.teamId,
    });
  }

  // --- LÓGICA DO WIZARD ---

  void _startAction(MatchEventType type) {
    setState(() {
      _activeAction = type;
      _wizardStep = 1;
      _primaryPlayer = null;
      _primaryTeamId = null;
      _assistPlayer = null;
      _concededById = null;
      _concededByName = null;
    });
  }

  void _cancelAction() {
    setState(() {
      _activeAction = null;
      _wizardStep = 0;
    });
  }

  void _onPlayerTapped(DocumentSnapshot p, String teamId) {
    if (_activeAction == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Selecione uma AÇÃO no topo primeiro (ex: Gol, Cartão).'),
        duration: Duration(seconds: 2),
      ));
      return;
    }

    setState(() {
      if (_wizardStep == 1) {
        _primaryPlayer = p;
        _primaryTeamId = teamId;

        // Infere automaticamente o goleiro que sofreu o gol para sugerir
        if (_activeAction == MatchEventType.goal ||
            _activeAction == MatchEventType.ownGoal ||
            _activeAction == MatchEventType.penaltyMissed) {
          final homeId = widget.match['team_home_id'];
          final awayId = widget.match['team_away_id'];
          final targetTeamId = (_activeAction == MatchEventType.ownGoal)
              ? teamId
              : (teamId == homeId ? awayId : homeId);
          final pool = (targetTeamId == homeId) ? _homePlayers : _awayPlayers;
          try {
            final gk = pool
                .firstWhere((p) => (p.data() as Map)['is_goalkeeper'] == true);
            _concededById = gk.id;
            _concededByName = gk['name'];
          } catch (_) {}
        }

        if (_activeAction == MatchEventType.goal) {
          _wizardStep = 2; // Gols pedem assistência
        } else if (_activeAction == MatchEventType.ownGoal ||
            _activeAction == MatchEventType.penaltyMissed) {
          _wizardStep = 3; // Contra ou Pênalti pede goleiro
        } else {
          _wizardStep = 4; // Outros vão para o tempo
        }
      } else if (_wizardStep == 2 && _activeAction == MatchEventType.goal) {
        if (p.id != _primaryPlayer?.id) {
          // Não pode dar assistência pra ele mesmo
          _assistPlayer = p;
        }
        _wizardStep = 3; // Depois da assist, pede o goleiro
      } else if (_wizardStep == 3 &&
          (_activeAction == MatchEventType.goal ||
              _activeAction == MatchEventType.ownGoal ||
              _activeAction == MatchEventType.penaltyMissed)) {
        _concededById = p.id;
        _concededByName = p['name'];
        _wizardStep = 4; // Vai confirmar o tempo
      }
    });
  }

  Future<void> _saveScoutAction() async {
    if (_minuteController.text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Informe o minuto!')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final matchService = Provider.of<MatchService>(context, listen: false);
      final seasonId = Provider.of<ChampionshipService>(context, listen: false)
          .currentSeasonId;
      final int min = int.tryParse(_minuteController.text) ?? 0;
      final now = DateTime.now();

      final ev = MatchEvent(
        id: '',
        type: _activeAction!,
        playerId: _primaryPlayer!.id,
        playerName: _primaryPlayer!['name'],
        teamId: _primaryTeamId!,
        minute: min,
        period: _selectedPeriod,
        timestamp: now,
        concededByPlayerId: _concededById,
      );

      await matchService.addMatchEvent(
          seasonId: seasonId, matchId: widget.match.id, event: ev);

      if (_activeAction == MatchEventType.goal && _assistPlayer != null) {
        final evAssist = MatchEvent(
          id: '',
          type: MatchEventType.assist,
          playerId: _assistPlayer!.id,
          playerName: _assistPlayer!['name'],
          teamId: _primaryTeamId!,
          minute: min,
          period: _selectedPeriod,
          timestamp: now.add(const Duration(milliseconds: 50)),
        );
        await matchService.addMatchEvent(
            seasonId: seasonId, matchId: widget.match.id, event: evAssist);
      }

      if (_activeAction == MatchEventType.penaltyMissed &&
          _concededById != null) {
        final evSaved = MatchEvent(
          id: '',
          type: MatchEventType.penaltySaved,
          playerId: _concededById!,
          playerName: _concededByName ?? 'Goleiro',
          teamId: _primaryTeamId == widget.match['team_home_id']
              ? widget.match['team_away_id']
              : widget.match['team_home_id'],
          minute: min,
          period: _selectedPeriod,
          timestamp: now.add(const Duration(milliseconds: 50)),
        );
        await matchService.addMatchEvent(
            seasonId: seasonId, matchId: widget.match.id, event: evSaved);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Lance registrado rapidamente!'),
            backgroundColor: Colors.green));
        setState(() {
          _activeAction = null;
          _wizardStep = 0;
          // Mantemos o valor de _minuteController para facilitar lançamentos em sequência no mesmo minuto
        });
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // --- BUILDERS DE UI ---

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.white,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 4.0,
        runSpacing: 0.0,
        children: [
          _buildActionTab('GOL', MatchEventType.goal, Colors.green),
          _buildActionTab(
              'AMARELO', MatchEventType.yellowCard, Colors.amber[700]!),
          _buildActionTab('VERMELHO', MatchEventType.redCard, Colors.red),
          _buildActionTab('GOL CONTRA', MatchEventType.ownGoal, Colors.black87),
          _buildActionTab('PÊNALTI PERDIDO', MatchEventType.penaltyMissed,
              Colors.deepPurple),
          _buildActionTab('NA TRAVE', MatchEventType.shotOnPost, Colors.brown),
          _buildActionTab('TIRO LIVRE PERDIDO',
              MatchEventType.directFreeKickMissed, Colors.indigo),
          _buildActionTab('DEFESA DIFÍCIL', MatchEventType.difficultSave, Colors.cyan),
        ],
      ),
    );
  }

  Widget _buildActionTab(String label, MatchEventType type, Color color) {
    final bool isActive = _activeAction == type;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: ChoiceChip(
        label: Text(label,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isActive ? Colors.white : color)),
        selected: isActive,
        selectedColor: color,
        backgroundColor: color.withOpacity(0.1),
        onSelected: (selected) {
          if (selected)
            _startAction(type);
          else
            _cancelAction();
        },
      ),
    );
  }

  Widget _buildWizardBanner() {
    if (_activeAction == null) return const SizedBox.shrink();

    String title = '';
    Color color = Colors.blue;
    if (_activeAction == MatchEventType.goal) {
      title = '⚽ GOL';
      color = Colors.green;
    } else if (_activeAction == MatchEventType.yellowCard) {
      title = '🟨 AMARELO';
      color = Colors.amber[800]!;
    } else if (_activeAction == MatchEventType.redCard) {
      title = '🟥 VERMELHO';
      color = Colors.red;
    } else if (_activeAction == MatchEventType.ownGoal) {
      title = '⚽ CONTRA';
      color = Colors.black87;
    } else if (_activeAction == MatchEventType.penaltyMissed) {
      title = '🎯 PÊNALTI';
      color = Colors.deepPurple;
    } else if (_activeAction == MatchEventType.shotOnPost) {
      title = '🥅 NA TRAVE';
      color = Colors.brown;
    } else if (_activeAction == MatchEventType.directFreeKickMissed) {
      title = '🚫 TL PERDIDO';
      color = Colors.indigo;
    } else if (_activeAction == MatchEventType.difficultSave) {
      title = '🖐️ DEFESA DIFÍCIL';
      color = Colors.cyan;
    } else {
      title = '🎯 AÇÃO';
      color = Colors.purple;
    }

    if (_wizardStep == 1) {
      return Container(
          width: double.infinity,
          color: color,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Expanded(
                  child: Text('1. Toque no Jogador abaixo',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16))),
              IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: _cancelAction)
            ],
          ));
    } else if (_wizardStep == 2) {
      return Container(
          width: double.infinity,
          color: color,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Expanded(
                  child: Text('2. Quem deu Assistência?',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16))),
              ElevatedButton(
                onPressed: () => setState(() => _wizardStep = 3),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white, foregroundColor: color),
                child: const Text('Ninguém (Pular)'),
              )
            ],
          ));
    } else if (_wizardStep == 3) {
      bool isPenalty = _activeAction == MatchEventType.penaltyMissed;
      String stepTitle =
          isPenalty ? '3. O Goleiro Defendeu?' : '3. Quem sofreu o Gol?';
      String skipBtn = isPenalty
          ? 'Não (Na trave/Fora)'
          : (_concededByName != null
              ? 'Pular ($_concededByName)'
              : 'Pular (Autodetectar)');

      return Container(
          width: double.infinity,
          color: color,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                  child: Text(stepTitle,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16))),
              ElevatedButton(
                onPressed: () => setState(() {
                  if (isPenalty) {
                    _concededById = null;
                    _concededByName = null;
                  }
                  _wizardStep = 4;
                }),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white, foregroundColor: color),
                child: Text(skipBtn),
              )
            ],
          ));
    } else if (_wizardStep == 4) {
      return Container(
          color: color,
          padding: const EdgeInsets.all(12),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                          'Confirmar $title de ${_primaryPlayer?['name']}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15),
                          overflow: TextOverflow.ellipsis),
                    ),
                    IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: _cancelAction,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints())
                  ],
                ),
                if (_assistPlayer != null)
                  Text('Assistência: ${_assistPlayer?['name']}',
                      style: const TextStyle(color: Colors.white70)),
                if (_concededByName != null &&
                    (_activeAction == MatchEventType.goal ||
                        _activeAction == MatchEventType.ownGoal))
                  Text('Sofrido por: $_concededByName',
                      style: const TextStyle(color: Colors.white70)),
                if (_concededByName != null &&
                    _activeAction == MatchEventType.penaltyMissed)
                  Text('Defendido por: $_concededByName',
                      style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: TextField(
                    controller: _minuteController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        hintText: 'Min.',
                        fillColor: Colors.white,
                        filled: true,
                        isDense: true,
                        border: OutlineInputBorder()),
                  )),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    dropdownColor: color,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                    value: _selectedPeriod,
                    items: const [
                      DropdownMenuItem(value: '1T', child: Text('1º T')),
                      DropdownMenuItem(value: '2T', child: Text('2º T'))
                    ],
                    onChanged: (v) => setState(() => _selectedPeriod = v!),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: color),
                      onPressed: _isSaving ? null : _saveScoutAction,
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator())
                          : const Text('SALVAR'))
                ])
              ]));
    }

    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final seasonId = Provider.of<ChampionshipService>(context).currentSeasonId;
    final matchRef = FirebaseFirestore.instance
        .collection('championships')
        .doc(seasonId)
        .collection('matches')
        .doc(widget.match.id);

    return Scaffold(
      appBar: AppBar(title: const Text('Live Scout Rápido')),
      body: _isLoadingPlayers
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                StreamBuilder<DocumentSnapshot>(
                    stream: matchRef.snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || !snapshot.data!.exists)
                        return const SizedBox.shrink();
                      final data =
                          snapshot.data!.data() as Map<String, dynamic>;

                      return Container(
                        color: Colors.grey[200],
                        padding: const EdgeInsets.symmetric(
                            vertical: 20, horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Expanded(
                                child: Text(data['team_home_name'] ?? 'Casa',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16))),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Text(
                                  "${data['score_home'] ?? 0} x ${data['score_away'] ?? 0}",
                                  style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w900)),
                            ),
                            Expanded(
                                child: Text(data['team_away_name'] ?? 'Fora',
                                    textAlign: TextAlign.left,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16))),
                          ],
                        ),
                      );
                    }),

                // BARRA DE AÇÕES (TOPO)
                _buildActionBar(),

                // BANNER DE ASSISTENTE (WIZARD)
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  child: _buildWizardBanner(),
                ),

                Expanded(
                  flex: 3,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Casa
                      Expanded(
                        child: Column(
                          children: [
                            Container(
                              width: double.infinity,
                              color: Colors.blue[50],
                              padding: const EdgeInsets.all(4),
                              child: const Text('CASA',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue)),
                            ),
                            Expanded(
                              child: ListView.builder(
                                  itemCount: _homePlayers.length,
                                  itemBuilder: (ctx, i) => _buildPlayerTile(
                                      _homePlayers[i],
                                      widget.match['team_home_id'])),
                            )
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1, color: Colors.grey),
                      // Fora
                      Expanded(
                        child: Column(
                          children: [
                            Container(
                              width: double.infinity,
                              color: Colors.red[50],
                              padding: const EdgeInsets.all(4),
                              child: const Text('VISITANTE',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red)),
                            ),
                            Expanded(
                              child: ListView.builder(
                                  itemCount: _awayPlayers.length,
                                  itemBuilder: (ctx, i) => _buildPlayerTile(
                                      _awayPlayers[i],
                                      widget.match['team_away_id'])),
                            )
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(thickness: 4, color: Colors.black12, height: 4),
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text("TIMELINE DO JOGO",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          letterSpacing: 1.2)),
                ),

                Expanded(
                  flex: 2,
                  child: ScoutTimelineWidget(
                    match: widget.match,
                    homePlayers: _homePlayers,
                    awayPlayers: _awayPlayers,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPlayerTile(DocumentSnapshot p, String teamId) {
    final isSelected = (p.id == _primaryPlayer?.id ||
        p.id == _assistPlayer?.id ||
        p.id == _concededById);

    return InkWell(
      onTap: () => _onPlayerTapped(p, teamId),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
            color: isSelected ? Colors.yellow[100] : null,
            border: const Border(
                bottom: BorderSide(color: Colors.black12, width: 0.5))),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: isSelected ? Colors.amber : Colors.grey[300],
              child: Text('${p['jersey_number'] ?? '-'}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black)),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: Text(p['name'],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal))),
          ],
        ),
      ),
    );
  }
}

class MockDocumentSnapshot implements DocumentSnapshot {
  @override
  final String id;
  final Map<String, dynamic> _data;
  MockDocumentSnapshot(this.id, this._data);
  @override
  Map<String, dynamic> data() => _data;
  @override
  dynamic get(Object field) => _data[field as String];
  @override
  dynamic operator [](Object field) => _data[field as String];
  @override
  bool get exists => true;
  @override
  DocumentReference get reference => throw UnimplementedError();
  @override
  SnapshotMetadata get metadata => throw UnimplementedError();
}
