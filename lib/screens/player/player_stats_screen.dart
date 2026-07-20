import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/admin_service.dart';
import '../../services/championship_service.dart';
import '../../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../../widgets/main_bottom_nav_bar.dart';
import '../../widgets/generic_player_rank_list.dart';
import '../../widgets/total_cards_rank_list.dart';
import '../../models/player_model.dart';
import '../../widgets/ui/shimmer_effect.dart';
import '../../widgets/ui/custom_empty_state.dart';
import '../../theme/app_theme.dart';


class PlayerStatsScreen extends StatefulWidget {
  const PlayerStatsScreen({super.key});

  @override
  State<PlayerStatsScreen> createState() => _PlayerStatsScreenState();
}

class _PlayerStatsScreenState extends State<PlayerStatsScreen> with SingleTickerProviderStateMixin {
  bool _isFetching = true;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    
    // 🚨 Analytics: Inicialização e Controle Dinâmico de Abas
    _tabController = TabController(length: 9, vsync: this);
    AnalyticsService.logCustomScreenView('Player_Stats_Screen_Tab_Artilheiros'); // Aba padrão
    
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final tabs = [
          'Artilheiros', 'Assistencias', 'Goleiro_MV', 'Craque_Jogo', 
          'Pendurados', 'Suspensos', 'Amarelos', 'Vermelhos', 'Total_Cartoes'
        ];
        AnalyticsService.logCustomScreenView('Player_Stats_Screen_Tab_${tabs[_tabController.index]}');
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
            "• Goleiro MV: Menos Vazado (Média de gols sofridos por jogo).\n"
            "   (Exige mínimo de 3 jogos, ou o máximo atingido no início do campeonato).\n"
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

            body: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: 8,
              separatorBuilder: (_,__) => const SizedBox(height: 16),
              itemBuilder: (_,__) => const Row(
                children: [
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
        
        // --- LOGICA DINAMICA DE GOLEIRO MENOS VAZADO ---
        int maxGoalkeeperMatches = 0;
        for (var p in allPlayers) {
          if (p.isGoalkeeper && p.matchesPlayed > maxGoalkeeperMatches) {
            maxGoalkeeperMatches = p.matchesPlayed;
          }
        }
        
        int minRequiredMatches = 3;
        if (maxGoalkeeperMatches < 3) {
          minRequiredMatches = maxGoalkeeperMatches;
        }
        if (minRequiredMatches == 0) minRequiredMatches = 1;

        final goalkeepers = allPlayers.where((p) {
          if (!p.isGoalkeeper) return false;
          if (maxGoalkeeperMatches == 0) return true; // Se ninguém jogou, mostra todos
          return p.matchesPlayed >= minRequiredMatches && p.matchesPlayed > 0;
        }).toList()
        ..sort((a, b) {
           double avgA = a.goalsConceded / a.matchesPlayed;
           double avgB = b.goalsConceded / b.matchesPlayed;
           if (avgA == avgB) {
              return b.matchesPlayed.compareTo(a.matchesPlayed); // Desempate: quem jogou mais
           }
           return avgA.compareTo(avgB); // Menor média ganha
        });

        final motm = allPlayers.where((p) => p.motmAwards > 0).toList()..sort((a, b) => b.motmAwards.compareTo(a.motmAwards));
        final pending = allPlayers.where((p) => p.yellowCards == AdminService.pendingYellowCards).toList();
        final suspended = allPlayers.where((p) => p.isSuspended).toList();
        final yellows = allPlayers.where((p) => p.totalYellowCards > 0).toList()..sort((a, b) => b.totalYellowCards.compareTo(a.totalYellowCards));
        final reds = allPlayers.where((p) => p.totalRedCards > 0).toList()..sort((a, b) => b.totalRedCards.compareTo(a.totalRedCards));

        return Scaffold(
          appBar: AppBar(
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
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: Colors.white,
              tabs: const [
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

          body: TabBarView(
            controller: _tabController,
            children: [
              GenericPlayerRankList(players: scorers, statField: 'goals', statLabel: 'Gols', emptyMessage: 'Nenhum gol marcado.', emptyIcon: Icons.sports_soccer),
              GenericPlayerRankList(players: assists, statField: 'assists', statLabel: 'Ass', emptyMessage: 'Nenhuma assistência.', emptyIcon: Icons.assistant),
              GenericPlayerRankList(players: goalkeepers, statField: 'goals_conceded_avg', statLabel: 'GS/Jogo', emptyMessage: 'Sem dados de goleiros.', emptyIcon: Icons.pan_tool),
              GenericPlayerRankList(players: motm, statField: 'motmAwards', statLabel: 'x', emptyMessage: 'Nenhum craque eleito.', emptyIcon: Icons.star),
              GenericPlayerRankList(players: pending, isStatusList: true, emptyMessage: 'Ninguém pendurado.', emptyIcon: Icons.mood),
              GenericPlayerRankList(players: suspended, isStatusList: true, isSuspendedTab: true, emptyMessage: 'Ninguém suspenso.', emptyIcon: Icons.check_circle_outline),
              GenericPlayerRankList(players: yellows, statField: 'totalYellowCards', statLabel: 'CA', emptyMessage: 'Sem cartões.', emptyIcon: Icons.style_outlined),
              GenericPlayerRankList(players: reds, statField: 'totalRedCards', statLabel: 'CV', emptyMessage: 'Sem cartões.', emptyIcon: Icons.style),
              TotalCardsRankList(allPlayers: allPlayers),
            ],
          ),
          bottomNavigationBar: const MainBottomNavBar(currentRoute: '/player-stats'),
        );
      }
    );
  }
}