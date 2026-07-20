import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/fantasy_models.dart';
import '../../services/fantasy_service.dart';
import '../../services/analytics_service.dart';
import '../../viewmodels/fantasy_home_viewmodel.dart';

class FantasyLineupPreviewWidget extends StatelessWidget {
  final FantasyHomeViewModel vm;

  const FantasyLineupPreviewWidget({super.key, required this.vm});

  @override
  Widget build(BuildContext context) {
    if (vm.team!.lineupPlayerIds.isEmpty) {
      return const Center(child: Text("Time incompleto"));
    }
    return FutureBuilder<List<FantasyPlayer>>(
      future: Provider.of<FantasyService>(context, listen: false)
          .getPlayersByIds(vm.team!.lineupPlayerIds),
      builder: (context, playerSnapshot) {
        if (!playerSnapshot.hasData) return const CircularProgressIndicator();
        List<FantasyPlayer> players = playerSnapshot.data!;
        players.sort((a, b) =>
            _rankingPos(a.position).compareTo(_rankingPos(b.position)));

        return Column(
          children: [
            if (!vm.isMarketOpen)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [Colors.green.shade800, Colors.green.shade600]),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.green.withValues(alpha: 0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2))
                    ]),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("TOTAL DA PARCIAL",
                                style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1)),
                            Text("Rodada Atual",
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500))
                          ]),
                      Text("${vm.teamPartialScore.toStringAsFixed(2)} pts",
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900)),
                    ]),
              )
            else if (vm.currentRound > 1)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [Colors.blue.shade800, Colors.blue.shade600]),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.blue.withValues(alpha: 0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2))
                    ]),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("PONTUAÇÃO DA ÚLTIMA RODADA",
                                style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1)),
                            Text("Rodada ${vm.currentRound - 1}",
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500))
                          ]),
                      Text("${vm.team!.lastScore.toStringAsFixed(2)} pts",
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900)),
                    ]),
              ),

            // Lista de Jogadores
            ...players.map((p) {
              final scoreData = vm.liveScores[p.playerId] ??
                  LiveScoreData(totalScore: 0, isCaptain: false);
              return _buildMiniPlayerRow(context, p, scoreData, vm.isMarketOpen,
                  vm.config, vm.team!.captainId);
            }),
          ],
        );
      },
    );
  }

  int _rankingPos(String pos) {
    switch (pos) {
      case 'Goleiro':
        return 1;
      case 'Fixo':
        return 2;
      case 'Ala':
        return 3;
      case 'Pivô':
        return 4;
      case 'Técnico':
        return 5;
      default:
        return 99;
    }
  }

  Widget _buildMiniPlayerRow(
      BuildContext context,
      FantasyPlayer player,
      LiveScoreData score,
      bool isMarketOpen,
      FantasyGameConfig config,
      String? currentCaptainId) {
    final bool isCaptain =
        isMarketOpen ? (player.playerId == currentCaptainId) : score.isCaptain;
    final double finalScore = isMarketOpen
        ? (isCaptain ? player.lastScore * 2 : player.lastScore)
        : (isCaptain ? score.totalScore * 2 : score.totalScore);

    final Color scoreColor =
        finalScore >= 0 ? Colors.green[700]! : Colors.red[700]!;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: isMarketOpen
            ? null
            : () => showScoutDetails(context, player, score, config),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(children: [
              Container(
                  width: 25,
                  alignment: Alignment.center,
                  child: Text(player.position.substring(0, 1),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          fontSize: 12))),
              const SizedBox(width: 8),
              CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: player.photoUrl.isNotEmpty
                      ? NetworkImage(player.photoUrl)
                      : null,
                  child: player.photoUrl.isEmpty
                      ? const Icon(Icons.person, size: 16)
                      : null),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(player.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                      overflow: TextOverflow.ellipsis)),
              if (isCaptain)
                Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                        color: Colors.orange, shape: BoxShape.circle),
                    child:
                        const Icon(Icons.star, color: Colors.white, size: 10)),
              if (!isMarketOpen)
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: scoreColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(finalScore.toStringAsFixed(2),
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: scoreColor,
                            fontSize: 14)))
              else
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(finalScore.toStringAsFixed(2),
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: finalScore >= 0
                              ? Colors.blue[700]
                              : Colors.red[700],
                          fontSize: 14)),
                  const Text("pts",
                      style: TextStyle(fontSize: 9, color: Colors.grey)),
                ])
            ])),
      ),
    );
  }

  static void showScoutDetails(BuildContext context, FantasyPlayer player,
      LiveScoreData score, FantasyGameConfig config) {
    AnalyticsService.logCustomScreenView('Fantasy_Scout_Details_Modal',
        parameters: {'player_id': player.playerId, 'player_name': player.name});

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(player.name,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(player.position, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            if (player.position == 'Técnico')
              _buildTechnicianInfo()
            else
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 16,
                runSpacing: 20,
                children: [
                  if (score.goals > 0)
                    _buildScoutIcon(Icons.sports_soccer, "Gols", score.goals,
                        Colors.green, score.goals * config.ptsGoal),
                  if (score.assists > 0)
                    _buildScoutIcon(Icons.assistant, "Assists", score.assists,
                        Colors.blue, score.assists * config.ptsAssist),
                  if (score.cleanSheets > 0)
                    _buildScoutIcon(Icons.shield, "SG", score.cleanSheets,
                        Colors.teal, score.cleanSheets * config.ptsCleanSheet),
                  if (score.penaltiesSaved > 0)
                    _buildScoutIcon(
                        Icons.sports_martial_arts,
                        "Pên. Def",
                        score.penaltiesSaved,
                        Colors.orange,
                        score.penaltiesSaved * config.ptsPenaltySaved),
                  if (score.shotsOnPost > 0)
                    _buildScoutIcon(Icons.adjust, "Na Trave", score.shotsOnPost,
                        Colors.brown, score.shotsOnPost * config.ptsShotOnPost),
                  if (score.yellows > 0)
                    _buildScoutIcon(
                        Icons.style,
                        "Amarelo",
                        score.yellows,
                        Colors.amber[800]!,
                        score.yellows * config.ptsYellowCard),
                  if (score.penaltiesMissed > 0)
                    _buildScoutIcon(
                        Icons.cancel,
                        "Pên. Perd",
                        score.penaltiesMissed,
                        Colors.deepPurple,
                        score.penaltiesMissed * config.ptsPenaltyMissed),
                  if (score.missedFreeKicks > 0)
                    _buildScoutIcon(
                        Icons.warning,
                        "Tiro Liv",
                        score.missedFreeKicks,
                        Colors.deepOrange,
                        score.missedFreeKicks * config.ptsMissedFreeKick),
                  if (score.ownGoals > 0)
                    _buildScoutIcon(
                        Icons.report_problem,
                        "Gol Contra",
                        score.ownGoals,
                        Colors.red[900]!,
                        score.ownGoals * config.ptsOwnGoal),
                  if (score.reds > 0)
                    _buildScoutIcon(Icons.style, "Vermelho", score.reds,
                        Colors.red, score.reds * config.ptsRedCard),
                  if (score.motm > 0)
                    _buildScoutIcon(Icons.star, "Craque", score.motm,
                        Colors.amber, score.motm * config.ptsMotm),
                  if (!score.hasStats)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20.0),
                      child: Text("Nenhum scout registrado na rodada.",
                          style: TextStyle(color: Colors.grey)),
                    )
                ],
              ),
            const Divider(height: 48),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Pontuação da Rodada",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    if (score.isCaptain)
                      const Text("Bônus de Capitão Ativo (2x)",
                          style: TextStyle(
                              color: Colors.orange,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                  ],
                ),
                Text(
                    "${(score.isCaptain ? score.totalScore * 2 : score.totalScore).toStringAsFixed(2)} pts",
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.green)),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  static Widget _buildTechnicianInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.withValues(alpha: 0.2))),
      child: Column(
        children: const [
          Icon(Icons.psychology, color: Colors.blue, size: 32),
          SizedBox(height: 8),
          Text("Média da Equipe Real",
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
          SizedBox(height: 4),
          Text(
              "A pontuação do técnico é a média aritmética simples de todos os jogadores do seu time que entraram em campo e pontuaram.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.black54))
        ],
      ),
    );
  }

  static Widget _buildScoutIcon(
      IconData icon, String label, int count, Color color, double points) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.topRight,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 24),
            ),
            if (count > 1)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                    color: Colors.black, shape: BoxShape.circle),
                child: Text(count.toString(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              )
          ],
        ),
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        Text("${points > 0 ? '+' : ''}${points.toStringAsFixed(1)} pts",
            style: TextStyle(fontSize: 10, color: color)),
      ],
    );
  }
}
