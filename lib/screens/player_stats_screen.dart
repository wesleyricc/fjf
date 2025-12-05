import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/admin_service.dart';
import '../services/championship_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/generic_player_rank_list.dart'; 
import '../widgets/total_cards_rank_list.dart';    

class PlayerStatsScreen extends StatelessWidget {
  const PlayerStatsScreen({super.key});

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
    final championshipService = Provider.of<ChampionshipService>(context);
    final seasonId = championshipService.currentSeasonId;
    final seasonName = championshipService.currentSeasonName;
    
    // ALTERAÇÃO: Define a referência base sempre para a temporada atual
    // Removemos a verificação de LEGACY_ID
    final Query baseQuery = FirebaseFirestore.instance
        .collection('championships')
        .doc(seasonId)
        .collection('player_stats');

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
          actions: [IconButton(icon: const Icon(Icons.help_outline), onPressed: () => _showHelp(context))],
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
            // 1. Artilheiros
            GenericPlayerRankList(
              baseQuery: baseQuery.where('isActive', isEqualTo: true).where('is_staff', isEqualTo: false).where('goals', isGreaterThan: 0).orderBy('goals', descending: true).orderBy('name'),
              statField: 'goals', statLabel: 'Gols', emptyMessage: 'Nenhum gol marcado.',
            ),
            // 2. Assistências
            GenericPlayerRankList(
              baseQuery: baseQuery.where('isActive', isEqualTo: true).where('is_staff', isEqualTo: false).where('assists', isGreaterThan: 0).orderBy('assists', descending: true).orderBy('name'),
              statField: 'assists', statLabel: 'Ass', emptyMessage: 'Nenhuma assistência.',
            ),
            // 3. Goleiros
            GenericPlayerRankList(
              baseQuery: baseQuery.where('isActive', isEqualTo: true).where('is_goalkeeper', isEqualTo: true).orderBy('goals_conceded', descending: false).orderBy('name'),
              statField: 'goals_conceded', statLabel: 'GS', emptyMessage: 'Sem dados de goleiros.',
            ),
            // 4. Craque
            GenericPlayerRankList(
              baseQuery: baseQuery.where('isActive', isEqualTo: true).where('man_of_the_match_awards', isGreaterThan: 0).orderBy('man_of_the_match_awards', descending: true).orderBy('name'),
              statField: 'man_of_the_match_awards', statLabel: 'x', emptyMessage: 'Nenhum craque eleito.',
            ),
            // 5. Pendurados
            GenericPlayerRankList(
              baseQuery: baseQuery.where('isActive', isEqualTo: true).where('yellow_cards', isEqualTo: AdminService.pendingYellowCards).orderBy('name'),
              emptyMessage: 'Ninguém pendurado.', isStatusList: true,
            ),
            // 6. Suspensos
            GenericPlayerRankList(
              baseQuery: baseQuery.where('isActive', isEqualTo: true).where('is_suspended', isEqualTo: true).orderBy('name'),
              emptyMessage: 'Ninguém suspenso.', isStatusList: true, isSuspendedTab: true,
            ),
            // 7. Amarelos Total
            GenericPlayerRankList(
              baseQuery: baseQuery.where('isActive', isEqualTo: true).where('total_yellow_cards', isGreaterThan: 0).orderBy('total_yellow_cards', descending: true).orderBy('name'),
              statField: 'total_yellow_cards', statLabel: 'CA', emptyMessage: 'Sem cartões.',
            ),
            // 8. Vermelhos Total
            GenericPlayerRankList(
              baseQuery: baseQuery.where('isActive', isEqualTo: true).where('total_red_cards', isGreaterThan: 0).orderBy('total_red_cards', descending: true).orderBy('name'),
              statField: 'total_red_cards', statLabel: 'CV', emptyMessage: 'Sem cartões.',
            ),
            // 9. Total (Client Side)
            TotalCardsRankList(
              baseQuery: baseQuery.where('isActive', isEqualTo: true),
              emptyMessage: 'Sem cartões registrados.',
            ),
          ],
        ),
        bottomNavigationBar: const SponsorBannerRotator(),
      ),
    );
  }
}