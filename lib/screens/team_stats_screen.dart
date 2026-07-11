import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/championship_service.dart';
import '../services/admin_service.dart';
import '../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../models/team_model.dart'; 


import '../widgets/main_bottom_nav_bar.dart';
import '../widgets/rank_indicator.dart';
import '../widgets/rank_highlight_card.dart';
import '../widgets/ui/shimmer_effect.dart';     
import '../widgets/ui/custom_empty_state.dart';  
import 'team_detail_screen.dart';
import '../theme/app_theme.dart'; 

class TeamStatsScreen extends StatefulWidget {
  const TeamStatsScreen({super.key});

  @override
  State<TeamStatsScreen> createState() => _TeamStatsScreenState();
}

class _TeamStatsScreenState extends State<TeamStatsScreen> with SingleTickerProviderStateMixin {
  bool _showOverall = false; 
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    
    // 🚨 Analytics: Inicialização Dinâmica
    _tabController = TabController(length: 6, vsync: this);
    AnalyticsService.logCustomScreenView('Team_Stats_Screen_Tab_Melhor_Ataque'); // Padrão
    
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final tabs = ['Melhor_Ataque', 'Melhor_Defesa', 'Amarelos', 'Vermelhos', 'Total_Cartoes', 'Fair_Play'];
        AnalyticsService.logCustomScreenView('Team_Stats_Screen_Tab_${tabs[_tabController.index]}');
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _showHelp(BuildContext context) async {
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
                  const TextSpan(text: 'Fair Play (PD):\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Ranking de equipes com menos Pontos Disciplinares (ordem ascendente). Este é o critério de desempate na classificação.\n\n'),
                  const TextSpan(text: 'Regra Geral de Suspensão:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: '- Um atleta é suspenso quando toma 1 CV ou ${AdminService.suspensionYellowCards} CA em jogos diferentes (2 CA no mesmo joga contabiliza-se apenas um para regra de Suspensão);\n'),
                  const TextSpan(text: '- Se um atleta vem para o jogo com 1 CA acumulado e levar 2CA e 1CV no jogo, ele irá cumprir suspensão pelo CV, e seus CA seguem acumulados;\n'),
                  TextSpan(text: '- Se um atleta vem para o jogo pendurado (${AdminService.pendingYellowCards} CA) e levar 2CA e 1CV no jogo, ele irá cumprir suspensão dobrada, pelo CV e pelos CA acumulados.\n\n'),
                  const TextSpan(text: 'Regra Geral de Zeramento de Cartões:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Um atleta tem seus CA zerados apenas quando cumpre suspensão por levar 3CA.\n'),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Fechar'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChampionshipService>(
      builder: (context, champService, child) {
        final seasonName = champService.currentSeasonName;
        final allTeams = champService.teams; 
        final bool isLoading = champService.isLoading;

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
                const Text('Estatísticas das Equipes'),
                Text(seasonName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w300)),
              ],
            ),
            actions: [
              Row(
                children: [
                  Text(
                    _showOverall ? "Geral" : "1ª Fase",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  Switch(
                    value: _showOverall,
                    activeColor: Colors.white,
                    activeTrackColor: Colors.greenAccent,
                    inactiveThumbColor: Colors.white,
                    inactiveTrackColor: Colors.white24,
                    onChanged: (val) {
                      setState(() => _showOverall = val);
                      // 🚨 Analytics: Registra o uso do filtro (Geral vs 1ª Fase)
                      AnalyticsService.logCustomScreenView(
                        'Team_Stats_Screen_Toggle',
                        parameters: {'mode': val ? 'Geral' : '1a_Fase'}
                      );
                    },
                  ),
                ],
              ),
              IconButton(icon: const Icon(Icons.help_outline), onPressed: () => _showHelp(context)),
              IconButton(
                icon: const Icon(Icons.refresh), 
                tooltip: "Atualizar Dados",
                onPressed: () => champService.fetchStaticData(forceRefresh: true),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: Colors.white,
              tabs: const [
                Tab(text: 'Melhor Ataque'),
                Tab(text: 'Melhor Defesa'),
                Tab(text: 'Amarelos'),
                Tab(text: 'Vermelhos'),
                Tab(text: 'Total Cartões'),
                Tab(text: 'Fair Play (PD)'),
              ],
            ),
          ),

          
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildRankingList(context, allTeams, isLoading, (t) => _showOverall ? t.overallGoalsFor : t.goalsFor, 'GP', Icons.sports_soccer, descending: true, champService: champService),
              _buildRankingList(context, allTeams, isLoading, (t) => _showOverall ? t.overallGoalsAgainst : t.goalsAgainst, 'GC', Icons.gpp_good, descending: false, champService: champService), 
              _buildRankingList(context, allTeams, isLoading, (t) => t.totalYellowCards, 'CA', Icons.style, descending: true, filterZero: true, color: Colors.amber[800], champService: champService),
              _buildRankingList(context, allTeams, isLoading, (t) => t.totalRedCards, 'CV', Icons.style, descending: true, filterZero: true, color: Colors.red, champService: champService),
              _buildRankingList(context, allTeams, isLoading, (t) => t.totalYellowCards + t.totalRedCards, 'Cartões', Icons.layers, descending: true, filterZero: true, champService: champService),
              _buildRankingList(context, allTeams, isLoading, (t) => t.disciplinaryPoints, 'PD', Icons.balance, descending: false, filterZero: true, champService: champService), 
            ],
          ),
          
          bottomNavigationBar: const MainBottomNavBar(currentRoute: '/team-stats'),
        );
      },
    );
  }

  Widget _buildRankingList(
    BuildContext context, 
    List<Team> teams,
    bool isLoading,
    int Function(Team) valueSelector, 
    String suffix, 
    IconData icon,
    {
      required bool descending,
      required ChampionshipService champService, 
      bool filterZero = false,
      Color? color
    }
  ) {

    if (champService.isOffline && teams.isEmpty) {
      return CustomEmptyState.offline(
        onRetry: () => champService.fetchStaticData(forceRefresh: true),
      );
    }

    if (isLoading && teams.isEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 6,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.only(bottom: 12.0),
          child: Row(
            children: [
              ShimmerEffect.circular(size: 40),
              SizedBox(width: 16),
              Expanded(child: ShimmerEffect.rectangular(height: 16)),
              SizedBox(width: 16),
              ShimmerEffect.rectangular(height: 16, width: 40),
            ],
          ),
        ),
      );
    }

    var list = List<Team>.from(teams);
    if (filterZero) {
      list = list.where((t) => valueSelector(t) > 0).toList();
    }
    
    list.sort((a, b) {
      final va = valueSelector(a);
      final vb = valueSelector(b);
      return descending ? vb.compareTo(va) : va.compareTo(vb);
    });

    if (list.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => champService.fetchStaticData(forceRefresh: true),
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              child: CustomEmptyState(
                icon: Icons.query_stats,
                title: "Sem Estatísticas",
                message: "Ainda não há dados suficientes para gerar este ranking.",
                buttonText: "Atualizar",
                onButtonPressed: () => champService.fetchStaticData(forceRefresh: true),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => champService.fetchStaticData(forceRefresh: true),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 16, top: 8),
        itemCount: list.length,
        itemBuilder: (context, index) {
          final team = list[index];
          final rank = index + 1;
          final val = valueSelector(team);

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
                    child: Hero(
                      tag: 'stat_shield_${team.id}_$suffix', 
                      child: CachedNetworkImage(
                        imageUrl: team.shieldUrl, 
                        width: 25, height: 25, 
                        fit: BoxFit.contain,
                        memCacheWidth: 100,
                        memCacheHeight: 100,
                        placeholder: (_,__) => Container(color: Colors.transparent),
                        errorWidget: (_,__,___) => const Icon(Icons.shield, size: 25, color: Colors.grey),
                      ),
                    ),
                  ),
                Expanded(child: Text(team.name, overflow: TextOverflow.ellipsis)),
              ],
            ),
            trailing: trailing,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TeamDetailScreen(team: team, heroTag: 'stat_shield_${team.id}_$suffix'))), 
          );
        },
      ),
    );
  }
}