import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/fantasy_service.dart';
import '../../services/championship_service.dart';
import '../../utils/app_feedback.dart';
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
  bool _isGeneratingStats = false;
  bool _hasAutoTriggered = false;
  List<Map<String, dynamic>>? _localMostSelected;
  int _localTotalTeams = 0;

  Future<void> _triggerGenerateStats() async {
    if (_isGeneratingStats) return;
    setState(() => _isGeneratingStats = true);

    try {
      final result = await _fantasyService.generateGlobalMarketStats();
      final freshSnap = await FirebaseFirestore.instance.collection('fantasy_stats').doc('global_round_stats').get();
      if (freshSnap.exists && mounted) {
        final d = freshSnap.data() as Map<String, dynamic>;
        setState(() {
          _localMostSelected = List<Map<String, dynamic>>.from(d['most_selected'] ?? d['most_picked'] ?? []);
          _localTotalTeams = d['total_teams'] ?? 0;
        });
      }

      if (mounted) {
        if (result.contains("Sucesso")) {
          AppFeedback.showSuccess(context, result);
        } else {
          AppFeedback.showWarning(context, result);
        }
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.showError(context, "Erro ao gerar estatísticas: $e");
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingStats = false);
      }
    }
  }

  void _checkAndAutoGenerateIfMarketClosed(bool isMarketOpen) {
    if (!isMarketOpen && !_hasAutoTriggered && !_isGeneratingStats) {
      _hasAutoTriggered = true;
      // Dispara silenciosamente em segundo plano após o frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _triggerGenerateStats();
      });
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
          actions: [
            IconButton(
              icon: _isGeneratingStats
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.sync),
              tooltip: "Atualizar Estatísticas",
              onPressed: _isGeneratingStats ? null : _triggerGenerateStats,
            ),
          ],
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
              stream: _fantasyService.streamMarketStatus(),
              builder: (context, statusSnap) {
                final marketStatus = statusSnap.data ?? {'is_open': true, 'current_round': 1};
                final bool isMarketOpen = marketStatus['is_open'] == true;
                final int currentRound = marketStatus['current_round'] ?? 1;
                final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

                return StreamBuilder<bool>(
                  stream: isMarketOpen
                      ? Stream.value(false)
                      : _fantasyService.streamAreAllMatchesFinished(seasonId, currentRound),
                  builder: (context, matchSnap) {
                    final bool isScoutsValidating = !isMarketOpen && (matchSnap.data == true);

                    return StreamBuilder<DocumentSnapshot>(
                      stream: _fantasyService.streamGlobalScouts(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final bool docExists = snapshot.hasData && snapshot.data!.exists;
                        final data = docExists ? (snapshot.data!.data() as Map<String, dynamic>) : <String, dynamic>{};
                        final mostSelected = List<Map<String, dynamic>>.from(data['most_selected'] ?? data['most_picked'] ?? []);
                        final effectiveList = mostSelected.isNotEmpty ? mostSelected : (_localMostSelected ?? []);

                        if (effectiveList.isEmpty) {
                          // Se o mercado estiver fechado e ainda não existirem estatísticas, tenta gerar automaticamente
                          if (!isMarketOpen && !_hasAutoTriggered) {
                            _checkAndAutoGenerateIfMarketClosed(isMarketOpen);
                          }

                          return _buildEmptyMostSelected(isMarketOpen, currentRound, isScoutsValidating: isScoutsValidating);
                        }

                        final int totalTeams = (data['total_teams'] as int?) ?? _localTotalTeams;
                        final int round = (data['round'] as int?) ?? currentRound;

                        return _buildMostSelectedList(effectiveList, totalTeams, round, isMarketOpen, isScoutsValidating: isScoutsValidating);
                      },
                    );
                  },
                );
              },
            ),

            // Aba 3: Seleção da Rodada (Dream Team)
            StreamBuilder<Map<String, dynamic>>(
              stream: _fantasyService.streamMarketStatus(),
              builder: (context, statusSnap) {
                final marketStatus = statusSnap.data ?? {'is_open': true, 'current_round': 1};
                final bool isMarketOpen = marketStatus['is_open'] == true;
                final int currentRound = marketStatus['current_round'] ?? 1;
                final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

                return StreamBuilder<bool>(
                  stream: isMarketOpen
                      ? Stream.value(false)
                      : _fantasyService.streamAreAllMatchesFinished(seasonId, currentRound),
                  builder: (context, matchSnap) {
                    final bool isScoutsValidating = !isMarketOpen && (matchSnap.data == true);

                    return StreamBuilder<DocumentSnapshot>(
                      stream: _fantasyService.streamGlobalScouts(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        if (!snapshot.hasData || !snapshot.data!.exists) {
                          return _buildEmptyDreamTeam(isScoutsValidating: isScoutsValidating);
                        }

                        final data = snapshot.data!.data() as Map<String, dynamic>;
                        final dreamTeam = List<Map<String, dynamic>>.from(data['dream_team'] ?? []);

                        if (dreamTeam.isEmpty) {
                          return _buildEmptyDreamTeam(isScoutsValidating: isScoutsValidating);
                        }

                        return _buildDreamTeamList(dreamTeam);
                      },
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
                      ? "As estatísticas consolidadas dos mais escalados são geradas assim que o mercado fecha para preservar o sigilo das estratégias.\n\nVocê também pode gerá-las agora para pré-visualização."
                      : "As estatísticas dos mais escalados ainda não foram geradas para esta rodada."),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isGeneratingStats ? null : _triggerGenerateStats,
              icon: _isGeneratingStats
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.refresh),
              label: Text(_isGeneratingStats ? "Gerando..." : "Gerar Estatísticas Agora"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyDreamTeam({bool isScoutsValidating = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isScoutsValidating ? Icons.fact_check_rounded : Icons.military_tech_outlined,
                size: 64,
                color: Colors.amber.shade700,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isScoutsValidating ? "Scouts em Validação" : "Seleção da Rodada",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              isScoutsValidating
                  ? "Todos os jogos da rodada foram encerrados! Os scouts estão sendo validados e a Seleção da Rodada será oficializada assim que o fechamento for homologado."
                  : "A Seleção da Rodada será gerada ao final da rodada pelo sistema de fechamento oficial, selecionando os maiores pontuadores de cada posição.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMostSelectedList(
      List<Map<String, dynamic>> players, int totalTeams, int round, bool isMarketOpen,
      {bool isScoutsValidating = false}) {
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
            child: Row(
              children: [
                Expanded(
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
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  tooltip: "Recalcular Estatísticas",
                  onPressed: _isGeneratingStats ? null : _triggerGenerateStats,
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

        // Visual do Podium (1º Ouro, 2º Prata, 3º Bronze)
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

                // Dados do Atleta (Nome, Posição, Preço)
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

  Widget _buildDreamTeamList(List<Map<String, dynamic>> players) {
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
                colors: [Colors.green.shade800, Colors.teal.shade700],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.star, color: Colors.amber, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Seleção da Rodada",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                      Text(
                        "Os maiores pontuadores por posição",
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
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
                // Foto do Atleta
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

                // Nome e Posição
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p['name'] ?? 'Desconhecido',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 3),
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
