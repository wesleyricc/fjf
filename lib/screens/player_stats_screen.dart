import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/admin_service.dart';
import '../services/championship_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/generic_player_rank_list.dart'; 
import '../widgets/total_cards_rank_list.dart';    
import '../models/player_model.dart'; 

class PlayerStatsScreen extends StatefulWidget {
  const PlayerStatsScreen({super.key});

  @override
  State<PlayerStatsScreen> createState() => _PlayerStatsScreenState();
}

class _PlayerStatsScreenState extends State<PlayerStatsScreen> {
  
  @override
  void initState() {
    super.initState();
    // Como os jogadores agora são lazy-loaded, precisamos forçar o download de todos
    // para montar o ranking global corretamente.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ChampionshipService>(context, listen: false).fetchAllPlayers();
    });
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
    // 1. Obtém a lista completa do Cache
    return Consumer<ChampionshipService>(
      builder: (context, service, _) {
        final seasonName = service.currentSeasonName;
        
        // Clona a lista para não afetar o cache original durante a ordenação
        final List<Player> allPlayers = List.from(service.allPlayers);

        // Se a lista estiver vazia e estiver carregando, mostra loading
        if (allPlayers.isEmpty && service.isLoading) {
          return Scaffold(
            appBar: AppBar(title: const Text("Estatísticas")),
            drawer: const AppDrawer(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        // Artilheiros
        final scorers = allPlayers.where((p) => !p.isStaff && p.goals > 0).toList()
          ..sort((a, b) => b.goals.compareTo(a.goals));
        
        // Assistências
        final assists = allPlayers.where((p) => !p.isStaff && p.assists > 0).toList()
          ..sort((a, b) => b.assists.compareTo(a.assists));
        
        // Goleiros
        final goalkeepers = allPlayers.where((p) => p.isGoalkeeper).toList()
          ..sort((a, b) => a.goalsConceded.compareTo(b.goalsConceded)); // Menor é melhor
        
        // Craques
        final motm = allPlayers.where((p) => p.motmAwards > 0).toList()
          ..sort((a, b) => b.motmAwards.compareTo(a.motmAwards));
        
        // Pendurados
        final pending = allPlayers.where((p) => p.yellowCards == AdminService.pendingYellowCards).toList();
        
        // Suspensos
        final suspended = allPlayers.where((p) => p.isSuspended).toList();
        
        // Amarelos Total
        final yellows = allPlayers.where((p) => p.totalYellowCards > 0).toList()
          ..sort((a, b) => b.totalYellowCards.compareTo(a.totalYellowCards));
        
        // Vermelhos Total
        final reds = allPlayers.where((p) => p.totalRedCards > 0).toList()
          ..sort((a, b) => b.totalRedCards.compareTo(a.totalRedCards));

        return DefaultTabController(
          length: 9,
          child: Scaffold(
            appBar: AppBar(
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
                  // Recarrega tudo forçado
                  onPressed: () => service.fetchAllPlayers(force: true)
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
                GenericPlayerRankList(players: scorers, statField: 'goals', statLabel: 'Gols', emptyMessage: 'Nenhum gol marcado.'),
                GenericPlayerRankList(players: assists, statField: 'assists', statLabel: 'Ass', emptyMessage: 'Nenhuma assistência.'),
                GenericPlayerRankList(players: goalkeepers, statField: 'goalsConceded', statLabel: 'GS', emptyMessage: 'Sem dados de goleiros.'),
                GenericPlayerRankList(players: motm, statField: 'motmAwards', statLabel: 'x', emptyMessage: 'Nenhum craque eleito.'),
                GenericPlayerRankList(players: pending, isStatusList: true, emptyMessage: 'Ninguém pendurado.'),
                GenericPlayerRankList(players: suspended, isStatusList: true, isSuspendedTab: true, emptyMessage: 'Ninguém suspenso.'),
                GenericPlayerRankList(players: yellows, statField: 'totalYellowCards', statLabel: 'CA', emptyMessage: 'Sem cartões.'),
                GenericPlayerRankList(players: reds, statField: 'totalRedCards', statLabel: 'CV', emptyMessage: 'Sem cartões.'),
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