import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart'; // <-- Importante
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/rank_indicator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'team_detail_screen.dart';
import '../services/admin_service.dart';
import '../services/championship_service.dart'; // <-- Importante
import '../services/firestore_service.dart'; // <-- Importante

class TeamStatsScreen extends StatelessWidget {
  const TeamStatsScreen({super.key});

  Future<void> _showTeamStatsHelp(BuildContext context) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Ajuda: Estatísticas das Equipes'),
          content: SingleChildScrollView(
            child: RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15), 
                children: <TextSpan>[
                  const TextSpan(text: 'Esta tela mostra os rankings e o status disciplinar das equipes.\n\n'),
                  const TextSpan(text: 'Melhor Ataque:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Ranking de equipes com mais gols.\n\n'),
                  const TextSpan(text: 'Melhor Defesa:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Ranking de equipes com menos gols sofridos.\n\n'),
                  const TextSpan(text: 'Cartões Amarelos:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Soma-se o total de cartões amarelos que a equipe levou.\n\n'),
                  const TextSpan(text: 'Cartões Vermelhos:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Soma-se o total de cartões vermelhos.\n\n'),
                  const TextSpan(text: 'Total de Cartões:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Soma-se o total de CV e CA.\n\n'),
                  const TextSpan(text: 'Fair Play (PD):\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Ranking de equipes com menos Pontos Disciplinares (ordem ascendente). Critério de desempate.\n\n'),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(child: const Text('Fechar'), onPressed: () => Navigator.of(dialogContext).pop()),
          ],
        );
      },
    );
  }

  // Helper para obter a Query correta
  Query _getTeamsQuery(String seasonId) {
    if (seasonId == FirestoreService.LEGACY_ID) {
      return FirebaseFirestore.instance.collection('teams');
    } else {
      return FirebaseFirestore.instance
          .collection('championships')
          .doc(seasonId)
          .collection('teams_participation');
    }
  }

  Widget _buildRankingList({
    required BuildContext context,
    required Query query,
    required String statField,
    required String statLabel,
    required String emptyMessage,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) {
          debugPrint("\n🔴 ERRO TEAM STATS ($statLabel): ${snapshot.error}");
          return Center(child: SelectableText('Erro: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return Center(child: Text(emptyMessage));

        final teams = snapshot.data!.docs;

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Column(
            children: [
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: teams.length,
                itemBuilder: (context, index) {
                  final team = teams[index];
                  final data = team.data() as Map<String, dynamic>;
                  final rank = index + 1;
                  final String shieldUrl = data['shield_url'] ?? '';
                  final int statValue = data[statField] ?? 0;

                  Widget trailingWidget;
                  if (statLabel == 'CA') {
                    trailingWidget = Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('$statValue', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(width: 4),
                      Icon(Icons.style, color: Colors.yellow[700], size: 20),
                    ]);
                  } else if (statLabel == 'CV') {
                    trailingWidget = Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('$statValue', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(width: 4),
                      Icon(Icons.style, color: Colors.red[700], size: 20),
                    ]);
                  } else { 
                    trailingWidget = Text('$statValue $statLabel', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16));
                  }

                  return ListTile(
                    leading: RankIndicator(rank: rank),
                    title: Row(
                      children: [
                        if (shieldUrl.isNotEmpty)
                           Padding(
                             padding: const EdgeInsets.only(right: 8.0),
                             child: SizedBox(
                               width: 25, height: 25,
                               child: CachedNetworkImage(
                                 imageUrl: shieldUrl,
                                 placeholder: (c, u) => const Icon(Icons.shield, size: 20, color: Colors.grey),
                                 errorWidget: (c, u, e) => const Icon(Icons.shield, size: 25, color: Colors.grey),
                                 fit: BoxFit.contain,
                               ),
                             ),
                           ),
                         Expanded(child: Text(data['name'] ?? 'Nome Indisponível', overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                    trailing: trailingWidget,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => TeamDetailScreen(teamDoc: team))),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

   Widget _buildTotalCardsList({
    required BuildContext context,
    required Stream<QuerySnapshot> stream,
    required String emptyMessage,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

        if (snapshot.hasError) {
          debugPrint("\n🔴 ERRO TEAM STATS (CARTÕES): ${snapshot.error}");
          return Center(child: SelectableText('Erro: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return Center(child: Text(emptyMessage));

        List<Map<String, dynamic>> teamsData = snapshot.data!.docs.map((doc) {
           final data = doc.data() as Map<String, dynamic>;
           final yellow = data['total_yellow_cards'] ?? 0;
           final red = data['total_red_cards'] ?? 0;
           return {
             'doc': doc,
             'name': data['name'] ?? '?',
             'shield_url': data['shield_url'] ?? '',
             'yellow_cards': yellow,
             'red_cards': red,
             'total_cards': yellow + red,
           };
        }).toList();

        teamsData.removeWhere((team) => team['total_cards'] == 0);
        teamsData.sort((a, b) {
           int totalComp = a['total_cards'].compareTo(b['total_cards']); 
           if (totalComp != 0) return totalComp;
           return a['name'].compareTo(b['name']);
        });
        
        if (teamsData.isEmpty) return Center(child: Text(emptyMessage));

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Column(
            children: [
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: teamsData.length,
                itemBuilder: (context, index) {
                  final teamMap = teamsData[index];
                  final teamDoc = teamMap['doc'] as DocumentSnapshot;
                  final rank = index + 1;
                  final String shieldUrl = teamMap['shield_url'];
                  final int totalCards = teamMap['total_cards'];
                  final int yellowCards = teamMap['yellow_cards'];
                  final int redCards = teamMap['red_cards'];

                  return ListTile(
                    leading: RankIndicator(rank: rank),
                    title: Row(
                      children: [
                          if (shieldUrl.isNotEmpty)
                             Padding(
                               padding: const EdgeInsets.only(right: 8.0),
                               child: SizedBox(
                                 width: 25, height: 25,
                                 child: CachedNetworkImage(
                                   imageUrl: shieldUrl,
                                   errorWidget: (c, u, e) => const Icon(Icons.shield, size: 25, color: Colors.grey),
                                   fit: BoxFit.contain,
                                 ),
                               ),
                             ),
                           Expanded(child: Text(teamMap['name'], overflow: TextOverflow.ellipsis)),
                        ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('$totalCards Cartões', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                         Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('$yellowCards', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            Icon(Icons.style, color: Colors.yellow[700], size: 14),
                            const Text(' / ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            Text('$redCards', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            Icon(Icons.style, color: Colors.red[700], size: 14),
                          ],
                        )
                      ],
                    ),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => TeamDetailScreen(teamDoc: teamDoc))),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFairPlayList({
    required BuildContext context,
    required Query query,
    required String emptyMessage,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

        if (snapshot.hasError) {
          debugPrint("\n🔴 ERRO TEAM STATS (FAIR PLAY): ${snapshot.error}");
          return Center(child: SelectableText('Erro: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return Center(child: Text(emptyMessage));

        final teams = snapshot.data!.docs;

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Column(
            children: [
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: teams.length,
                itemBuilder: (context, index) {
                  final team = teams[index];
                  final data = team.data() as Map<String, dynamic>;
                  final rank = index + 1;
                  final String shieldUrl = data['shield_url'] ?? '';
                  
                  final int statValue = data['disciplinary_points'] ?? 0;
                  final int yellowCards = data['total_yellow_cards'] ?? 0;
                  final int redCards = data['total_red_cards'] ?? 0;

                  return ListTile(
                    leading: RankIndicator(rank: rank),
                    title: Row(
                      children: [
                        if (shieldUrl.isNotEmpty)
                           Padding(
                             padding: const EdgeInsets.only(right: 8.0),
                             child: SizedBox(
                               width: 25, height: 25,
                               child: CachedNetworkImage(imageUrl: shieldUrl, errorWidget: (c, u, e) => const Icon(Icons.shield, size: 25, color: Colors.grey), fit: BoxFit.contain),
                             ),
                           ),
                         Expanded(child: Text(data['name'] ?? 'Nome Indisponível', overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('$statValue PD', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('$yellowCards', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            Icon(Icons.style, color: Colors.yellow[700], size: 14),
                            const Text(' / ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            Text('$redCards', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            Icon(Icons.style, color: Colors.red[700], size: 14),
                          ],
                        )
                      ],
                    ),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => TeamDetailScreen(teamDoc: team))),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. Recupera a Temporada Atual
    final championshipService = Provider.of<ChampionshipService>(context);
    final seasonId = championshipService.currentSeasonId;
    final seasonName = championshipService.currentSeasonName;

    // 2. Base da Query
    final baseQuery = _getTeamsQuery(seasonId);

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
          actions: [
            IconButton(
              icon: const Icon(Icons.help_outline),
              tooltip: 'Ajuda',
              onPressed: () => _showTeamStatsHelp(context),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Melhor Ataque'),
              Tab(text: 'Melhor Defesa'),
              Tab(text: 'Cartões Amarelos'),
              Tab(text: 'Cartões Vermelhos'),
              Tab(text: 'Total de Cartões'),
              Tab(text: 'Fair Play (PD)'),
            ],
          ),
        ),
        drawer: const AppDrawer(),
        body: TabBarView(
          children: [
            _buildRankingList(
              context: context,
              query: baseQuery.orderBy('goals_for', descending: true).orderBy('name'),
              statField: 'goals_for', statLabel: 'GP', emptyMessage: 'Sem gols marcados.',
            ),
            _buildRankingList(
              context: context,
              query: baseQuery.orderBy('goals_against', descending: false).orderBy('name'),
              statField: 'goals_against', statLabel: 'GC', emptyMessage: 'Sem gols sofridos.',
            ),
            _buildRankingList(
              context: context,
              query: baseQuery.where('total_yellow_cards', isGreaterThan: 0).orderBy('total_yellow_cards', descending: true).orderBy('name'),
              statField: 'total_yellow_cards', statLabel: 'CA', emptyMessage: 'Sem cartões amarelos.',
            ),
            _buildRankingList(
              context: context,
              query: baseQuery.where('total_red_cards', isGreaterThan: 0).orderBy('total_red_cards', descending: true).orderBy('name'),
              statField: 'total_red_cards', statLabel: 'CV', emptyMessage: 'Sem cartões vermelhos.',
            ),
             _buildTotalCardsList(
               context: context,
               stream: baseQuery.snapshots(),
               emptyMessage: 'Sem cartões.',
             ),
            _buildFairPlayList(
              context: context,
              query: baseQuery.where('disciplinary_points', isGreaterThan: 0).orderBy('disciplinary_points', descending: false).orderBy('name'),
              emptyMessage: 'Sem pontos disciplinares.',
            ),
          ],
        ),
        bottomNavigationBar: const SponsorBannerRotator(),
      ),
    );
  }
}