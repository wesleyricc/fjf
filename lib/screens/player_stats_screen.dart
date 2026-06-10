import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/admin_service.dart';
import '../services/championship_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/generic_player_rank_list.dart'; 
import '../widgets/total_cards_rank_list.dart';    
import '../models/player_model.dart';
import '../widgets/ui/shimmer_effect.dart';     
import '../widgets/ui/custom_empty_state.dart';  
import '../theme/app_theme.dart'; // <-- NOVO IMPORT

class PlayerStatsScreen extends StatefulWidget {
  const PlayerStatsScreen({super.key});

  @override
  State<PlayerStatsScreen> createState() => _PlayerStatsScreenState();
}

class _PlayerStatsScreenState extends State<PlayerStatsScreen> {
  bool _isFetching = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchData();
    });
  }

  Future<void> _fetchData() async {
    await Provider.of<ChampionshipService>(context, listen: false).fetchAllPlayers();
    if (mounted) setState(() => _isFetching = false);
  }

  Future<void> _showHelp(BuildContext context) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Legenda das Estatísticas"),
        content: SingleChildScrollView(
          child: Text(
            "• Artilheiros: Ranking de gols marcados.\n"
            "• Assistências: Ranking de passes para gol.\n"
            "• Goleiro MV: Menos Vazado (Gols Sofridos).\n"
            "• Pendurados: Jogadores com ${AdminService.pendingYellowCards} cartões amarelos.\n"
            "• Suspensos: Jogadores suspensos na próxima rodada.\n"
            "• Total Cartões: Soma de CA + CV."
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("OK"))],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChampionshipService>(
      builder: (context, service, _) {
        final seasonName = service.currentSeasonName;
        final List<Player> allPlayers = List.from(service.allPlayers);

        if (service.isOffline && allPlayers.isEmpty) {
           return Scaffold(
            appBar: AppBar(
              title: const Text("Estatísticas"),
              flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.brazilGradient)),
            ),
            drawer: const AppDrawer(),
            body: CustomEmptyState.offline(
              onRetry: () {
                setState(() => _isFetching = true);
                service.fetchAllPlayers(force: true).then((_) {
                   if(mounted) setState(() => _isFetching = false);
                });
              }
            ),
           );
        }

        if (_isFetching && allPlayers.isEmpty) {
           return Scaffold(
            appBar: AppBar(
              title: const Text("Estatísticas"),
              flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.brazilGradient)),
            ),
            drawer: const AppDrawer(),
            body: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: 8,
              separatorBuilder: (_,__) => const SizedBox(height: 16),
              itemBuilder: (_,__) => Row(
                children: const [
                  ShimmerEffect.circular(size: 45),
                  SizedBox(width: 16),
                  Expanded(child: ShimmerEffect.rectangular(height: 16)),
                  SizedBox(width: 16),
                  ShimmerEffect.rectangular(height: 24, width: 40),
                ],
              ),
            ),
           );
        }

        final scorers = allPlayers.where((p) => !p.isStaff && p.goals > 0).toList()..sort((a, b) => b.goals.compareTo(a.goals));
        final assists = allPlayers.where((p) => !p.isStaff && p.assists > 0).toList()..sort((a, b) => b.assists.compareTo(a.assists));
        final goalkeepers = allPlayers.where((p) => p.isGoalkeeper).toList()..sort((a, b) => a.goalsConceded.compareTo(b.goalsConceded));
        final motm = allPlayers.where((p) => p.motmAwards > 0).toList()..sort((a, b) => b.motmAwards.compareTo(a.motmAwards));
        final pending = allPlayers.where((p) => p.yellowCards == AdminService.pendingYellowCards).toList();
        final suspended = allPlayers.where((p) => p.isSuspended).toList();
        final yellows = allPlayers.where((p) => p.totalYellowCards > 0).toList()..sort((a, b) => b.totalYellowCards.compareTo(a.totalYellowCards));
        final reds = allPlayers.where((p) => p.totalRedCards > 0).toList()..sort((a, b) => b.totalRedCards.compareTo(a.totalRedCards));

        return DefaultTabController(
          length: 9,
          child: Scaffold(
            appBar: AppBar(
              // 🚨 NOVO: Gradiente da Copa aplicado
              flexibleSpace: Container(
                decoration: const BoxDecoration(
                  gradient: AppTheme.brazilGradient,
                ),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Estatísticas'),
                  Text(seasonName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w300)),
                ],
              ),
              actions: [
                IconButton(icon: const Icon(Icons.help_outline), onPressed: () => _showHelp(context)),
                IconButton(
                  icon: const Icon(Icons.refresh), 
                  onPressed: () {
                    setState(() => _isFetching = true);
                    service.fetchAllPlayers(force: true).then((_) {
                       if(mounted) setState(() => _isFetching = false);
                    });
                  }
                ),
              ],
              bottom: const TabBar(
                isScrollable: true,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                tabs: [
                  Tab(text: 'Artilheiros'),
                  Tab(text: 'Assistências'),
                  Tab(text: 'Goleiro MV'),
                  Tab(text: 'Craque do Jogo'),
                  Tab(text: 'Pendurados'),
                  Tab(text: 'Suspensos'),
                  Tab(text: 'Amarelos'),
                  Tab(text: 'Vermelhos'),
                  Tab(text: 'Total Cartões'),
                ],
              ),
            ),
            drawer: const AppDrawer(),
            body: TabBarView(
              children: [
                GenericPlayerRankList(players: scorers, statField: 'goals', statLabel: 'Gols', emptyMessage: 'Nenhum gol marcado.', emptyIcon: Icons.sports_soccer),
                GenericPlayerRankList(players: assists, statField: 'assists', statLabel: 'Ass', emptyMessage: 'Nenhuma assistência.', emptyIcon: Icons.assistant),
                GenericPlayerRankList(players: goalkeepers, statField: 'goalsConceded', statLabel: 'GS', emptyMessage: 'Sem dados de goleiros.', emptyIcon: Icons.pan_tool),
                GenericPlayerRankList(players: motm, statField: 'motmAwards', statLabel: 'x', emptyMessage: 'Nenhum craque eleito.', emptyIcon: Icons.star),
                GenericPlayerRankList(players: pending, isStatusList: true, emptyMessage: 'Ninguém pendurado.', emptyIcon: Icons.mood),
                GenericPlayerRankList(players: suspended, isStatusList: true, isSuspendedTab: true, emptyMessage: 'Ninguém suspenso.', emptyIcon: Icons.check_circle_outline),
                GenericPlayerRankList(players: yellows, statField: 'totalYellowCards', statLabel: 'CA', emptyMessage: 'Sem cartões.', emptyIcon: Icons.style_outlined),
                GenericPlayerRankList(players: reds, statField: 'totalRedCards', statLabel: 'CV', emptyMessage: 'Sem cartões.', emptyIcon: Icons.style),
                TotalCardsRankList(allPlayers: allPlayers),
              ],
            ),
            bottomNavigationBar: const SponsorBannerRotator(),
          ),
        );
      }
    );
  }
}