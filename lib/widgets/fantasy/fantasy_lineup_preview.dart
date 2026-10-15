import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/fantasy_models.dart';
import '../../services/fantasy_service.dart';
import '../../viewmodels/fantasy_home_viewmodel.dart';
import '../../services/fantasy_scout_service.dart';
import 'live_scouts_widget.dart';
import '../ui/optimized_network_image.dart';

class FantasyLineupPreviewWidget extends StatelessWidget {
  final FantasyHomeViewModel vm;

  const FantasyLineupPreviewWidget({super.key, required this.vm});

  @override
  Widget build(BuildContext context) {
    if (vm.team == null ||
        (vm.team!.lineupPlayerIds.isEmpty && vm.team!.benchPlayerIds.isEmpty)) {
      return const Center(child: Text("Time incompleto"));
    }

    final allIds = <String>{
      ...vm.team!.lineupPlayerIds,
      ...vm.team!.benchPlayerIds,
    }.toList();

    return FutureBuilder<List<FantasyPlayer>>(
      future: Provider.of<FantasyService>(context, listen: false)
          .getPlayersByIds(allIds),
      builder: (context, playerSnapshot) {
        if (!playerSnapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final allPlayers = playerSnapshot.data!;
        final starterIds = vm.team!.lineupPlayerIds.toSet();
        final benchIds = vm.team!.benchPlayerIds.toSet();

        final starters =
            allPlayers.where((p) => starterIds.contains(p.playerId)).toList();
        final bench =
            allPlayers.where((p) => benchIds.contains(p.playerId)).toList();

        starters.sort((a, b) =>
            _getSlotSortOrder(a, isBench: false).compareTo(_getSlotSortOrder(b, isBench: false)));
        bench.sort((a, b) =>
            _getSlotSortOrder(a, isBench: true).compareTo(_getSlotSortOrder(b, isBench: true)));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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

            // Cabeçalho da Seção Titulares
            Padding(
              padding:
                  const EdgeInsets.only(left: 4, right: 4, bottom: 8, top: 4),
              child: Row(
                children: [
                  const Icon(Icons.shield, size: 16, color: Colors.blueGrey),
                  const SizedBox(width: 6),
                  const Text(
                    "Titulares",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    "${starters.length} atletas",
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),

            // Lista de Titulares
            ...starters.map((p) {
              final scoreData = vm.liveScores[p.playerId] ??
                  LiveScoreData(totalScore: 0, isCaptain: false);
              final allocatedPos = _getAllocatedPosition(p, isBench: false);
              return _buildMiniPlayerRow(
                context,
                p,
                scoreData,
                vm.isMarketOpen,
                vm.config,
                vm.team!.captainId,
                isBench: false,
                isLuxury: false,
                allocatedPosition: allocatedPos,
              );
            }),

            // Seção Banco de Reservas
            if (bench.isNotEmpty) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.event_seat,
                        size: 16, color: Colors.blueGrey),
                    const SizedBox(width: 6),
                    const Text(
                      "Banco de Reservas",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    if (vm.team!.luxuryReserveId != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: Colors.amber.shade700, width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.diamond,
                                size: 12, color: Colors.amber.shade800),
                            const SizedBox(width: 4),
                            Text(
                              "Reserva de Luxo",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Text(
                        "${bench.length} reserva${bench.length > 1 ? 's' : ''}",
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500),
                      ),
                  ],
                ),
              ),
              ...bench.map((p) {
                final scoreData = vm.liveScores[p.playerId] ??
                    LiveScoreData(totalScore: 0, isCaptain: false);
                final isLuxury = (vm.team!.luxuryReserveId == p.playerId);
                final allocatedPos = _getAllocatedPosition(p, isBench: true);
                return _buildMiniPlayerRow(
                  context,
                  p,
                  scoreData,
                  vm.isMarketOpen,
                  vm.config,
                  vm.team!.captainId,
                  isBench: true,
                  isLuxury: isLuxury,
                  allocatedPosition: allocatedPos,
                );
              }),
            ] else if (!vm.isMarketOpen) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.event_seat_outlined,
                        size: 18, color: Colors.grey.shade500),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Nenhum atleta foi escalado no banco de reservas para esta rodada.",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  int _getSlotSortOrder(FantasyPlayer p, {required bool isBench}) {
    if (!isBench && vm.team?.lineupSlots != null) {
      for (final entry in vm.team!.lineupSlots!.entries) {
        if (entry.value == p.playerId) {
          final slot = int.tryParse(entry.key);
          if (slot != null) return slot;
        }
      }
    } else if (isBench && vm.team?.benchSlots != null) {
      for (final entry in vm.team!.benchSlots!.entries) {
        if (entry.value == p.playerId) {
          final slot = int.tryParse(entry.key);
          if (slot != null) return slot;
        }
      }
    }
    return isBench ? (10 + _rankingPos(p.position)) : _rankingPos(p.position);
  }

  String _positionForSlot(int slotIndex, {required String defaultPos}) {
    switch (slotIndex) {
      case 1:
      case 11:
        return 'Goleiro';
      case 2:
      case 12:
        return 'Fixo';
      case 3:
      case 4:
      case 13:
        return 'Ala';
      case 5:
      case 15:
        return 'Pivô';
      case 6:
      case 16:
        return 'Técnico';
      default:
        return defaultPos;
    }
  }

  String _getAllocatedPosition(FantasyPlayer p, {required bool isBench}) {
    final slot = _getSlotSortOrder(p, isBench: isBench);
    return _positionForSlot(slot, defaultPos: p.position);
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
      String? currentCaptainId,
      {bool isBench = false,
      bool isLuxury = false,
      String? allocatedPosition}) {
    final String pos = allocatedPosition ?? player.position;
    final String initial =
        pos.isNotEmpty ? pos.substring(0, 1).toUpperCase() : '?';

    final bool isCaptain = !isBench &&
        (isMarketOpen ? (player.playerId == currentCaptainId) : score.isCaptain);
    final double finalScore = isBench
        ? (isMarketOpen ? player.lastScore : score.totalScore)
        : (isMarketOpen
            ? (isCaptain ? player.lastScore * 2 : player.lastScore)
            : (isCaptain ? score.totalScore * 2 : score.totalScore));

    final Color scoreColor =
        finalScore >= 0 ? Colors.green[700]! : Colors.red[700]!;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isLuxury
            ? BorderSide(color: Colors.amber.shade600, width: 1.2)
            : BorderSide.none,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: SizedBox(
            width: 48,
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(initial,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color:
                              isBench ? Colors.blueGrey.shade400 : Colors.grey,
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
                            ? OptimizedNetworkImage(
                                imageUrl: player.photoUrl,
                                width: 24,
                                height: 32,
                                memCacheWidth: 60,
                                memCacheHeight: 80,
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                                fallbackIcon: Icons.person,
                              )
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
                  if (isLuxury)
                    Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: Colors.amber.shade700, width: 0.8)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.diamond,
                                color: Colors.amber.shade800, size: 10),
                            const SizedBox(width: 3),
                            Text("Luxo",
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade900)),
                          ],
                        ))
                  else if (isBench)
                    Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(4)),
                        child: Text("Reserva",
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700))),
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
                    child: Text(
                        finalScore > 0
                            ? "+${finalScore.toStringAsFixed(2)}"
                            : finalScore.toStringAsFixed(2),
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
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              "$pos • C\$ ${player.currentPrice.toStringAsFixed(2)}",
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey[50],
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isBench)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isLuxury
                              ? Colors.amber.withValues(alpha: 0.1)
                              : Colors.blueGrey.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isLuxury
                                ? Colors.amber.shade300
                                : Colors.blueGrey.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isLuxury ? Icons.diamond : Icons.event_seat,
                              size: 14,
                              color: isLuxury
                                  ? Colors.amber.shade900
                                  : Colors.blueGrey.shade700,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                isLuxury
                                    ? "Reserva de Luxo: Se pontuar mais que o titular desta posição, substitui automaticamente ao final da rodada."
                                    : "Banco de Reserva: Substitui o titular desta posição caso ele não jogue.",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: isLuxury
                                      ? Colors.amber.shade900
                                      : Colors.blueGrey.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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
                      position: pos,
                    ),
                  ]),
            )
          ],
        ),
      ),
    );
  }
}

