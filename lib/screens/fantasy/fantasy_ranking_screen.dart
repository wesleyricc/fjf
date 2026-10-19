import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/fantasy_service.dart';
import '../../models/fantasy_models.dart';
import '../../services/fantasy_auth_service.dart';
import '../../services/championship_service.dart';
import '../../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../../widgets/ui/shimmer_effect.dart';
import '../../widgets/ui/custom_empty_state.dart';
import '../../widgets/team_logo_widget.dart';
import '../../widgets/fantasy/fantasy_bottom_nav_bar.dart';

class FantasyRankingScreen extends StatefulWidget {
  const FantasyRankingScreen({super.key});

  @override
  State<FantasyRankingScreen> createState() => _FantasyRankingScreenState();
}

class _FantasyRankingScreenState extends State<FantasyRankingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  RankingMetric _currentMetric = RankingMetric.points;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Se o mercado estiver aberto, direciona para a aba Geral (onde há classificação acumulada ativa)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final fantasyService = Provider.of<FantasyService>(context, listen: false);
        final status = await fantasyService.streamMarketStatus().first;
        final bool isOpen = status['is_open'] == true;
        if (isOpen && mounted && _tabController.index == 0) {
          _tabController.animateTo(1);
        }
      } catch (_) {}
    });

    // 🚨 Analytics: Acesso inicial ao ranking
    AnalyticsService.logCustomScreenView('Fantasy_Ranking_Tab_Init');

    // 🚨 Analytics: Monitora qual ranking os usuários mais olham
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final tabName = _tabController.index == 0 ? 'Rodada' : 'Geral';
        AnalyticsService.logCustomScreenView('Fantasy_Ranking_Tab_$tabName');
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildMetricToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).primaryColor,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () {
                  if (_currentMetric != RankingMetric.points) {
                    setState(() => _currentMetric = RankingMetric.points);
                    AnalyticsService.logCustomScreenView('Fantasy_Ranking_Metric_Points');
                  }
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  decoration: BoxDecoration(
                    color: _currentMetric == RankingMetric.points
                        ? Colors.white
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: _currentMetric == RankingMetric.points
                        ? [
                            const BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            )
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.emoji_events_outlined,
                        size: 16,
                        color: _currentMetric == RankingMetric.points
                            ? Theme.of(context).primaryColor
                            : Colors.white70,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "PONTUAÇÃO",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _currentMetric == RankingMetric.points
                              ? Theme.of(context).primaryColor
                              : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: InkWell(
                onTap: () {
                  if (_currentMetric != RankingMetric.patrimony) {
                    setState(() => _currentMetric = RankingMetric.patrimony);
                    AnalyticsService.logCustomScreenView('Fantasy_Ranking_Metric_Cartoletas');
                  }
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  decoration: BoxDecoration(
                    color: _currentMetric == RankingMetric.patrimony
                        ? Colors.white
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: _currentMetric == RankingMetric.patrimony
                        ? [
                            const BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            )
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.monetization_on_outlined,
                        size: 16,
                        color: _currentMetric == RankingMetric.patrimony
                            ? const Color(0xFF047857)
                            : Colors.white70,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "CARTOLETAS",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _currentMetric == RankingMetric.patrimony
                              ? const Color(0xFF047857)
                              : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fantasyService = Provider.of<FantasyService>(context, listen: false);
    final seasonId = Provider.of<ChampionshipService>(context).currentSeasonId;

    return StreamBuilder<Map<String, dynamic>>(
      stream: fantasyService.streamMarketStatus(),
      builder: (context, statusSnap) {
        final status =
            statusSnap.data ?? {'is_open': true, 'current_round': 1};
        final bool isOpen = status['is_open'] == true;
        final int currentRound = (status['current_round'] ?? 1) is int
            ? status['current_round']
            : int.tryParse(status['current_round'].toString()) ?? 1;

        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/logo_fjf_fantasy.webp', height: 28),
                const SizedBox(width: 8),
                const Text("Classificação"),
              ],
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!isOpen) ...[
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: const BoxDecoration(
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                      Text(!isOpen ? "DA RODADA (AO VIVO)" : "DA RODADA"),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!isOpen) ...[
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: const BoxDecoration(
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                      Text(!isOpen ? "GERAL (AO VIVO)" : "GERAL"),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar:
              const FantasyBottomNavBar(currentRoute: '/fantasy-rankings'),
          body: Column(
            children: [
              _buildMetricToggle(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _RankingList(
                      isGlobal: false,
                      metric: _currentMetric,
                      seasonId: seasonId,
                      currentRound: currentRound,
                      isMarketOpen: isOpen,
                      onGoToGlobal: () => _tabController.animateTo(1),
                    ),
                    _RankingList(
                      isGlobal: true,
                      metric: _currentMetric,
                      seasonId: seasonId,
                      currentRound: currentRound,
                      isMarketOpen: isOpen,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RankingList extends StatefulWidget {
  final bool isGlobal;
  final RankingMetric metric;
  final String seasonId;
  final int currentRound;
  final bool isMarketOpen;
  final VoidCallback? onGoToGlobal;

  const _RankingList({
    required this.isGlobal,
    required this.metric,
    required this.seasonId,
    required this.currentRound,
    required this.isMarketOpen,
    this.onGoToGlobal,
  });

  @override
  State<_RankingList> createState() => _RankingListState();
}

class _RankingListState extends State<_RankingList>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  int _currentLimit = 20;
  List<FantasyTeam>? _teams;
  bool _isLoadingInitial = true;
  bool _isLoadingMore = false;
  bool _hasError = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadRanking(initial: true);
  }

  @override
  void didUpdateWidget(covariant _RankingList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.metric != widget.metric || oldWidget.isGlobal != widget.isGlobal) {
      _currentLimit = 20;
      _loadRanking(initial: true);
    }
  }

  Future<void> _loadRanking(
      {bool initial = false, bool forceRefresh = false}) async {
    // 🏆 FINOPS & LIVE SCOUT: Se for a aba DA RODADA com mercado aberto,
    // não carrega dados estáticos de rodadas passadas (esta aba é exclusiva de jogos ao vivo)
    if (!widget.isGlobal && widget.isMarketOpen) {
      if (mounted) {
        setState(() {
          _isLoadingInitial = false;
          _hasError = false;
        });
      }
      return;
    }

    if (initial && !_isLoadingInitial) {
      setState(() {
        _isLoadingInitial = true;
        _hasError = false;
      });
    }

    try {
      final fantasyService =
          Provider.of<FantasyService>(context, listen: false);
      final teams = await fantasyService.getRanking(
        isGlobal: widget.isGlobal,
        metric: widget.metric,
        limit: _currentLimit,
        forceRefresh: forceRefresh,
      );

      if (mounted) {
        setState(() {
          _teams = teams;
          _isLoadingInitial = false;
          _hasError = false;
          _hasMore = teams.length >= _currentLimit;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingInitial = false;
          if (_teams == null) {
            _hasError = true;
          }
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    final nextLimit = _currentLimit + 20;
    setState(() {
      _isLoadingMore = true;
    });

    try {
      final fantasyService =
          Provider.of<FantasyService>(context, listen: false);
      final previousCount = _teams?.length ?? 0;
      final teams = await fantasyService.getRanking(
        isGlobal: widget.isGlobal,
        metric: widget.metric,
        limit: nextLimit,
      );

      if (mounted) {
        setState(() {
          _currentLimit = nextLimit;
          _teams = teams;
          _isLoadingMore = false;
          _hasMore = teams.length >= nextLimit && teams.length > previousCount;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text("Não foi possível carregar mais times. Tente novamente."),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _handleRefresh() async {
    await _loadRanking(forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final fantasyService = Provider.of<FantasyService>(context, listen: false);
    final authService = Provider.of<FantasyAuthService>(context, listen: false);
    final currentUserId = authService.user?.uid;

    // 🏆 REGRA DO RANKING DA RODADA:
    // A aba 'DA RODADA' é exclusiva para acompanhar as parciais ao vivo (Live Scout) dos jogos em andamento.
    // Com o mercado aberto, as partidas da rodada ainda não iniciaram. Não exibimos pontuações de rodadas
    // passadas como se fossem da rodada atual.
    if (!widget.isGlobal && widget.isMarketOpen) {
      return _buildMarketOpenWaitingLiveScout(context);
    }

    // 🏆 FINOPS: Se o mercado estiver fechado e temos seasonId e round válidos, ouvimos o stream do leaderboard consolidado
    if (!widget.isMarketOpen && widget.seasonId.isNotEmpty && widget.currentRound > 0) {
      return StreamBuilder<FantasyLiveLeaderboard?>(
        stream: fantasyService.streamLiveLeaderboard(
          seasonId: widget.seasonId,
          round: widget.currentRound,
        ),
        builder: (context, liveSnap) {
          final liveLeaderboard = liveSnap.data;

          // Se temos dados consolidados ao vivo no documento único
          if (liveLeaderboard != null && liveLeaderboard.teams.isNotEmpty) {
            final liveTeams = List<FantasyLiveTeamScore>.from(liveLeaderboard.teams);

            // Verifica se as partidas da rodada já iniciaram ou se a rodada está consolidada
            final bool hasMatchesStarted = liveLeaderboard.isFinal ||
                liveTeams.any((t) => t.playersPlayed > 0 || t.roundScore != 0.0);

            // Ordenação local conforme a aba e a métrica
            if (widget.metric == RankingMetric.patrimony) {
              if (widget.isGlobal) {
                liveTeams.sort((a, b) => b.teamValue.compareTo(a.teamValue));
              } else {
                liveTeams.sort((a, b) => b.lastVariation.compareTo(a.lastVariation));
              }
            } else {
              if (widget.isGlobal) {
                liveTeams.sort((a, b) => b.totalPoints.compareTo(a.totalPoints));
              } else {
                if (hasMatchesStarted) {
                  liveTeams.sort((a, b) => b.roundScore.compareTo(a.roundScore));
                } else {
                  liveTeams.sort((a, b) => b.totalPoints.compareTo(a.totalPoints));
                }
              }
            }

            return RefreshIndicator(
              onRefresh: _handleRefresh,
              child: ListView.builder(
                key: PageStorageKey<String>(
                    'live_ranking_list_${widget.metric.name}_${widget.isGlobal}_${liveLeaderboard.round}'),
                itemCount: liveTeams.length + 1, // +1 para o banner do topo
                padding: const EdgeInsets.only(bottom: 24, top: 6),
                itemBuilder: (ctx, index) {
                  if (index == 0) {
                    return _buildLiveHeaderBanner(liveLeaderboard, hasMatchesStarted);
                  }

                  final teamIndex = index - 1;
                  final team = liveTeams[teamIndex];
                  final int rank = teamIndex + 1;
                  final bool isMe = team.userId == currentUserId || team.teamId == currentUserId;

                  return _buildLiveRankingCard(
                      context, rank, team, isMe, widget.isGlobal, hasMatchesStarted, widget.metric);
                },
              ),
            );
          }

          // Fallback para o ranking estático padrão (quando o live ainda não foi gerado)
          return _buildStandardRankingList(context, currentUserId);
        },
      );
    }

    return _buildStandardRankingList(context, currentUserId);
  }

  Widget _buildMarketOpenWaitingLiveScout(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Ícone estilizado
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.deepPurple.shade100,
                    Colors.blue.shade50,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.deepPurple.shade200, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurple.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                Icons.sensors_outlined,
                size: 40,
                color: Colors.deepPurple.shade700,
              ),
            ),
            const SizedBox(height: 20),

            // Badge da Rodada
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF2563EB),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "MERCADO ABERTO • RODADA ${widget.currentRound}",
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                      color: Color(0xFF1D4ED8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Título
            const Text(
              "Aguardando Início das Partidas",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 10),

            // Descrição explicativa
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                "O Ranking da Rodada exibe exclusivamente as pontuações do Live Scout em tempo real durante as partidas.\n\n"
                "Como o mercado da Rodada ${widget.currentRound} ainda está aberto para escalação, a bola ainda não rolou. O ranking ao vivo entrará em ação automaticamente assim que o mercado fechar e os jogos iniciarem!",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Botões de Ação
            Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                if (widget.onGoToGlobal != null)
                  ElevatedButton.icon(
                    onPressed: widget.onGoToGlobal,
                    icon: const Icon(Icons.leaderboard_outlined, size: 18),
                    label: const Text("Ver Classificação Geral"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 1,
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(context, '/fantasy-lineup');
                  },
                  icon: const Icon(Icons.shield_outlined, size: 18),
                  label: const Text("Escalar Meu Time"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F172A),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveHeaderBanner(
      FantasyLiveLeaderboard leaderboard, bool hasMatchesStarted) {
    final bool isFinal = leaderboard.isFinal;

    final Color bgColor = isFinal
        ? Colors.grey.shade100
        : (hasMatchesStarted ? Colors.green.shade50 : Colors.blue.shade50);
    final Color borderColor = isFinal
        ? Colors.grey.shade300
        : (hasMatchesStarted ? Colors.green.shade300 : Colors.blue.shade200);
    final Color textColor = isFinal
        ? Colors.grey.shade800
        : (hasMatchesStarted ? Colors.green.shade800 : Colors.blue.shade900);
    final Color iconColor = isFinal
        ? Colors.grey.shade700
        : (hasMatchesStarted ? Colors.green.shade700 : Colors.blue.shade700);

    final String titleText = isFinal
        ? "Rodada ${leaderboard.round} consolidada"
        : (hasMatchesStarted
            ? "Parciais ao vivo da Rodada ${leaderboard.round}"
            : "Rodada ${leaderboard.round} • Aguardando início das partidas");

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(
            isFinal
                ? Icons.check_circle_outline
                : (hasMatchesStarted ? Icons.sensors : Icons.schedule),
            color: iconColor,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              titleText,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
          if (!isFinal && hasMatchesStarted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                "AO VIVO",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLiveRankingCard(
      BuildContext context,
      int rank,
      FantasyLiveTeamScore team,
      bool isMe,
      bool isGlobal,
      bool hasMatchesStarted,
      RankingMetric metric) {
    Color? rankColor;
    IconData? rankIcon;
    double elevation = 1;

    if (rank == 1) {
      rankColor = const Color(0xFFFFD700);
      rankIcon = Icons.emoji_events;
      elevation = 4;
    } else if (rank == 2) {
      rankColor = const Color(0xFFC0C0C0);
      rankIcon = Icons.looks_two;
    } else if (rank == 3) {
      rankColor = const Color(0xFFCD7F32);
      rankIcon = Icons.looks_3;
    }

    String displayValue;
    String displayUnit;
    Color valueColor;

    if (metric == RankingMetric.patrimony) {
      if (isGlobal) {
        displayValue = "C\$ ${team.teamValue.toStringAsFixed(2)}";
        displayUnit = "patrimônio";
        valueColor = const Color(0xFF047857);
      } else {
        final v = team.lastVariation;
        displayValue = "${v >= 0 ? '+' : ''}C\$ ${v.toStringAsFixed(2)}";
        displayUnit = "valorização";
        valueColor = v >= 0 ? const Color(0xFF047857) : const Color(0xFFDC2626);
      }
    } else {
      final double displayPoints = isGlobal
          ? team.totalPoints
          : (hasMatchesStarted ? team.roundScore : 0.0);
      displayValue = displayPoints.toStringAsFixed(2);
      displayUnit = "pts";
      valueColor = !isGlobal ? Colors.green.shade800 : Colors.blue.shade800;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      elevation: elevation,
      color: isMe ? Colors.green[50] : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isMe
            ? BorderSide(color: Theme.of(context).primaryColor, width: 2)
            : (rank <= 3
                ? BorderSide(color: rankColor!.withValues(alpha: 0.6), width: 1.5)
                : BorderSide(color: Colors.grey.shade200)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: SizedBox(
          width: 75,
          child: Row(
            children: [
              SizedBox(
                width: 25,
                child: rankIcon != null
                    ? Icon(rankIcon, color: rankColor, size: 22)
                    : Text(
                        "$rankº",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                        textAlign: TextAlign.center,
                      ),
              ),
              const SizedBox(width: 6),
              TeamLogoWidget(
                logoUrl: team.customLogoUrl,
                shieldType: team.shieldType,
                radius: 20,
              ),
            ],
          ),
        ),
        title: Text(
          team.teamName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: isMe ? FontWeight.bold : FontWeight.w600,
            color: isMe ? Colors.green[900] : Colors.black87,
          ),
        ),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                team.ownerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                "⚽ ${team.playersPlayed}/${team.playersTotal}",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: team.playersPlayed == team.playersTotal
                      ? Colors.green.shade700
                      : Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isMe ? Colors.green.shade100 : Colors.grey[100],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isMe ? Colors.green.shade400 : Colors.grey.shade300,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayValue,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: valueColor,
                ),
              ),
              Text(
                displayUnit,
                style: TextStyle(fontSize: 9, color: Colors.grey[600], fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStandardRankingList(
      BuildContext context, String? currentUserId) {
    // 1. LOADING INICIAL
    if (_isLoadingInitial) {
      return ListView.builder(
        padding: const EdgeInsets.all(10),
        itemCount: 8,
        itemBuilder: (_, __) => _buildSkeletonItem(),
      );
    }

    // 2. ERRO OFFLINE
    if (_hasError && (_teams == null || _teams!.isEmpty)) {
      return CustomEmptyState.offline(
        onRetry: () => _loadRanking(initial: true),
      );
    }

    // 3. EMPTY STATE
    if (_teams == null || _teams!.isEmpty) {
      return RefreshIndicator(
        onRefresh: _handleRefresh,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: const Center(
                child: CustomEmptyState(
                  icon: Icons.emoji_events_outlined,
                  title: "Sem Classificação",
                  message: "Nenhum time pontuou nesta liga ainda.",
                ),
              ),
            ),
          ),
        ),
      );
    }

    final teams = _teams!;

    // 4. LISTA REAL
    final bool showRoundInfoBanner = !widget.isGlobal;
    final int extraHeaderCount = showRoundInfoBanner ? 1 : 0;

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      child: ListView.builder(
        key: PageStorageKey<String>('ranking_list_${widget.metric.name}_${widget.isGlobal}'),
        itemCount: teams.length + (_hasMore ? 1 : 0) + extraHeaderCount,
        padding: const EdgeInsets.only(bottom: 20, top: 10),
        itemBuilder: (ctx, index) {
          if (showRoundInfoBanner && index == 0) {
            return _buildStandardHeaderBanner();
          }

          final itemIndex = index - extraHeaderCount;
          if (itemIndex == teams.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: _isLoadingMore ? null : _loadMore,
                  icon: _isLoadingMore
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more),
                  label: Text(_isLoadingMore ? "Carregando..." : "Ver Mais"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).primaryColor,
                    side: BorderSide(color: Theme.of(context).primaryColor),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ),
            );
          }

          final team = teams[itemIndex];
          final int rank = itemIndex + 1;
          final bool isMe = team.userId == currentUserId;

          return _buildRankingCard(context, rank, team, isMe, widget.isGlobal, widget.metric);
        },
      ),
    );
  }

  Widget _buildStandardHeaderBanner() {
    final bool isPatrimony = widget.metric == RankingMetric.patrimony;
    String bannerText;

    if (isPatrimony) {
      bannerText = widget.isMarketOpen
          ? "Ranking de Valorização da última rodada consolidada (+C\$ ganhas ou perdidas)."
          : "Valorização da rodada: as cartoletas serão consolidadas ao final da apuração dos scouts.";
    } else {
      bannerText = widget.isMarketOpen
          ? "Mercado aberto para a Rodada ${widget.currentRound}. Exibindo pontuação oficial da última rodada apurada."
          : "Mercado fechado para a Rodada ${widget.currentRound}. Aguardando o início das partidas para exibir as parciais ao vivo.";
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isPatrimony ? const Color(0xFFECFDF5) : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPatrimony ? const Color(0xFFA7F3D0) : Colors.blue.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isPatrimony ? Icons.monetization_on_outlined : Icons.info_outline,
            color: isPatrimony ? const Color(0xFF047857) : Colors.blue.shade700,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              bannerText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isPatrimony ? const Color(0xFF065F46) : Colors.blue.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonItem() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: const [
            ShimmerEffect.rectangular(height: 20, width: 30),
            SizedBox(width: 12),
            ShimmerEffect.circular(size: 40),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerEffect.rectangular(height: 16, width: 120),
                  SizedBox(height: 6),
                  ShimmerEffect.rectangular(height: 12, width: 80),
                ],
              ),
            ),
            ShimmerEffect.rectangular(height: 20, width: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildRankingCard(BuildContext context, int rank, FantasyTeam team,
      bool isMe, bool isGlobal, RankingMetric metric) {
    Color? rankColor;
    IconData? rankIcon;
    double elevation = 1;

    if (rank == 1) {
      rankColor = const Color(0xFFFFD700);
      rankIcon = Icons.emoji_events;
      elevation = 4;
    } else if (rank == 2) {
      rankColor = const Color(0xFFC0C0C0);
      rankIcon = Icons.looks_two;
    } else if (rank == 3) {
      rankColor = const Color(0xFFCD7F32);
      rankIcon = Icons.looks_3;
    }

    String displayValue;
    String displayUnit;
    Color valueColor;

    if (metric == RankingMetric.patrimony) {
      if (isGlobal) {
        displayValue = "C\$ ${team.teamValue.toStringAsFixed(2)}";
        displayUnit = "patrimônio";
        valueColor = const Color(0xFF047857);
      } else {
        final v = team.lastVariation;
        displayValue = "${v >= 0 ? '+' : ''}C\$ ${v.toStringAsFixed(2)}";
        displayUnit = "valorização";
        valueColor = v >= 0 ? const Color(0xFF047857) : const Color(0xFFDC2626);
      }
    } else {
      final double displayPoints = isGlobal ? team.totalPoints : team.lastScore;
      displayValue = displayPoints.toStringAsFixed(2);
      displayUnit = "pts";
      valueColor = !isGlobal ? Colors.green.shade800 : Colors.blue.shade800;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      elevation: elevation,
      color: isMe ? Colors.green[50] : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isMe
            ? const BorderSide(color: Colors.green, width: 2)
            : BorderSide.none,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 30,
              child: rankIcon != null
                  ? Icon(rankIcon, color: rankColor, size: 24)
                  : Text("$rankº",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.grey),
                      textAlign: TextAlign.center),
            ),
            const SizedBox(width: 8),
            TeamLogoWidget(
              logoUrl: team.customLogoUrl,
              shieldType: team.shieldType,
              radius: 20,
            ),
          ],
        ),
        title: Text(team.teamName,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        subtitle: Text(team.ownerName,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade300)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(displayValue,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: valueColor)),
            Text(displayUnit,
                style: TextStyle(fontSize: 9, color: Colors.grey[600], fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    );
  }
}
