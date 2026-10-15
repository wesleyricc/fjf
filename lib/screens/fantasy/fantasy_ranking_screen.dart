import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/fantasy_service.dart';
import '../../models/fantasy_models.dart';
import '../../services/fantasy_auth_service.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // 🚨 Analytics: Acesso inicial ao ranking (Aba da Rodada como Padrão)
    AnalyticsService.logCustomScreenView('Fantasy_Ranking_Tab_Rodada');

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

  @override
  Widget build(BuildContext context) {
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
          tabs: const [
            Tab(text: "DA RODADA"),
            Tab(text: "GERAL"),
          ],
        ),
      ),
      bottomNavigationBar:
          const FantasyBottomNavBar(currentRoute: '/fantasy-rankings'),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _RankingList(isGlobal: false),
          _RankingList(isGlobal: true),
        ],
      ),
    );
  }
}

class _RankingList extends StatefulWidget {
  final bool isGlobal;

  const _RankingList({required this.isGlobal});

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

  Future<void> _loadRanking(
      {bool initial = false, bool forceRefresh = false}) async {
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
        limit: nextLimit,
      );

      if (mounted) {
        if (teams.isEmpty && previousCount > 0) {
          setState(() {
            _isLoadingMore = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  "Não foi possível carregar mais times. Tente novamente."),
              duration: Duration(seconds: 3),
            ),
          );
          return;
        }

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
    final authService = Provider.of<FantasyAuthService>(context, listen: false);
    final currentUserId = authService.user?.uid;

    // 4. LISTA REAL
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      child: ListView.builder(
        key: PageStorageKey<String>('ranking_list_${widget.isGlobal}'),
        itemCount: teams.length + (_hasMore ? 1 : 0),
        padding: const EdgeInsets.only(bottom: 20, top: 10),
        itemBuilder: (ctx, index) {
          if (index == teams.length) {
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

          final team = teams[index];
          final int rank = index + 1;
          final bool isMe = team.userId == currentUserId;

          return _buildRankingCard(context, rank, team, isMe, widget.isGlobal);
        },
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
      bool isMe, bool isGlobal) {
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

    final double displayPoints = isGlobal ? team.totalPoints : team.lastScore;

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
            Text(displayPoints.toStringAsFixed(2),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.blue[800])),
            Text("pts",
                style: TextStyle(fontSize: 10, color: Colors.grey[600])),
          ]),
        ),
      ),
    );
  }
}
