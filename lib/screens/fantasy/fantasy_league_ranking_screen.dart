import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/fantasy_league_model.dart';
import '../../models/fantasy_models.dart';
import '../../services/fantasy_league_service.dart';
import '../../services/fantasy_service.dart';
import '../../services/championship_service.dart';
import '../../services/fantasy_auth_service.dart';
import '../../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../../widgets/team_logo_widget.dart';
import '../../widgets/fantasy/league_invite_modal.dart';
import '../../widgets/fantasy/fantasy_team_lineup_modal.dart';
import 'fantasy_manage_league_screen.dart';

class FantasyLeagueRankingScreen extends StatefulWidget {
  final FantasyLeague league;

  const FantasyLeagueRankingScreen({super.key, required this.league});

  @override
  State<FantasyLeagueRankingScreen> createState() =>
      _FantasyLeagueRankingScreenState();
}

class _FantasyLeagueRankingScreenState extends State<FantasyLeagueRankingScreen>
    with SingleTickerProviderStateMixin {
  final FantasyLeagueService _leagueService = FantasyLeagueService();
  late TabController _tabController;

  bool _isLoading = true;
  List<Map<String, dynamic>> _rankedTeams = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // 🚨 Analytics: Registro da visualização do ranking de UMA liga privada específica
    AnalyticsService.logViewItem(
      contentType: 'fantasy_private_league',
      itemId: widget.league.id,
      itemName: widget.league.name,
    );

    _loadLeagueRanking(forceRefresh: false);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadLeagueRanking({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);

    try {
      final teamsData = await _leagueService.getLeagueRanking(
        widget.league,
        forceRefresh: forceRefresh,
      );

      if (mounted) {
        setState(() {
          _rankedTeams = teamsData;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Erro ao carregar ranking da liga: $e");
      if (mounted) {
        setState(() {
          _errorMessage = "Não foi possível carregar o ranking.";
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final currentUserId =
        Provider.of<FantasyAuthService>(context, listen: false).user?.uid;
    final isOwner = widget.league.ownerId == currentUserId;

    final fantasyService = Provider.of<FantasyService>(context, listen: false);
    final seasonId = Provider.of<ChampionshipService>(context).currentSeasonId;

    return StreamBuilder<Map<String, dynamic>>(
      stream: fantasyService.streamMarketStatus(),
      builder: (context, statusSnap) {
        final status = statusSnap.data ?? {'is_open': true, 'current_round': 1};
        final bool isOpen = status['is_open'] == true;
        final int currentRound = (status['current_round'] ?? 1) is int
            ? status['current_round']
            : int.tryParse(status['current_round'].toString()) ?? 1;

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                if (widget.league.imageUrl != null &&
                    widget.league.imageUrl!.isNotEmpty) ...[
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white24,
                    backgroundImage: NetworkImage(widget.league.imageUrl!),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.league.name, overflow: TextOverflow.ellipsis),
                      Text(
                        "Código: ${widget.league.inviteCode}",
                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!isOpen) ...[
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: const BoxDecoration(
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                      Text(!isOpen ? "DA RODADA (AO VIVO)" : "DA RODADA"),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!isOpen) ...[
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: const BoxDecoration(
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                      Text(!isOpen ? "GERAL (AO VIVO)" : "GERAL"),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              if (isOwner)
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: "Gerenciar Liga",
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            FantasyManageLeagueScreen(league: widget.league),
                      ),
                    );
                    _loadLeagueRanking(forceRefresh: true);
                  },
                ),
              IconButton(
                icon: const Icon(Icons.share),
                tooltip: "Convidar Amigos",
                onPressed: () => LeagueInviteModal.show(context, widget.league,
                    isOwner: isOwner),
              ),
            ],
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildLeagueTabBody(
                primaryColor: primaryColor,
                isOwner: isOwner,
                currentUserId: currentUserId,
                seasonId: seasonId,
                currentRound: currentRound,
                isGlobal: false,
                isOpen: isOpen,
              ),
              _buildLeagueTabBody(
                primaryColor: primaryColor,
                isOwner: isOwner,
                currentUserId: currentUserId,
                seasonId: seasonId,
                currentRound: currentRound,
                isGlobal: true,
                isOpen: isOpen,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLeagueTabBody({
    required Color primaryColor,
    required bool isOwner,
    required String? currentUserId,
    required String seasonId,
    required int currentRound,
    required bool isGlobal,
    required bool isOpen,
  }) {
    final fantasyService = Provider.of<FantasyService>(context, listen: false);

    // 🏆 FINOPS: Se o mercado estiver fechado e temos seasonId e round válidos, ouvimos o stream do leaderboard consolidado
    if (!isOpen && seasonId.isNotEmpty && currentRound > 0) {
      return StreamBuilder<FantasyLiveLeaderboard?>(
        stream: fantasyService.streamLiveLeaderboard(
          seasonId: seasonId,
          round: currentRound,
        ),
        builder: (context, liveSnap) {
          final liveLeaderboard = liveSnap.data;

          if (liveLeaderboard != null && liveLeaderboard.teams.isNotEmpty) {
            // Filtra os membros da liga em memória sem nenhuma leitura extra no Firestore
            final leagueMembers = widget.league.members;
            final leagueTeams = liveLeaderboard.teams.where((t) {
              return leagueMembers.contains(t.teamId) ||
                  leagueMembers.contains(t.userId);
            }).toList();

            if (leagueTeams.isNotEmpty) {
              // Verifica se as partidas da rodada já iniciaram ou se a rodada está consolidada
              final bool hasMatchesStarted = liveLeaderboard.isFinal ||
                  liveLeaderboard.teams
                      .any((t) => t.playersPlayed > 0 || t.roundScore != 0.0);

              if (isGlobal) {
                leagueTeams
                    .sort((a, b) => b.totalPoints.compareTo(a.totalPoints));
              } else {
                if (hasMatchesStarted) {
                  leagueTeams
                      .sort((a, b) => b.roundScore.compareTo(a.roundScore));
                } else {
                  leagueTeams
                      .sort((a, b) => b.totalPoints.compareTo(a.totalPoints));
                }
              }

              return Column(
                children: [
                  if (isOwner) _buildOwnerInviteBanner(primaryColor),
                  _buildLiveHeaderBanner(liveLeaderboard, hasMatchesStarted),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () => _loadLeagueRanking(forceRefresh: true),
                      color: primaryColor,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: leagueTeams.length,
                        itemBuilder: (context, index) {
                          final team = leagueTeams[index];
                          final int rank = index + 1;
                          final bool isMe = team.userId == currentUserId ||
                              team.teamId == currentUserId;

                          return _buildLiveLeagueCard(
                            context,
                            rank: rank,
                            team: team,
                            isMe: isMe,
                            isGlobal: isGlobal,
                            primaryColor: primaryColor,
                            hasMatchesStarted: hasMatchesStarted,
                            seasonId: seasonId,
                            currentRound: currentRound,
                            isOpen: isOpen,
                          );
                        },
                      ),
                    ),
                  ),
                ],
              );
            }
          }

          // Fallback para o modo padrão se ainda não houver parciais
          return _buildStandardLeagueBody(
            primaryColor,
            isOwner: isOwner,
            isGlobal: isGlobal,
            isOpen: isOpen,
            currentRound: currentRound,
          );
        },
      );
    }

    return _buildStandardLeagueBody(
      primaryColor,
      isOwner: isOwner,
      isGlobal: isGlobal,
      isOpen: isOpen,
      currentRound: currentRound,
    );
  }

  Widget _buildLiveHeaderBanner(
      FantasyLiveLeaderboard leaderboard, bool hasMatchesStarted) {
    final bool isFinal = leaderboard.isFinal;

    final Color bgColor = isFinal
        ? Colors.grey.shade100
        : (hasMatchesStarted ? Colors.green.shade50 : Colors.blue.shade50);
    final Color borderColor = isFinal
        ? Colors.grey.shade300
        : (hasMatchesStarted ? Colors.green.shade300 : Colors.blue.shade200);
    final Color textColor = isFinal
        ? Colors.grey.shade800
        : (hasMatchesStarted ? Colors.green.shade800 : Colors.blue.shade900);
    final Color iconColor = isFinal
        ? Colors.grey.shade700
        : (hasMatchesStarted ? Colors.green.shade700 : Colors.blue.shade700);

    final String titleText = isFinal
        ? "Rodada ${leaderboard.round} consolidada"
        : (hasMatchesStarted
            ? "Parciais da Liga • Rodada ${leaderboard.round}"
            : "Rodada ${leaderboard.round} • Aguardando início das partidas");

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 6, 10, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(
            isFinal
                ? Icons.check_circle_outline
                : (hasMatchesStarted ? Icons.sensors : Icons.schedule),
            color: iconColor,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              titleText,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ),
          if (!isFinal && hasMatchesStarted)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                "AO VIVO",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLiveLeagueCard(
    BuildContext context, {
    required int rank,
    required FantasyLiveTeamScore team,
    required bool isMe,
    required bool isGlobal,
    required Color primaryColor,
    required bool hasMatchesStarted,
    required String seasonId,
    required int currentRound,
    required bool isOpen,
  }) {
    Color rankColor = Colors.grey.shade300;
    if (rank == 1) {
      rankColor = Colors.amber;
    } else if (rank == 2) {
      rankColor = Colors.grey.shade400;
    } else if (rank == 3) {
      rankColor = Colors.brown.shade300;
    }

    // Se for da rodada e as partidas ainda não iniciaram, a pontuação da rodada fica 0.00
    final double displayPoints = isGlobal
        ? team.totalPoints
        : (hasMatchesStarted ? team.roundScore : 0.0);

    return Card(
      elevation: rank <= 3 ? 4 : 1,
      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      color: isMe ? Colors.green[50] : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isMe
            ? BorderSide(color: primaryColor, width: 2)
            : (rank <= 3
                ? BorderSide(color: rankColor, width: 2)
                : BorderSide.none),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        onTap: () {
          FantasyTeamLineupModal.show(
            context,
            seasonId: seasonId,
            round: currentRound,
            teamId: team.teamId,
            userId: team.userId,
            teamName: team.teamName,
            ownerName: team.ownerName,
            shieldType: team.shieldType,
            customLogoUrl: team.customLogoUrl,
            roundScore: team.roundScore,
            totalPoints: team.totalPoints,
            teamValue: team.teamValue,
            captainId: team.captainId,
            substitutions: team.substitutions,
            finalLineup: team.finalLineup,
            playersPlayed: team.playersPlayed,
            playersTotal: team.playersTotal,
            isMe: isMe,
            isMarketOpen: isOpen,
          );
        },
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              child: Text(
                "$rankº",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: rank <= 3 ? rankColor : Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 8),
            TeamLogoWidget(
              logoUrl: team.customLogoUrl,
              shieldType: team.shieldType,
              radius: 20,
            ),
          ],
        ),
        title: Text(
          team.teamName,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isMe ? Colors.green[900] : Colors.black87,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                team.ownerName,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                "⚽ ${team.playersPlayed}/${team.playersTotal}",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: team.playersPlayed == team.playersTotal
                      ? Colors.green.shade700
                      : Colors.grey.shade700,
                ),
              ),
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isMe ? Colors.green.shade100 : Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isMe ? Colors.green.shade300 : Colors.grey.shade300,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayPoints.toStringAsFixed(2),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: !isGlobal ? Colors.green[800] : primaryColor,
                ),
              ),
              Text(
                "pts",
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStandardLeagueBody(
    Color primaryColor, {
    required bool isOwner,
    required bool isGlobal,
    required bool isOpen,
    required int currentRound,
  }) {
    if (_isLoading && _rankedTeams.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _rankedTeams.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: Colors.grey)),
            TextButton(
              onPressed: () => _loadLeagueRanking(forceRefresh: true),
              child: const Text("Tentar Novamente"),
            ),
          ],
        ),
      );
    }

    if (_rankedTeams.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.people_outline, size: 60, color: Colors.grey),
              const SizedBox(height: 16),
              const Text("Nenhum time encontrado nesta liga."),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => LeagueInviteModal.show(context, widget.league,
                    isOwner: isOwner),
                icon: const Icon(Icons.share),
                label: const Text("Convidar Amigos"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final bool showRoundInfoBanner = !isGlobal;
    final int extraHeaderCount = showRoundInfoBanner ? 1 : 0;

    return Column(
      children: [
        if (isOwner) _buildOwnerInviteBanner(primaryColor),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _loadLeagueRanking(forceRefresh: true),
            color: primaryColor,
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _rankedTeams.length + extraHeaderCount,
              itemBuilder: (context, index) {
                if (showRoundInfoBanner && index == 0) {
                  return Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: Colors.blue.shade700, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isOpen
                                ? "Mercado aberto para a Rodada $currentRound. As pontuações da rodada começarão assim que as partidas iniciarem."
                                : "Mercado fechado para a Rodada $currentRound. Aguardando o início das partidas para exibir as parciais ao vivo.",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final itemIndex = index - extraHeaderCount;
                final team = _rankedTeams[itemIndex];
                final String teamName = team['team_name'] ?? 'Time Sem Nome';
                final String? logoUrl = team['custom_logo_url'];
                final double points =
                    isGlobal ? (team['total_points'] ?? 0.0).toDouble() : 0.0;

                final int rank = index + 1;

                Color rankColor = Colors.grey.shade300;
                if (rank == 1) {
                  rankColor = Colors.amber;
                } else if (rank == 2) {
                  rankColor = Colors.grey.shade400;
                } else if (rank == 3) {
                  rankColor = Colors.brown.shade300;
                }

                return Card(
                  elevation: rank <= 3 ? 4 : 1,
                  margin:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: rank <= 3
                        ? BorderSide(color: rankColor, width: 2)
                        : BorderSide.none,
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "$rankº",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: rank <= 3 ? rankColor : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 12),
                        TeamLogoWidget(
                          logoUrl: logoUrl,
                          shieldType: team['shield_type']?.toString(),
                          radius: 20,
                        ),
                      ],
                    ),
                    title: Text(teamName,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: Text(
                      points.toStringAsFixed(2),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: primaryColor,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Banner com destaque e botão de convite para o dono da liga
  Widget _buildOwnerInviteBanner(Color primaryColor) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            primaryColor.withValues(alpha: 0.1),
            primaryColor.withValues(alpha: 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: primaryColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.vpn_key_rounded, color: primaryColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text("Código da Liga:",
                        style: TextStyle(fontSize: 11, color: Colors.black54)),
                    const SizedBox(width: 6),
                    Text(
                      widget.league.inviteCode,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: primaryColor,
                        letterSpacing: 1,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text("Convide seus amigos para disputar esta liga",
                    style: TextStyle(fontSize: 11, color: Colors.black54)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      FantasyManageLeagueScreen(league: widget.league),
                ),
              );
              _loadLeagueRanking(forceRefresh: true);
            },
            icon: const Icon(Icons.settings, size: 14),
            label: const Text("Gerenciar"),
            style: OutlinedButton.styleFrom(
              foregroundColor: primaryColor,
              side: BorderSide(color: primaryColor),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              textStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 6),
          ElevatedButton.icon(
            onPressed: () =>
                LeagueInviteModal.show(context, widget.league, isOwner: true),
            icon: const Icon(Icons.share, size: 14),
            label: const Text("Convidar"),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              elevation: 1,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}
