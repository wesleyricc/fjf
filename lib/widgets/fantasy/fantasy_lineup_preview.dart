import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/fantasy_models.dart';
import '../../services/fantasy_service.dart';
import '../../services/analytics_service.dart';
import '../../viewmodels/fantasy_home_viewmodel.dart';
import '../../services/fantasy_scout_service.dart';
import 'live_scouts_widget.dart';

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
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: SizedBox(
            width: 48,
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(player.position.substring(0, 1),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          fontSize: 12)),
                  Container(
                      width: 24,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: player.photoUrl.isNotEmpty
                            ? Image.network(player.photoUrl, fit: BoxFit.cover, alignment: Alignment.topCenter, errorBuilder: (c,e,s) => const Icon(Icons.person, size: 14))
                            : const Icon(Icons.person, size: 14),
                      )),
                ]),
          ),
          title: Row(children: [
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                      child: Text(player.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                          overflow: TextOverflow.ellipsis)),
                  if (isCaptain)
                    Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                            color: Colors.orange, shape: BoxShape.circle),
                        child: const Icon(Icons.star,
                            color: Colors.white, size: 10)),
                ],
              ),
            ),
            (!isMarketOpen)
                ? Container(
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
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                        Text(finalScore.toStringAsFixed(2),
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: finalScore >= 0
                                    ? Colors.blue[700]
                                    : Colors.red[700],
                                fontSize: 14)),
                        const Text("pts",
                            style: TextStyle(fontSize: 9, color: Colors.grey)),
                      ]),
          ]),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey[50],
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    LiveScoutsWidget(
                      scouts: FantasyScoutDetail(
                        totalScore: score.totalScore,
                        goals: score.goals,
                        assists: score.assists,
                        yellows: score.yellows,
                        reds: score.reds,
                        goalsConceded: score.goalsConceded,
                        penaltiesSaved: score.penaltiesSaved,
                        penaltiesMissed: score.penaltiesMissed,
                        shotsOnPost: score.shotsOnPost,
                        cleanSheets: score.cleanSheets,
                        ownGoals: score.ownGoals,
                        missedFreeKicks: score.missedFreeKicks,
                        motm: score.motm,
                        difficultSaves: score.difficultSaves,
                      ),
                      isCaptain: isCaptain,
                      isMarketOpen: isMarketOpen,
                      position: player.position,
                    ),
                  ]),
            )
          ],
        ),
      ),
    );
  }
}
