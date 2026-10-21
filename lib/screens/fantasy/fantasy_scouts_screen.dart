import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/fantasy_service.dart';
import '../../services/fantasy_scout_service.dart';
import '../../services/championship_service.dart';
import '../../repositories/fantasy_repository.dart';
import '../../models/fantasy_models.dart';
import '../../models/team_model.dart';
import '../../widgets/fantasy/fantasy_bottom_nav_bar.dart';
import '../../widgets/fantasy/fantasy_live_athletes_view.dart';
import '../../widgets/ui/optimized_network_image.dart';

class FantasyScoutsScreen extends StatefulWidget {
  final int initialTabIndex;

  const FantasyScoutsScreen({super.key, this.initialTabIndex = 0});

  @override
  State<FantasyScoutsScreen> createState() => _FantasyScoutsScreenState();
}

class _FantasyScoutsScreenState extends State<FantasyScoutsScreen> {
  final FantasyService _fantasyService = FantasyService();
  final FantasyRepository _fantasyRepo = FantasyRepository();
  final FantasyScoutService _scoutService = FantasyScoutService();

  int? _selectedDreamTeamRound;
  int? _selectedMostSelectedRound;
  List<FantasyPlayer> _allPlayers = [];
  Map<String, Team> _teamsMap = {};
  bool _isLoadingBaseData = true;

  @override
  void initState() {
    super.initState();
    _loadBaseData();
  }

  Future<void> _loadBaseData() async {
    try {
      final players = await _fantasyRepo.getAllPlayers();
      if (mounted) {
        final champ = Provider.of<ChampionshipService>(context, listen: false);
        setState(() {
          _allPlayers = players;
          _teamsMap = {for (var t in champ.teams) t.id: t};
          _isLoadingBaseData = false;
        });
      }
    } catch (e) {
      debugPrint("Erro ao carregar dados base de scouts: $e");
      if (mounted) {
        setState(() => _isLoadingBaseData = false);
      }
    }
  }

  Color _getPositionColor(String? pos) {
    final lower = (pos ?? '').toLowerCase();
    if (lower.contains('gol')) return Colors.amber.shade800;
    if (lower.contains('fix')) return Colors.blue.shade700;
    if (lower.contains('ala')) return Colors.purple.shade700;
    if (lower.contains('piv')) return Colors.red.shade700;
    if (lower.contains('téc') || lower.contains('tec')) return Colors.teal.shade700;
    return Colors.grey.shade700;
  }

  List<Map<String, dynamic>> _computeLiveDreamTeam({
    required Map<String, FantasyScoutDetail> scores,
    required List<FantasyPlayer> players,
    required Map<String, Team> teamsMap,
  }) {
    if (scores.isEmpty || players.isEmpty) return [];

    final Map<String, List<Map<String, dynamic>>> byPos = {
      'Goleiro': [],
      'Fixo': [],
      'Ala': [],
      'Pivô': [],
      'Técnico': [],
    };

    for (final player in players) {
      final scout = scores[player.playerId];
      if (scout == null || (!scout.hasStats && scout.totalScore == 0)) {
        continue;
      }

      final pos = player.position;
      final team = teamsMap[player.teamId];

      final item = {
        'player_id': player.playerId,
        'name': player.name,
        'position': pos,
        'photo_url': player.photoUrl,
        'team_shield_url': team?.shieldUrl ?? '',
        'team_name': team?.name ?? '',
        'score': scout.totalScore,
        'round_score': scout.totalScore,
      };

      final lower = pos.toLowerCase();
      if (lower.contains('gol')) {
        byPos['Goleiro']!.add(item);
      } else if (lower.contains('fix')) {
        byPos['Fixo']!.add(item);
      } else if (lower.contains('ala')) {
        byPos['Ala']!.add(item);
      } else if (lower.contains('piv')) {
        byPos['Pivô']!.add(item);
      } else if (lower.contains('téc') || lower.contains('tec')) {
        byPos['Técnico']!.add(item);
      }
    }

    for (final key in byPos.keys) {
      byPos[key]!.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));
    }

    final List<Map<String, dynamic>> dreamTeam = [];

    // Formação FJF: 1 Goleiro, 1 Fixo, 2 Alas, 1 Pivô, 1 Técnico
    if (byPos['Goleiro']!.isNotEmpty) {
      dreamTeam.add(byPos['Goleiro']!.first);
    }
    if (byPos['Fixo']!.isNotEmpty) {
      dreamTeam.add(byPos['Fixo']!.first);
    }
    if (byPos['Ala']!.isNotEmpty) {
      dreamTeam.addAll(byPos['Ala']!.take(2));
    }
    if (byPos['Pivô']!.isNotEmpty) {
      dreamTeam.add(byPos['Pivô']!.first);
    }
    if (byPos['Técnico']!.isNotEmpty) {
      dreamTeam.add(byPos['Técnico']!.first);
    }

    return dreamTeam;
  }

  Widget _buildRoundSelectorBar({
    required int selectedRound,
    required int currentRound,
    required bool isMarketOpen,
    required bool isScoutsValidating,
    required ValueChanged<int> onSelected,
  }) {
    final bool isCurrent = (selectedRound == currentRound);
    final bool isLive = isCurrent && !isMarketOpen;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          PopupMenuButton<int>(
            tooltip: "Selecionar Rodada",
            onSelected: onSelected,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Rodada $selectedRound",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.arrow_drop_down, size: 20, color: Colors.black87),
              ],
            ),
            itemBuilder: (ctx) {
              final maxRound = currentRound > 0 ? currentRound : 1;
              return List.generate(maxRound, (index) {
                final r = index + 1;
                final rIsCurrent = (r == currentRound);
                final rIsSelected = (r == selectedRound);
                return PopupMenuItem<int>(
                  value: r,
                  child: Row(
                    children: [
                      Text(
                        "Rodada $r",
                        style: TextStyle(
                          fontWeight: rIsSelected ? FontWeight.bold : FontWeight.normal,
                          color: rIsSelected ? Theme.of(context).primaryColor : Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (rIsCurrent)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isMarketOpen ? Colors.blue.shade50 : Colors.green.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isMarketOpen ? "Aberta" : "Ao Vivo",
                            style: TextStyle(
                              fontSize: 10,
                              color: isMarketOpen ? Colors.blue.shade800 : Colors.green.shade800,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            "Finalizada",
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              });
            },
          ),
          const SizedBox(width: 8),
          if (isCurrent) ...[
            if (isScoutsValidating)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  "Validando Scouts",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.orange),
                ),
              )
            else if (isLive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      "Ao Vivo",
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  "Mercado Aberto",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue),
                ),
              ),
          ] else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                "Oficial Consolidado",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black54),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final routeArgs = ModalRoute.of(context)?.settings.arguments;
    int tabIndex = widget.initialTabIndex;
    if (routeArgs is int) {
      tabIndex = routeArgs;
    } else if (routeArgs is Map && routeArgs['tab'] is int) {
      tabIndex = routeArgs['tab'] as int;
    }

    return DefaultTabController(
      length: 3,
      initialIndex: tabIndex.clamp(0, 2),
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/logo_fjf_fantasy.webp', height: 28),
              const SizedBox(width: 8),
              const Text("Central de Scouts"),
            ],
          ),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: "Parciais Ao Vivo", icon: Icon(Icons.bolt)),
              Tab(text: "Mais Escalados", icon: Icon(Icons.groups)),
              Tab(text: "Seleção da Rodada", icon: Icon(Icons.star)),
            ],
          ),
        ),
        bottomNavigationBar: const FantasyBottomNavBar(currentRoute: '/fantasy-scouts'),
        body: TabBarView(
          children: [
            // Aba 1: Parciais Ao Vivo de Qualquer Atleta (Tempo Real / FinOps otimizado)
            const FantasyLiveAthletesView(),

            // Aba 2: Mais Escalados da Rodada
            StreamBuilder<Map<String, dynamic>>(
              stream: _fantasyRepo.streamMarketStatus(),
              builder: (context, statusSnap) {
                final marketStatus = statusSnap.data ?? {'is_open': true, 'current_round': 1};
                final bool isMarketOpen = marketStatus['is_open'] == true;
                final int currentRound = (marketStatus['current_round'] as int?) ?? 1;
                final selectedRound = _selectedMostSelectedRound ?? currentRound;
                final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

                return StreamBuilder<bool>(
                  stream: isMarketOpen
                      ? Stream.value(false)
                      : _fantasyService.streamAreAllMatchesFinished(seasonId, currentRound),
                  builder: (context, matchSnap) {
                    final bool isScoutsValidating = !isMarketOpen && (matchSnap.data == true);

                    return Column(
                      children: [
                        _buildRoundSelectorBar(
                          selectedRound: selectedRound,
                          currentRound: currentRound,
                          isMarketOpen: isMarketOpen,
                          isScoutsValidating: isScoutsValidating,
                          onSelected: (r) {
                            setState(() => _selectedMostSelectedRound = r);
                          },
                        ),
                        Expanded(
                          child: StreamBuilder<DocumentSnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('fantasy_stats')
                                .doc('round_$selectedRound')
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Center(child: CircularProgressIndicator());
                              }

                              Map<String, dynamic> data = {};
                              if (snapshot.hasData && snapshot.data!.exists) {
                                data = snapshot.data!.data() as Map<String, dynamic>;
                              }

                              List<Map<String, dynamic>> mostSelected = List<Map<String, dynamic>>.from(
                                  data['most_selected'] ?? data['most_picked'] ?? []);

                              // Se não achou em round_$selectedRound, tenta fallback para global_round_stats se a rodada coincidir
                              if (mostSelected.isEmpty) {
                                return StreamBuilder<DocumentSnapshot>(
                                  stream: _fantasyService.streamGlobalScouts(),
                                  builder: (context, globalSnap) {
                                    if (globalSnap.connectionState == ConnectionState.waiting) {
                                      return const Center(child: CircularProgressIndicator());
                                    }
                                    if (globalSnap.hasData && globalSnap.data!.exists) {
                                      final gData = globalSnap.data!.data() as Map<String, dynamic>;
                                      final int gRound = (gData['round'] as int?) ?? 0;
                                      if (gRound == selectedRound) {
                                        mostSelected = List<Map<String, dynamic>>.from(
                                            gData['most_selected'] ?? gData['most_picked'] ?? []);
                                        data = gData;
                                      }
                                    }

                                    if (mostSelected.isEmpty) {
                                      return _buildEmptyMostSelected(
                                        isMarketOpen,
                                        selectedRound,
                                        isScoutsValidating: isScoutsValidating && selectedRound == currentRound,
                                      );
                                    }

                                    final int totalTeams = (data['total_teams'] as int?) ?? 0;
                                    return _buildMostSelectedList(
                                      mostSelected,
                                      totalTeams,
                                      selectedRound,
                                      isMarketOpen && selectedRound == currentRound,
                                      isScoutsValidating: isScoutsValidating && selectedRound == currentRound,
                                    );
                                  },
                                );
                              }

                              final int totalTeams = (data['total_teams'] as int?) ?? 0;
                              return _buildMostSelectedList(
                                mostSelected,
                                totalTeams,
                                selectedRound,
                                isMarketOpen && selectedRound == currentRound,
                                isScoutsValidating: isScoutsValidating && selectedRound == currentRound,
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),

            // Aba 3: Seleção da Rodada (Dream Team)
            StreamBuilder<Map<String, dynamic>>(
              stream: _fantasyRepo.streamMarketStatus(),
              builder: (context, statusSnap) {
                final marketStatus = statusSnap.data ?? {'is_open': true, 'current_round': 1};
                final bool isMarketOpen = marketStatus['is_open'] == true;
                final int currentRound = (marketStatus['current_round'] as int?) ?? 1;
                final selectedRound = _selectedDreamTeamRound ?? currentRound;
                final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

                return StreamBuilder<bool>(
                  stream: isMarketOpen
                      ? Stream.value(false)
                      : _fantasyService.streamAreAllMatchesFinished(seasonId, currentRound),
                  builder: (context, matchSnap) {
                    final bool isScoutsValidating = !isMarketOpen && (matchSnap.data == true);

                    return Column(
                      children: [
                        _buildRoundSelectorBar(
                          selectedRound: selectedRound,
                          currentRound: currentRound,
                          isMarketOpen: isMarketOpen,
                          isScoutsValidating: isScoutsValidating,
                          onSelected: (r) {
                            setState(() => _selectedDreamTeamRound = r);
                          },
                        ),
                        Expanded(
                          child: _buildDreamTeamContent(
                            seasonId: seasonId,
                            selectedRound: selectedRound,
                            currentRound: currentRound,
                            isMarketOpen: isMarketOpen,
                            isScoutsValidating: isScoutsValidating,
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDreamTeamContent({
    required String seasonId,
    required int selectedRound,
    required int currentRound,
    required bool isMarketOpen,
    required bool isScoutsValidating,
  }) {
    final bool isCurrent = (selectedRound == currentRound);

    // Se é a rodada atual e o mercado está fechado (em andamento ou parciais ativas)
    if (isCurrent && !isMarketOpen) {
      if (_isLoadingBaseData) {
        return const Center(child: CircularProgressIndicator());
      }

      return StreamBuilder<Map<String, FantasyScoutDetail>>(
        stream: _scoutService.streamLiveScores(seasonId, selectedRound),
        builder: (context, liveSnap) {
          if (liveSnap.connectionState == ConnectionState.waiting && !liveSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final liveScores = liveSnap.data ?? {};
          final liveDreamTeam = _computeLiveDreamTeam(
            scores: liveScores,
            players: _allPlayers,
            teamsMap: _teamsMap,
          );

          if (liveDreamTeam.isEmpty) {
            return _buildEmptyDreamTeam(
              round: selectedRound,
              isLive: true,
              isScoutsValidating: isScoutsValidating,
            );
          }

          return _buildDreamTeamList(
            liveDreamTeam,
            round: selectedRound,
            isLive: true,
            isScoutsValidating: isScoutsValidating,
          );
        },
      );
    }

    // Se é a rodada atual com mercado aberto (jogos da rodada ainda não iniciaram)
    if (isCurrent && isMarketOpen) {
      return _buildEmptyDreamTeam(
        round: selectedRound,
        isMarketOpen: true,
      );
    }

    // Se é uma rodada anterior (oficial já fechada)
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('fantasy_stats')
          .doc('round_$selectedRound')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        List<Map<String, dynamic>> dreamTeam = [];
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          dreamTeam = List<Map<String, dynamic>>.from(data['dream_team'] ?? []);
        }

        // Se não achou em round_$selectedRound, tenta fallback para global_round_stats se a rodada coincidir
        if (dreamTeam.isEmpty) {
          return StreamBuilder<DocumentSnapshot>(
            stream: _fantasyService.streamGlobalScouts(),
            builder: (context, globalSnap) {
              if (globalSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (globalSnap.hasData && globalSnap.data!.exists) {
                final gData = globalSnap.data!.data() as Map<String, dynamic>;
                final int gRound = (gData['round'] as int?) ?? 0;
                if (gRound == selectedRound) {
                  dreamTeam = List<Map<String, dynamic>>.from(gData['dream_team'] ?? []);
                }
              }

              if (dreamTeam.isEmpty) {
                return _buildEmptyDreamTeam(
                  round: selectedRound,
                  isOfficial: true,
                );
              }

              return _buildDreamTeamList(
                dreamTeam,
                round: selectedRound,
                isLive: false,
              );
            },
          );
        }

        return _buildDreamTeamList(
          dreamTeam,
          round: selectedRound,
          isLive: false,
        );
      },
    );
  }

  Widget _buildEmptyMostSelected(bool isMarketOpen, int round, {bool isScoutsValidating = false}) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isScoutsValidating ? Colors.amber.shade50 : Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isScoutsValidating ? Icons.fact_check_rounded : Icons.groups_outlined,
                size: 64,
                color: isScoutsValidating ? Colors.amber.shade700 : Colors.blue.shade600,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isScoutsValidating
                  ? "Scouts em Validação (Rodada $round)"
                  : (isMarketOpen
                      ? "Mercado Aberto (Rodada $round)"
                      : "Estatísticas da Rodada $round"),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              isScoutsValidating
                  ? "Todos os jogos da rodada estão encerrados. Os scouts estão sendo auditados e validados pela coordenação e em breve o mercado será reaberto."
                  : (isMarketOpen
                      ? "As estatísticas consolidadas dos mais escalados são geradas oficialmente pela coordenação no fechamento do mercado para preservar o sigilo das estratégias."
                      : "As estatísticas dos mais escalados ainda não foram disponibilizadas para esta rodada."),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyDreamTeam({
    required int round,
    bool isMarketOpen = false,
    bool isLive = false,
    bool isScoutsValidating = false,
    bool isOfficial = false,
  }) {
    String title = "Seleção da Rodada $round";
    String description = "Aguardando definição dos scouts.";
    IconData icon = Icons.military_tech_outlined;
    Color iconColor = Colors.amber.shade700;
    Color bgColor = Colors.amber.shade50;

    if (isScoutsValidating) {
      title = "Scouts em Validação (Rodada $round)";
      description =
          "Todos os jogos da rodada foram encerrados! Os scouts estão sendo auditados e a Seleção da Rodada será oficializada assim que o fechamento for homologado pela coordenação.";
      icon = Icons.fact_check_rounded;
      iconColor = Colors.orange.shade700;
      bgColor = Colors.orange.shade50;
    } else if (isLive) {
      title = "Seleção Parcial Ao Vivo (Rodada $round)";
      description =
          "A rodada está em andamento! A Seleção da Rodada será formada dinamicamente em tempo real conforme as partidas forem acontecendo e os scouts forem registrados.";
      icon = Icons.bolt;
      iconColor = Colors.green.shade700;
      bgColor = Colors.green.shade50;
    } else if (isMarketOpen) {
      title = "Mercado Aberto (Rodada $round)";
      description =
          "O mercado da Rodada $round ainda está aberto. A Seleção da Rodada será montada durante os jogos.\n\nVocê pode consultar a Seleção Oficial das rodadas anteriores no seletor de rodada acima.";
      icon = Icons.lock_open;
      iconColor = Colors.blue.shade700;
      bgColor = Colors.blue.shade50;
    } else if (isOfficial) {
      title = "Seleção da Rodada $round";
      description = "Nenhuma seleção oficial foi registrada para a Rodada $round.";
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 64, color: iconColor),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMostSelectedList(
    List<Map<String, dynamic>> players,
    int totalTeams,
    int round,
    bool isMarketOpen, {
    bool isScoutsValidating = false,
  }) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: players.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          // Card de Cabeçalho / Sumário
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Theme.of(context).primaryColor, Colors.indigo.shade800],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isScoutsValidating
                            ? Colors.amber.shade400
                            : (isMarketOpen ? Colors.amber : Colors.greenAccent),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isScoutsValidating) ...[
                            Icon(Icons.fact_check_rounded, size: 12, color: Colors.amber.shade900),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            isScoutsValidating
                                ? "SCOUTS EM VALIDAÇÃO"
                                : (isMarketOpen ? "MERCADO ABERTO" : "MERCADO FECHADO"),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isScoutsValidating
                                  ? Colors.amber.shade900
                                  : (isMarketOpen ? Colors.black87 : Colors.green.shade900),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Rodada $round",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                if (isScoutsValidating) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, size: 13, color: Colors.white),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "Jogos encerrados. Validando scouts antes de reabrir o mercado.",
                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  "${players.length} Atletas em Destaque",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                if (totalTeams > 0)
                  Text(
                    "Total de $totalTeams times escalados",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          );
        }

        final p = players[index - 1];
        final rank = index;
        final int selections = (p['selections'] ?? p['count'] ?? 0) as int;
        final int captainSelections = (p['captain_selections'] ?? 0) as int;
        final String photoUrl = (p['photo_url'] ?? '').toString();
        final String shieldUrl = (p['team_shield_url'] ?? '').toString();
        final String pos = (p['position'] ?? '').toString();
        final Color posColor = _getPositionColor(pos);
        final dynamic roundScoreRaw = p['round_score'] ?? p['score'];
        final double? roundScore = roundScoreRaw != null ? (roundScoreRaw as num).toDouble() : null;

        Widget rankBadge;
        if (rank == 1) {
          rankBadge = Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFFA500)]),
            ),
            child: const Center(
              child: Text("1º", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12)),
            ),
          );
        } else if (rank == 2) {
          rankBadge = Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey.shade400,
            ),
            child: const Center(
              child: Text("2º", style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12)),
            ),
          );
        } else if (rank == 3) {
          rankBadge = Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.brown.shade300,
            ),
            child: const Center(
              child: Text("3º", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
            ),
          );
        } else {
          rankBadge = Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey.shade200,
            ),
            child: Center(
              child: Text(
                "$rankº",
                style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ),
          );
        }

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                rankBadge,
                const SizedBox(width: 10),

                // Foto do Atleta com Escudo do Clube sobreposto
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey.shade200,
                        border: Border.all(color: Colors.grey.shade300, width: 1),
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: OptimizedNetworkImage(
                        imageUrl: photoUrl,
                        width: 46,
                        height: 46,
                        memCacheWidth: 96,
                        memCacheHeight: 96,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        fallbackIcon: Icons.person,
                      ),
                    ),
                    if (shieldUrl.isNotEmpty)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          clipBehavior: Clip.hardEdge,
                          child: OptimizedNetworkImage(
                            imageUrl: shieldUrl,
                            width: 18,
                            height: 18,
                            memCacheWidth: 40,
                            memCacheHeight: 40,
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                            errorWidget: const SizedBox.shrink(),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),

                // Dados do Atleta (Nome, Posição, Time)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p['name'] ?? 'Desconhecido',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: posColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: posColor.withValues(alpha: 0.4), width: 0.6),
                            ),
                            child: Text(
                              pos,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: posColor,
                              ),
                            ),
                          ),
                          if (p['team_name'] != null && p['team_name'].toString().isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                p['team_name'].toString(),
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (captainSelections > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            "★ $captainSelections como capitão",
                            style: TextStyle(fontSize: 10, color: Colors.amber.shade900, fontWeight: FontWeight.w600),
                          ),
                        ),
                    ],
                  ),
                ),

                // Contagem de Escalações e Pontos
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          "$selections",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          selections == 1 ? "time" : "times",
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                    if (roundScore != null)
                      Text(
                        "${roundScore >= 0 ? '+' : ''}${roundScore.toStringAsFixed(1)} pts",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: roundScore >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDreamTeamList(
    List<Map<String, dynamic>> players, {
    required int round,
    required bool isLive,
    bool isScoutsValidating = false,
  }) {
    double totalTeamScore = 0.0;
    for (var p in players) {
      final dynamic raw = p['score'] ?? p['round_score'] ?? 0;
      totalTeamScore += (raw as num).toDouble();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: players.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isLive
                    ? [Colors.teal.shade800, Colors.green.shade700]
                    : [Colors.green.shade800, Colors.teal.shade700],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  isLive ? Icons.bolt : Icons.star,
                  color: Colors.amber,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isScoutsValidating
                                  ? Colors.amber.shade400
                                  : (isLive ? Colors.greenAccent : const Color(0xFFFFD700)),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isScoutsValidating) ...[
                                  Icon(Icons.fact_check_rounded, size: 11, color: Colors.amber.shade900),
                                  const SizedBox(width: 3),
                                ],
                                Text(
                                  isScoutsValidating
                                      ? "SCOUTS EM VALIDAÇÃO"
                                      : (isLive ? "PARCIAL AO VIVO" : "SELEÇÃO OFICIAL"),
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: isScoutsValidating
                                        ? Colors.amber.shade900
                                        : (isLive ? Colors.green.shade900 : Colors.black87),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "Rodada $round",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isLive ? "Seleção Parcial da Rodada" : "Seleção da Rodada",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                      Text(
                        isLive
                            ? "Maiores pontuadores da rodada em tempo real"
                            : "Os maiores pontuadores por posição",
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      totalTeamScore.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                    const Text("pts total", style: TextStyle(color: Colors.white70, fontSize: 10)),
                  ],
                ),
              ],
            ),
          );
        }

        final p = players[index - 1];
        final String photoUrl = (p['photo_url'] ?? '').toString();
        final String shieldUrl = (p['team_shield_url'] ?? '').toString();
        final String pos = (p['position'] ?? '').toString();
        final Color posColor = _getPositionColor(pos);
        final dynamic scoreRaw = p['score'] ?? p['round_score'] ?? 0;
        final double score = (scoreRaw as num).toDouble();

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // Foto do Atleta com Escudo sobreposto
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey.shade200,
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: OptimizedNetworkImage(
                        imageUrl: photoUrl,
                        width: 44,
                        height: 44,
                        memCacheWidth: 96,
                        memCacheHeight: 96,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        fallbackIcon: Icons.person,
                      ),
                    ),
                    if (shieldUrl.isNotEmpty)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          clipBehavior: Clip.hardEdge,
                          child: OptimizedNetworkImage(
                            imageUrl: shieldUrl,
                            width: 18,
                            height: 18,
                            memCacheWidth: 40,
                            memCacheHeight: 40,
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                            errorWidget: const SizedBox.shrink(),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),

                // Nome, Posição e Time
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p['name'] ?? 'Desconhecido',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: posColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: posColor.withValues(alpha: 0.4), width: 0.6),
                            ),
                            child: Text(
                              pos,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: posColor,
                              ),
                            ),
                          ),
                          if (p['team_name'] != null && p['team_name'].toString().isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                p['team_name'].toString(),
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Pontuação
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      score.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: score >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                    ),
                    const Text("pts", style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
