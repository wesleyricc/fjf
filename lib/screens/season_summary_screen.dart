import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

// Services & Models
import '../services/championship_service.dart';
import '../services/award_service.dart';
import '../services/auth_service.dart';
import '../models/team_model.dart';
import '../models/match_model.dart';
import '../models/award_model.dart';

// Widgets
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/award_card.dart';
import 'edit_award_screen.dart';
import '../theme/app_theme.dart'; // <-- NOVO IMPORT

class SeasonSummaryScreen extends StatefulWidget {
  const SeasonSummaryScreen({super.key});

  @override
  State<SeasonSummaryScreen> createState() => _SeasonSummaryScreenState();
}

class _SeasonSummaryScreenState extends State<SeasonSummaryScreen> {
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ChampionshipService>(context, listen: false).fetchAllPlayers();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChampionshipService>(
      builder: (context, champService, _) {
        final seasonName = champService.currentSeasonName;
        final authService = Provider.of<AuthService>(context);
        final isAdmin = authService.isAuthenticated;

        if (champService.allPlayers.isEmpty && champService.isLoading) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Resumo da Temporada'),
            // 🚨 NOVO: Gradiente da Copa aplicado
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: AppTheme.brazilGradient,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => champService.fetchStaticData(forceRefresh: true),
              )
            ],
          ),
          drawer: const AppDrawer(),
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Center(
                    child: Column(
                      children: [
                        Text(seasonName.toUpperCase(), style: const TextStyle(fontSize: 12, letterSpacing: 2.0, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text("HALL DA FAMA", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Theme.of(context).primaryColor)),
                      ],
                    ),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: _buildChampionSection(context, champService),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 32)),
              
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionTitle("Destaques das Equipes"),
                      const SizedBox(height: 4),
                      const Text(
                        "* Todas as estatísticas consideram os dados do campeonato completo.", 
                        style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)
                      ),
                      const SizedBox(height: 12),
                      _buildTeamStatsGrid(context, champService),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 32)),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionTitle("Destaques Individuais"),
                      const SizedBox(height: 4),
                      const Text(
                        "* Todas as estatísticas consideram os dados do campeonato completo.", 
                        style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)
                      ),
                      const SizedBox(height: 12),
                      _buildPlayerStatsGrid(context, champService),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 32)),
              
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionTitle("Premiações Oficiais"),
                      if (isAdmin)
                        IconButton(
                          icon: const Icon(Icons.add_circle, color: Colors.green),
                          tooltip: "Adicionar Prêmio",
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditAwardScreen())),
                        ),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              _buildAwardsSliverGrid(context, champService.currentSeasonId, isAdmin),

              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
          bottomNavigationBar: const SponsorBannerRotator(),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        const Icon(Icons.stars, size: 20, color: Colors.amber),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildChampionSection(BuildContext context, ChampionshipService service) {
    final matches = service.matches;
    final teams = service.teams;
    
    final finalMatch = matches.firstWhere(
      (m) => (m.phase == 'final' || m.phase == 'final_game'),
      orElse: () => MatchModel(id: '', location: '', round: 0, phase: '', status: '', homeTeamId: '', homeTeamName: '', homeTeamShield: '', awayTeamId: '', awayTeamName: '', awayTeamShield: ''),
    );

    Team? champion;
    
    if (finalMatch.id.isNotEmpty && finalMatch.isFinished) {
      String? champId = finalMatch.winnerTeamId;
      
      if (champId == null || champId.isEmpty) {
        final homeScore = finalMatch.scoreHome ?? 0;
        final awayScore = finalMatch.scoreAway ?? 0;
        final homePen = finalMatch.penaltyScoreHome ?? 0;
        final awayPen = finalMatch.penaltyScoreAway ?? 0;
        
        if (homeScore > awayScore) {
          champId = finalMatch.homeTeamId;
        } else if (awayScore > homeScore) {
          champId = finalMatch.awayTeamId;
        } else {
          if (homePen > awayPen) champId = finalMatch.homeTeamId;
          else if (awayPen > homePen) champId = finalMatch.awayTeamId;
        }
      }

      if (champId != null && champId.isNotEmpty) {
        try {
          champion = teams.firstWhere((t) => t.id == champId);
        } catch (_) {}
      }
    }

    if (finalMatch.id.isEmpty) {
      return _buildPlaceholderChampion("Fase Final Não Definida");
    } else if (!finalMatch.isFinished) {
      return _buildPlaceholderChampion("Campeonato em Andamento");
    } else if (champion == null) {
      return _buildPlaceholderChampion("Aguardando Definição Oficial");
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFDB931)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.amber.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(
        children: [
          const Text("CAMPEÃO DA TEMPORADA", style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
          const SizedBox(height: 16),
          if (champion.shieldUrl.isNotEmpty)
            CachedNetworkImage(imageUrl: champion.shieldUrl, height: 100, fit: BoxFit.contain),
          const SizedBox(height: 12),
          Text(champion.name, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 24), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          const Text("Parabéns pela conquista!", style: TextStyle(color: Colors.black54, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildPlaceholderChampion(String text) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(20)),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.emoji_events_outlined, size: 60, color: Colors.grey),
            const SizedBox(height: 10),
            Text(text, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamStatsGrid(BuildContext context, ChampionshipService service) {
    final teams = service.teams;
    final matches = service.matches;

    if (teams.isEmpty) return const Center(child: Text("Sem dados."));

    final sortedAttack = [...teams]..sort((a, b) => b.overallGoalsFor.compareTo(a.overallGoalsFor));
    final bestAttack = sortedAttack.first;

    final sortedDefense = [...teams]..sort((a, b) => a.overallGoalsAgainst.compareTo(b.overallGoalsAgainst));
    final bestDefense = sortedDefense.first;

    final sortedFairplay = [...teams]..sort((a, b) => a.disciplinaryPoints.compareTo(b.disciplinaryPoints));
    final bestFairplay = sortedFairplay.first;

    final sortedWorst = [...teams]..sort((a, b) {
      int cmp = a.overallPoints.compareTo(b.overallPoints);
      if (cmp != 0) return cmp;
      cmp = a.overallWins.compareTo(b.overallWins);
      if (cmp != 0) return cmp;
      return a.overallGoalDifference.compareTo(b.overallGoalDifference);
    });
    final lastPlace = sortedWorst.isNotEmpty ? sortedWorst.first : null;

    MatchModel? biggestWinMatch;
    int maxDiff = -1;
    for (var m in matches) {
      if (m.isFinished && m.scoreHome != null && m.scoreAway != null) {
        int diff = (m.scoreHome! - m.scoreAway!).abs();
        if (diff > maxDiff) {
          maxDiff = diff;
          biggestWinMatch = m;
        }
      }
    }

    final List<Widget> cards = [];

    cards.add(_buildStatCard(context, title: "MELHOR ATAQUE", name: bestAttack.name, subtitle: "${bestAttack.overallGoalsFor} Gols", imageUrl: bestAttack.shieldUrl, icon: Icons.add_circle_outline, color: Colors.blue, isTeam: true));
    cards.add(_buildStatCard(context, title: "MELHOR DEFESA", name: bestDefense.name, subtitle: "${bestDefense.overallGoalsAgainst} Gols Sofridos", imageUrl: bestDefense.shieldUrl, icon: Icons.shield, color: Colors.green, isTeam: true));
    cards.add(_buildStatCard(context, title: "FAIRPLAY", name: bestFairplay.name, subtitle: "${bestFairplay.disciplinaryPoints} Pts", imageUrl: bestFairplay.shieldUrl, icon: Icons.handshake, color: Colors.teal, isTeam: true));

    if (lastPlace != null) {
      cards.add(_buildStatCard(context, title: "TROFÉU ABACAXI", name: lastPlace.name, subtitle: "Último Lugar", imageUrl: lastPlace.shieldUrl, icon: FontAwesomeIcons.faceSadTear, color: Colors.brown, isTeam: true));
    }

    if (biggestWinMatch != null) {
      final isHomeWinner = (biggestWinMatch.scoreHome ?? 0) > (biggestWinMatch.scoreAway ?? 0);
      final winnerName = isHomeWinner ? biggestWinMatch.homeTeamName : biggestWinMatch.awayTeamName;
      final loserName = isHomeWinner ? biggestWinMatch.awayTeamName : biggestWinMatch.homeTeamName;
      final score = "${biggestWinMatch.scoreHome} x ${biggestWinMatch.scoreAway}";
      
      cards.add(_buildStatCard(context, title: "MAIOR GOLEADA", name: winnerName, subtitle: "$score (vs $loserName)", imageUrl: isHomeWinner ? biggestWinMatch.homeTeamShield : biggestWinMatch.awayTeamShield, icon: Icons.local_fire_department, color: Colors.red, isTeam: true));
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: cards,
    );
  }

  Widget _buildPlayerStatsGrid(BuildContext context, ChampionshipService service) {
    final players = service.allPlayers;

    if (players.isEmpty) return const Center(child: Text("Sem dados."));

    final scorers = [...players]..sort((a, b) => b.goals.compareTo(a.goals));
    final topScorer = scorers.isNotEmpty && scorers.first.goals > 0 ? scorers.first : null;

    final assisters = [...players]..sort((a, b) => b.assists.compareTo(a.assists));
    final topAssist = assisters.isNotEmpty && assisters.first.assists > 0 ? assisters.first : null;

    final goalkeepers = players.where((p) => p.isGoalkeeper).toList();
    goalkeepers.sort((a, b) => a.goalsConceded.compareTo(b.goalsConceded));
    final bestGK = goalkeepers.isNotEmpty ? goalkeepers.first : null;

    final List<Widget> cards = [];

    if (topScorer != null) {
      cards.add(_buildStatCard(context, title: "ARTILHEIRO", name: topScorer.name, subtitle: "${topScorer.goals} Gols", imageUrl: topScorer.photoUrl, icon: Icons.sports_soccer, color: Colors.orange));
    }
    if (topAssist != null) {
      cards.add(_buildStatCard(context, title: "GARÇOM", name: topAssist.name, subtitle: "${topAssist.assists} Assists", imageUrl: topAssist.photoUrl, icon: Icons.assistant, color: Colors.cyan));
    }
    if (bestGK != null) {
      cards.add(_buildStatCard(context, title: "PAREDÃO", name: bestGK.name, subtitle: "${bestGK.goalsConceded} Gols Sofridos", imageUrl: bestGK.photoUrl, icon: Icons.pan_tool, color: Colors.purple));
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: cards,
    );
  }

  Widget _buildStatCard(BuildContext context, {
    required String title,
    required String name,
    required String subtitle,
    required String imageUrl,
    required IconData icon,
    required Color color,
    bool isTeam = false, 
  }) {
    double screenWidth = MediaQuery.of(context).size.width - 32;
    double cardWidth = (screenWidth - 10) / 2;

    return Container(
      width: cardWidth,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 10),
          
          if (isTeam) 
            Container(
              height: 60, width: 60,
              padding: const EdgeInsets.all(4),
              child: imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.contain,
                      placeholder: (c, u) => Center(child: CircularProgressIndicator(strokeWidth: 2, color: color.withOpacity(0.5))),
                      errorWidget: (c, u, e) => Icon(icon, color: color.withOpacity(0.5), size: 30),
                    )
                  : Icon(icon, color: color, size: 35),
            )
          else
            CircleAvatar(
              radius: 30,
              backgroundColor: color.withOpacity(0.1),
              backgroundImage: imageUrl.isNotEmpty ? CachedNetworkImageProvider(imageUrl) : null,
              child: imageUrl.isEmpty ? Icon(icon, color: color, size: 28) : null,
            ),

          const SizedBox(height: 8),
          Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, height: 1.1),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildAwardsSliverGrid(BuildContext context, String seasonId, bool isAdmin) {
    final awardService = Provider.of<AwardService>(context);

    return StreamBuilder<List<Award>>(
      stream: awardService.streamAwards(seasonId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SliverToBoxAdapter(child: Center(child: CircularProgressIndicator()));
        }
        
        final awards = snapshot.data ?? [];
        if (awards.isEmpty) {
          return SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
              child: const Center(child: Text("Nenhuma premiação lançada ainda.", style: TextStyle(color: Colors.grey))),
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.85,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final award = awards[index];
                return AwardCard(
                  award: award,
                  isAdmin: isAdmin,
                  onEdit: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditAwardScreen(award: award))),
                  onDelete: () => _confirmDelete(context, awardService, seasonId, award.id),
                );
              },
              childCount: awards.length,
            ),
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, AwardService service, String seasonId, String awardId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Excluir Prêmio?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancelar")),
          TextButton(onPressed: () { service.deleteAward(seasonId, awardId); Navigator.pop(ctx); }, child: const Text("Excluir", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }
}