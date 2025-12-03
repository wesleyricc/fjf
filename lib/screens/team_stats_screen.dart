import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Services & Models
import '../services/championship_service.dart';
import '../services/firestore_service.dart';
import '../models/team_model.dart'; // <-- Importante: Model Team

// Widgets & Screens
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/rank_indicator.dart';
import 'team_detail_screen.dart';

class TeamStatsScreen extends StatelessWidget {
  const TeamStatsScreen({super.key});

  Future<void> _showHelp(BuildContext context) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Legenda'),
        content: const SingleChildScrollView(
          child: Text(
            "• Ataque: Times com mais gols marcados.\n"
            "• Defesa: Times com menos gols sofridos.\n"
            "• Fair Play: Menor pontuação disciplinar (Critério de desempate)."
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final championshipService = Provider.of<ChampionshipService>(context);
    final seasonId = championshipService.currentSeasonId;
    final seasonName = championshipService.currentSeasonName;
    final firestoreService = FirestoreService();

    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Estatísticas das Equipes'),
              Text(seasonName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w300)),
            ],
          ),
          actions: [IconButton(icon: const Icon(Icons.help_outline), onPressed: () => _showHelp(context))],
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Melhor Ataque'),
              Tab(text: 'Melhor Defesa'),
              Tab(text: 'Amarelos'),
              Tab(text: 'Vermelhos'),
              Tab(text: 'Total Cartões'),
              Tab(text: 'Fair Play (PD)'),
            ],
          ),
        ),
        drawer: const AppDrawer(),
        // StreamBuilder único para toda a tela
        body: StreamBuilder<List<Team>>(
          stream: firestoreService.streamTeams(seasonId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            
            final allTeams = snapshot.data ?? [];
            if (allTeams.isEmpty) return const Center(child: Text("Nenhuma equipe encontrada."));

            return TabBarView(
              children: [
                _buildRankingList(context, allTeams, (t) => t.goalsFor, 'GP', descending: true),
                _buildRankingList(context, allTeams, (t) => t.goalsAgainst, 'GC', descending: false), // Menos é melhor
                _buildRankingList(context, allTeams, (t) => t.totalYellowCards, 'CA', descending: true, filterZero: true, isCard: true, color: Colors.yellow[700]),
                _buildRankingList(context, allTeams, (t) => t.totalRedCards, 'CV', descending: true, filterZero: true, isCard: true, color: Colors.red),
                _buildRankingList(context, allTeams, (t) => t.totalYellowCards + t.totalRedCards, 'Cartões', descending: true, filterZero: true),
                _buildRankingList(context, allTeams, (t) => t.disciplinaryPoints, 'PD', descending: false, filterZero: true), // Menos é melhor
              ],
            );
          },
        ),
        bottomNavigationBar: const SponsorBannerRotator(),
      ),
    );
  }

  Widget _buildRankingList(
    BuildContext context, 
    List<Team> teams, 
    int Function(Team) valueSelector, 
    String suffix, 
    {
      required bool descending, 
      bool filterZero = false,
      bool isCard = false,
      Color? color
    }
  ) {
    // 1. Filtra e Ordena em Memória
    var list = List<Team>.from(teams);
    if (filterZero) {
      list = list.where((t) => valueSelector(t) > 0).toList();
    }
    
    list.sort((a, b) {
      final va = valueSelector(a);
      final vb = valueSelector(b);
      return descending ? vb.compareTo(va) : va.compareTo(vb);
    });

    if (list.isEmpty) return Center(child: Text("Sem dados para '$suffix'."));

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final team = list[index];
        final rank = index + 1;
        final val = valueSelector(team);

        Widget trailing;
        if (isCard && color != null) {
          trailing = Row(mainAxisSize: MainAxisSize.min, children: [
            Text('$val', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(width: 4),
            Icon(Icons.style, color: color, size: 20),
          ]);
        } else {
          trailing = Text('$val $suffix', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16));
        }

        return ListTile(
          leading: RankIndicator(rank: rank),
          title: Row(
            children: [
              if (team.shieldUrl.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: CachedNetworkImage(imageUrl: team.shieldUrl, width: 25, height: 25, fit: BoxFit.contain),
                ),
              Expanded(child: Text(team.name, overflow: TextOverflow.ellipsis)),
            ],
          ),
          trailing: trailing,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TeamDetailScreen(team: team))),
        );
      },
    );
  }
}