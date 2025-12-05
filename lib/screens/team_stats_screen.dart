import 'package:fjf_app/services/admin_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Services & Models
import '../services/championship_service.dart';
import '../services/firestore_service.dart';
import '../models/team_model.dart'; 

// Widgets & Screens
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/rank_indicator.dart';
import '../widgets/rank_highlight_card.dart'; // <-- Novo Widget
import 'team_detail_screen.dart';

class TeamStatsScreen extends StatelessWidget {
  const TeamStatsScreen({super.key});

  Future<void> _showHelp(BuildContext context) async {
    // ... (A sua função de ajuda, sem alterações)
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
                  const TextSpan(text: 'Soma-se o total de cartões amarelos que a equipe levou e que contabilizam para a pontuação disciplinar. Conforme definido no regulamento do campeonato e pela CBFS. Ex: 2CA e 1CV no mesmo jogo, contabiliza-se nesta guia, apenas 1 CA.\n\n'),

                  const TextSpan(text: 'Cartões Vermelhos:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Soma-se o total de cartões vermelhos registrados em súmula.\n\n'),

                  const TextSpan(text: 'Total de Cartões:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Soma-se o total de CV e CA que a equipe levou e que contabilizam para a pontuação disciplinar. Conforme definido no regulamento do campeonato e pela CBFS. Ex: 2CA e 1CV no mesmo jogo, contabiliza-se nesta guia, apenas 1 CA e 1 CV.\n\n'),

                  // --- INÍCIO DA ALTERAÇÃO (Adicionada nova legenda) ---
                  const TextSpan(text: 'Fair Play (PD):\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Ranking de equipes com menos Pontos Disciplinares (ordem ascendente). Este é o critério de desempate na classificação.\n\n'),
                  // --- FIM DA ALTERAÇÃO ---

                  const TextSpan(text: 'Regra Geral de Suspensão:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: '- Um atleta é suspenso quando toma 1 CV ou ${AdminService.suspensionYellowCards} CA em jogos diferentes (2 CA no mesmo joga contabiliza-se apenas um para regra de Suspensão);\n'),
                  const TextSpan(text: '- Se um atleta vem para o jogo com 1 CA acumulado e levar 2CA e 1CV no jogo, ele irá cumprimir suspensão pelo CV, e seus CA seguem acumulados;\n'),
                  TextSpan(text: '- Se um atleta vem para o jogo pendurado (${AdminService.pendingYellowCards} CA) e levar 2CA e 1CV no jogo, ele irá cumprimir suspensão dobrada, pelo CV e pelos CA acumulados.\n\n'),
                  
                  const TextSpan(text: 'Regra Geral de Zeramento de Cartões:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Um atleta tem seus CA zerados apenas quando cumpre suspensão por levar 3CA.\n'),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Fechar'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
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
        body: StreamBuilder<List<Team>>(
          stream: firestoreService.streamTeams(seasonId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            
            final allTeams = snapshot.data ?? [];
            if (allTeams.isEmpty) return const Center(child: Text("Nenhuma equipe encontrada."));

            return TabBarView(
              children: [
                _buildRankingList(context, allTeams, (t) => t.goalsFor, 'GP', Icons.sports_soccer, descending: true),
                _buildRankingList(context, allTeams, (t) => t.goalsAgainst, 'GC', Icons.gpp_good, descending: false), 
                _buildRankingList(context, allTeams, (t) => t.totalYellowCards, 'CA', Icons.style, descending: true, filterZero: true, color: Colors.amber[800]),
                _buildRankingList(context, allTeams, (t) => t.totalRedCards, 'CV', Icons.style, descending: true, filterZero: true, color: Colors.red),
                _buildRankingList(context, allTeams, (t) => t.totalYellowCards + t.totalRedCards, 'Cartões', Icons.layers, descending: true, filterZero: true),
                _buildRankingList(context, allTeams, (t) => t.disciplinaryPoints, 'PD', Icons.balance, descending: false, filterZero: true), 
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
    IconData icon,
    {
      required bool descending, 
      bool filterZero = false,
      Color? color
    }
  ) {
    // 1. Filtra e Ordena
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
      padding: const EdgeInsets.only(bottom: 16, top: 8),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final team = list[index];
        final rank = index + 1;
        final val = valueSelector(team);

        // --- TOP 3 (Destaque) ---
        if (index < 3) {
          return RankHighlightCard(
            rank: rank,
            title: team.name,
            subtitle: team.shortName.isNotEmpty ? team.shortName : "Equipe",
            imageUrl: team.shieldUrl,
            statValue: '$val',
            statLabel: suffix,
            statIcon: icon,
            customColor: color,
            isPlayer: false,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TeamDetailScreen(team: team))),
          );
        }

        // --- RESTO DA LISTA (Padrão) ---
        Widget trailing;
        if (color != null) {
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