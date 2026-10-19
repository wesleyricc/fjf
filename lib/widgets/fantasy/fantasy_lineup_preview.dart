import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/fantasy_models.dart';
import '../../services/fantasy_service.dart';
import '../../viewmodels/fantasy_home_viewmodel.dart';
import '../../services/fantasy_scout_service.dart';
import 'live_scouts_widget.dart';
import '../ui/optimized_network_image.dart';

class SubstitutionDisplayInfo {
  final FantasyPlayer reservePlayer;
  final FantasyPlayer replacedStarter;
  final double reserveRawScore;
  final double starterRawScore;
  final double reserveEffectiveScore;
  final double starterEffectiveScore;
  final double netGain;
  final bool isStarterCaptain;
  final String position;
  final bool isAbsence; // true = normal (ausência), false = luxo

  SubstitutionDisplayInfo({
    required this.reservePlayer,
    required this.replacedStarter,
    required this.reserveRawScore,
    required this.starterRawScore,
    required this.reserveEffectiveScore,
    required this.starterEffectiveScore,
    required this.netGain,
    required this.isStarterCaptain,
    required this.position,
    required this.isAbsence,
  });
}

class LuxuryReserveInfo {
  final FantasyPlayer reservePlayer;
  final FantasyPlayer replacedStarter;
  final double reserveRawScore;
  final double starterRawScore;
  final double reserveEffectiveScore;
  final double starterEffectiveScore;
  final double netGain;
  final double startersTotalScore;
  final double finalTotalScore;
  final bool isStarterCaptain;
  final String position;
  final bool isActivated;

  LuxuryReserveInfo({
    required this.reservePlayer,
    required this.replacedStarter,
    required this.reserveRawScore,
    required this.starterRawScore,
    required this.reserveEffectiveScore,
    required this.starterEffectiveScore,
    required this.netGain,
    required this.startersTotalScore,
    required this.finalTotalScore,
    required this.isStarterCaptain,
    required this.position,
    required this.isActivated,
  });
}

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

        starters.sort((a, b) => _getSlotSortOrder(a, isBench: false)
            .compareTo(_getSlotSortOrder(b, isBench: false)));
        bench.sort((a, b) => _getSlotSortOrder(a, isBench: true)
            .compareTo(_getSlotSortOrder(b, isBench: true)));

        final substitutions = (!vm.isMarketOpen)
            ? _computeAllSubstitutions(starters, bench)
            : <SubstitutionDisplayInfo>[];

        final absenceSubs = substitutions.where((s) => s.isAbsence).toList();
        final luxurySubs = substitutions.where((s) => !s.isAbsence).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!vm.isMarketOpen) ...[
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
              ),
              // Cards de Destaque para Substituições por Ausência
              ...absenceSubs
                  .map((sub) => _buildAbsenceSubstitutionCard(context, sub)),
              // Cards de Destaque para Reserva de Luxo
              ...luxurySubs
                  .map((sub) => _buildLuxuryActivationCard(context, sub)),
            ] else ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.blueGrey.shade900,
                      Colors.blueGrey.shade800
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.greenAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              "TIME CONFIRMADO",
                              style: TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "Pronto para a Rodada ${vm.currentRound}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade600,
                        foregroundColor: Colors.black87,
                        elevation: 2,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.swap_horiz, size: 16),
                      label: const Text(
                        "Mudar Time",
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      onPressed: () {
                        Navigator.pushNamed(context, '/fantasy-market');
                      },
                    ),
                  ],
                ),
              ),
            ],

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

              final sub = substitutions
                  .where((s) => s.replacedStarter.playerId == p.playerId)
                  .firstOrNull;

              final isReplacedByAbsence = sub != null && sub.isAbsence;
              final isReplacedByLuxury = sub != null && !sub.isAbsence;

              return _buildMiniPlayerRow(
                context,
                p,
                scoreData,
                vm.isMarketOpen,
                vm.config,
                vm.team!.captainId,
                isBench: false,
                isLuxury: false,
                isReplacedByAbsence: isReplacedByAbsence,
                isReplacedByLuxury: isReplacedByLuxury,
                replacementName: sub?.reservePlayer.name,
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
                    if (absenceSubs.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: Colors.blue.shade700, width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.swap_horiz,
                                size: 12, color: Colors.blue.shade800),
                            const SizedBox(width: 4),
                            Text(
                              "${absenceSubs.length} Entrada${absenceSubs.length > 1 ? 's' : ''} por Ausência",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade900,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (vm.team!.luxuryReserveId != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: luxurySubs.isNotEmpty
                              ? Colors.green.withValues(alpha: 0.15)
                              : Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: luxurySubs.isNotEmpty
                                  ? Colors.green.shade700
                                  : Colors.amber.shade700,
                              width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              luxurySubs.isNotEmpty
                                  ? Icons.check_circle
                                  : Icons.diamond,
                              size: 12,
                              color: luxurySubs.isNotEmpty
                                  ? Colors.green.shade800
                                  : Colors.amber.shade800,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              luxurySubs.isNotEmpty
                                  ? "Luxo Ativado (+${luxurySubs.first.netGain.toStringAsFixed(2)} pts)"
                                  : "Reserva de Luxo",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: luxurySubs.isNotEmpty
                                    ? Colors.green.shade900
                                    : Colors.amber.shade900,
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

                final sub = substitutions
                    .where((s) => s.reservePlayer.playerId == p.playerId)
                    .firstOrNull;

                final isAbsenceActivated = sub != null && sub.isAbsence;
                final isLuxuryActivated = sub != null && !sub.isAbsence;

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
                  isAbsenceActivated: isAbsenceActivated,
                  isLuxuryActivated: isLuxuryActivated,
                  replacedStarterName: sub?.replacedStarter.name,
                  wasReplacedStarterCaptain: sub?.isStarterCaptain ?? false,
                  luxuryNetGain: sub?.netGain,
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

  List<SubstitutionDisplayInfo> _computeAllSubstitutions(
    List<FantasyPlayer> starters,
    List<FantasyPlayer> bench,
  ) {
    final result = <SubstitutionDisplayInfo>[];
    final playersById = {
      for (var p in [...starters, ...bench]) p.playerId: p
    };

    // 1. Se o leaderboard consolidado da rodada fornecer as substituições oficiais:
    final liveSubs = vm.liveTeamScore?.substitutions ?? [];
    if (liveSubs.isNotEmpty) {
      for (final sub in liveSubs) {
        final starter = playersById[sub.outPlayerId];
        final reserve = playersById[sub.inPlayerId];
        if (starter != null && reserve != null) {
          final starterRaw = vm.liveScores[starter.playerId]?.totalScore ?? 0.0;
          final reserveRaw = vm.liveScores[reserve.playerId]?.totalScore ?? 0.0;
          final isStarterCap = (vm.team?.captainId == starter.playerId);
          final starterEff = isStarterCap ? starterRaw * 2 : starterRaw;
          final reserveEff = isStarterCap ? reserveRaw * 2 : reserveRaw;
          final netGain = reserveEff - starterEff;

          result.add(SubstitutionDisplayInfo(
            reservePlayer: reserve,
            replacedStarter: starter,
            reserveRawScore: reserveRaw,
            starterRawScore: starterRaw,
            reserveEffectiveScore: reserveEff,
            starterEffectiveScore: starterEff,
            netGain: netGain,
            isStarterCaptain: isStarterCap,
            position: sub.slotPosition.isNotEmpty
                ? sub.slotPosition
                : _getAllocatedPosition(starter, isBench: false),
            isAbsence: sub.type == 'normal',
          ));
        }
      }
      return result;
    }

    // 2. Fallback local para Reserva de Luxo caso o leaderboard ainda esteja sincronizando:
    final luxuryInfo = _computeLuxuryReserveInfo(starters, bench);
    if (luxuryInfo != null && luxuryInfo.isActivated) {
      result.add(SubstitutionDisplayInfo(
        reservePlayer: luxuryInfo.reservePlayer,
        replacedStarter: luxuryInfo.replacedStarter,
        reserveRawScore: luxuryInfo.reserveRawScore,
        starterRawScore: luxuryInfo.starterRawScore,
        reserveEffectiveScore: luxuryInfo.reserveEffectiveScore,
        starterEffectiveScore: luxuryInfo.starterEffectiveScore,
        netGain: luxuryInfo.netGain,
        isStarterCaptain: luxuryInfo.isStarterCaptain,
        position: luxuryInfo.position,
        isAbsence: false,
      ));
    }

    return result;
  }

  LuxuryReserveInfo? _computeLuxuryReserveInfo(
    List<FantasyPlayer> starters,
    List<FantasyPlayer> bench,
  ) {
    if (vm.team?.luxuryReserveId == null) return null;
    final luxuryPid = vm.team!.luxuryReserveId!;

    final luxuryPlayer =
        bench.where((p) => p.playerId == luxuryPid).firstOrNull;
    if (luxuryPlayer == null) return null;

    final luxuryPos = _getAllocatedPosition(luxuryPlayer, isBench: true);
    final startersOfPos = starters
        .where((s) => _getAllocatedPosition(s, isBench: false) == luxuryPos)
        .toList();
    if (startersOfPos.isEmpty) return null;

    // Encontra o titular de menor pontuação na posição
    FantasyPlayer worstStarter = startersOfPos.first;
    double worstScore = vm.liveScores[worstStarter.playerId]?.totalScore ?? 0.0;

    for (final s in startersOfPos.skip(1)) {
      final sScore = vm.liveScores[s.playerId]?.totalScore ?? 0.0;
      if (sScore < worstScore) {
        worstScore = sScore;
        worstStarter = s;
      } else if (sScore == worstScore) {
        // Se empatar e o atual pior for capitão, prefere substituir o não-capitão
        if (worstStarter.playerId == vm.team!.captainId &&
            s.playerId != vm.team!.captainId) {
          worstStarter = s;
        }
      }
    }

    final benchScore = vm.liveScores[luxuryPlayer.playerId]?.totalScore ?? 0.0;
    final bool isActivated = (benchScore > worstScore);

    final bool isStarterCaptain = (worstStarter.playerId == vm.team!.captainId);
    final double starterEffectiveScore =
        isStarterCaptain ? (worstScore * 2) : worstScore;
    final double benchEffectiveScore =
        isStarterCaptain ? (benchScore * 2) : benchScore;
    final double netGain = benchEffectiveScore - starterEffectiveScore;

    double startersSum = 0.0;
    for (final s in starters) {
      final sScore = vm.liveScores[s.playerId]?.totalScore ?? 0.0;
      final isCap = (s.playerId == vm.team!.captainId);
      startersSum += isCap ? (sScore * 2) : sScore;
    }
    final double finalTotal = startersSum + (isActivated ? netGain : 0.0);

    return LuxuryReserveInfo(
      reservePlayer: luxuryPlayer,
      replacedStarter: worstStarter,
      reserveRawScore: benchScore,
      starterRawScore: worstScore,
      reserveEffectiveScore: benchEffectiveScore,
      starterEffectiveScore: starterEffectiveScore,
      netGain: netGain,
      startersTotalScore: startersSum,
      finalTotalScore: finalTotal,
      isStarterCaptain: isStarterCaptain,
      position: luxuryPos,
      isActivated: isActivated,
    );
  }

  Widget _buildAbsenceSubstitutionCard(
      BuildContext context, SubstitutionDisplayInfo info) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFF0F7FF),
            const Color(0xFFE3F2FD).withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade300, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.blue.shade700,
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.swap_horiz, color: Colors.white, size: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "SUBSTITUIÇÃO POR AUSÊNCIA",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.blue.shade900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.blue.shade800,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "+${info.reserveEffectiveScore.toStringAsFixed(2)} pts",
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: TextStyle(
                fontSize: 12,
                color: Colors.blueGrey.shade900,
                height: 1.35,
              ),
              children: [
                const TextSpan(text: "O titular "),
                TextSpan(
                  text: info.replacedStarter.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(
                  text: " não entrou em campo nesta rodada. O reserva ",
                ),
                TextSpan(
                  text: info.reservePlayer.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(
                  text: " (+${info.reserveRawScore.toStringAsFixed(2)} pts)",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800,
                  ),
                ),
                TextSpan(
                  text:
                      " entrou na posição de ${info.position} e seus pontos estão somando no time.",
                ),
              ],
            ),
          ),
          if (info.isStarterCaptain) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.star, size: 13, color: Colors.orange.shade800),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      "Como o titular ausente era o Capitão (C), a faixa e o bônus 2x passaram para o reserva que entrou.",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200, width: 0.8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text(
                      "Status do Titular",
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.blueGrey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Ausente (0.00 pts)",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
                Icon(Icons.arrow_forward,
                    size: 15, color: Colors.blue.shade700),
                Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_seat,
                            size: 10, color: Colors.blue.shade800),
                        const SizedBox(width: 2),
                        Text(
                          "Reserva Entrou",
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.blue.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "+${info.reserveEffectiveScore.toStringAsFixed(2)} pts",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
                      ),
                    ),
                  ],
                ),
                Icon(Icons.drag_handle,
                    size: 15, color: Colors.blueGrey.shade400),
                Column(
                  children: [
                    const Text(
                      "Total Parcial",
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.blueGrey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "${vm.teamPartialScore.toStringAsFixed(2)} pts",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Colors.green.shade900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLuxuryActivationCard(
      BuildContext context, SubstitutionDisplayInfo info) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFFDF5),
            Colors.amber.shade50,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade400, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.amber.shade600,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.diamond, color: Colors.white, size: 14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "RESERVA DE LUXO ATIVADO!",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.amber.shade900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.shade700,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "+${info.netGain.toStringAsFixed(2)} pts",
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              style: TextStyle(
                fontSize: 12,
                color: Colors.brown.shade800,
                height: 1.35,
              ),
              children: [
                const TextSpan(text: "O reserva de luxo "),
                TextSpan(
                  text: info.reservePlayer.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(
                  text: " (+${info.reserveRawScore.toStringAsFixed(2)} pts)",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800,
                  ),
                ),
                const TextSpan(text: " superou o titular "),
                TextSpan(
                  text: info.replacedStarter.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(
                  text: " (+${info.starterRawScore.toStringAsFixed(2)} pts)",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade800,
                  ),
                ),
                TextSpan(
                  text:
                      " na posição de ${info.position} e entrou na sua parcial.",
                ),
              ],
            ),
          ),
          if (info.isStarterCaptain) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.star, size: 13, color: Colors.orange.shade800),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      "Como o titular substituído era o Capitão (C), a bonificação 2x foi transferida ao Reserva de Luxo.",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade300, width: 0.8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text(
                      "Pior Titular",
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.blueGrey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "${info.starterEffectiveScore.toStringAsFixed(2)} pts",
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                Icon(Icons.add, size: 15, color: Colors.amber.shade900),
                Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.diamond,
                            size: 10, color: Colors.amber.shade800),
                        const SizedBox(width: 2),
                        Text(
                          "Ganho Luxo",
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "+${info.netGain.toStringAsFixed(2)} pts",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade800,
                      ),
                    ),
                  ],
                ),
                Icon(Icons.drag_handle,
                    size: 15, color: Colors.blueGrey.shade400),
                Column(
                  children: [
                    const Text(
                      "Total Parcial",
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.blueGrey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "${vm.teamPartialScore.toStringAsFixed(2)} pts",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Colors.green.shade900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
      bool isReplacedByAbsence = false,
      bool isReplacedByLuxury = false,
      bool isAbsenceActivated = false,
      bool isLuxuryActivated = false,
      String? replacementName,
      String? replacedStarterName,
      bool wasReplacedStarterCaptain = false,
      double? luxuryNetGain,
      String? allocatedPosition}) {
    final String pos = allocatedPosition ?? player.position;
    final String initial =
        pos.isNotEmpty ? pos.substring(0, 1).toUpperCase() : '?';

    final bool isBaseCaptain = !isBench &&
        (isMarketOpen
            ? (player.playerId == currentCaptainId)
            : score.isCaptain);
    final bool isEffectiveCaptain = isBaseCaptain ||
        (isBench &&
            (isLuxuryActivated || isAbsenceActivated) &&
            wasReplacedStarterCaptain);

    final double rawScore = isMarketOpen ? player.lastScore : score.totalScore;
    final double finalScore = isBench
        ? (isEffectiveCaptain ? rawScore * 2 : rawScore)
        : (isBaseCaptain ? rawScore * 2 : rawScore);

    final Color scoreColor =
        finalScore >= 0 ? Colors.green[700]! : Colors.red[700]!;

    BorderSide borderSide = BorderSide.none;
    if (isLuxuryActivated) {
      borderSide = BorderSide(color: Colors.amber.shade700, width: 1.6);
    } else if (isAbsenceActivated) {
      borderSide = BorderSide(color: Colors.blue.shade700, width: 1.6);
    } else if (isReplacedByAbsence) {
      borderSide = BorderSide(color: Colors.red.shade300, width: 1.2);
    } else if (isReplacedByLuxury) {
      borderSide = BorderSide(color: Colors.orange.shade300, width: 1.2);
    } else if (isLuxury) {
      borderSide = BorderSide(color: Colors.amber.shade600, width: 1.2);
    }

    Color? cardColor;
    if (isLuxuryActivated) {
      cardColor = const Color(0xFFFFFDF7);
    } else if (isAbsenceActivated) {
      cardColor = const Color(0xFFF7FAFD);
    } else if (isReplacedByAbsence) {
      cardColor = const Color(0xFFFFF9F9);
    } else if (isReplacedByLuxury) {
      cardColor = const Color(0xFFFAFAFA);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: (isLuxuryActivated || isAbsenceActivated) ? 2 : 1,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: borderSide,
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
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: (isReplacedByAbsence || isReplacedByLuxury)
                                  ? Colors.grey.shade700
                                  : null),
                          overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 5),
                  _buildStatusBadge(player.status),
                  if (isEffectiveCaptain)
                    Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                            color: Colors.orange, shape: BoxShape.circle),
                        child: const Icon(Icons.star,
                            color: Colors.white, size: 10)),
                  if (isReplacedByAbsence)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border:
                            Border.all(color: Colors.red.shade300, width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_off,
                              size: 10, color: Colors.red.shade800),
                          const SizedBox(width: 3),
                          Text("Não Jogou",
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red.shade800)),
                        ],
                      ),
                    )
                  else if (isReplacedByLuxury)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: Colors.orange.shade400, width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.swap_horiz,
                              size: 10, color: Colors.orange.shade900),
                          const SizedBox(width: 3),
                          Text("Substituído",
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade900)),
                        ],
                      ),
                    )
                  else if (isAbsenceActivated)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade700,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.swap_horiz, color: Colors.white, size: 10),
                          SizedBox(width: 3),
                          Text("No Time",
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white)),
                        ],
                      ),
                    )
                  else if (isLuxuryActivated)
                    Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              Colors.amber.shade500,
                              Colors.amber.shade700,
                            ]),
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.amber.withValues(alpha: 0.3),
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ]),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.diamond, color: Colors.white, size: 10),
                            SizedBox(width: 3),
                            Text("No Time",
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white)),
                          ],
                        ))
                  else if (isLuxury)
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
                ? isReplacedByAbsence
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            "-",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade400,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            "Substituído",
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                        ],
                      )
                    : isReplacedByLuxury
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                finalScore > 0
                                    ? "+${finalScore.toStringAsFixed(2)}"
                                    : finalScore.toStringAsFixed(2),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade400,
                                  fontSize: 13,
                                  decoration: TextDecoration.lineThrough,
                                  decorationColor: Colors.red.shade400,
                                  decorationThickness: 2,
                                ),
                              ),
                              Text(
                                "Cedeu vaga",
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            ],
                          )
                        : isAbsenceActivated
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: Colors.blue.shade700,
                                          width: 1.2),
                                    ),
                                    child: Text(
                                      finalScore > 0
                                          ? "+${finalScore.toStringAsFixed(2)}"
                                          : finalScore.toStringAsFixed(2),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: Colors.blue.shade900,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    "Entrou no time",
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade800,
                                    ),
                                  ),
                                ],
                              )
                            : isLuxuryActivated
                                ? Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade50,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: Colors.green.shade700,
                                              width: 1.2),
                                        ),
                                        child: Text(
                                          finalScore > 0
                                              ? "+${finalScore.toStringAsFixed(2)}"
                                              : finalScore.toStringAsFixed(2),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            color: Colors.green.shade800,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      if (luxuryNetGain != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 1),
                                          child: Text(
                                            "+${luxuryNetGain.toStringAsFixed(2)} pts p/ time",
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.amber.shade900,
                                            ),
                                          ),
                                        ),
                                    ],
                                  )
                                : Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                        color:
                                            scoreColor.withValues(alpha: 0.1),
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
                      Text(
                        "C\$ ${player.currentPrice.toStringAsFixed(2)}",
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Colors.blueGrey.shade900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            player.lastPriceChange > 0
                                ? Icons.trending_up
                                : (player.lastPriceChange < 0
                                    ? Icons.trending_down
                                    : Icons.remove),
                            size: 12,
                            color: player.lastPriceChange > 0
                                ? Colors.green.shade700
                                : (player.lastPriceChange < 0
                                    ? Colors.red.shade700
                                    : Colors.grey.shade600),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            "${player.lastPriceChange > 0 ? '+' : ''}${player.lastPriceChange.toStringAsFixed(2)}",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: player.lastPriceChange > 0
                                  ? Colors.green.shade700
                                  : (player.lastPriceChange < 0
                                      ? Colors.red.shade700
                                      : Colors.grey.shade600),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            "• M ${player.averageScore.toStringAsFixed(1)}",
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ]),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              children: [
                Text(
                  pos,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isBench
                        ? Colors.blueGrey.shade400
                        : Colors.blueGrey.shade700,
                  ),
                ),
                if (player.teamShieldUrl.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Image.network(
                    player.teamShieldUrl,
                    width: 14,
                    height: 14,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ],
                Text(
                  " • ${player.matchesPlayed} jogo${player.matchesPlayed != 1 ? 's' : ''}",
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey[50],
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isReplacedByAbsence)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.blue.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.swap_horiz,
                                size: 14, color: Colors.blue.shade800),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                "Atleta não entrou em campo na súmula da partida. O reserva ${replacementName ?? 'do banco'} entrou em seu lugar na escalação oficial da rodada.",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.blue.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (isReplacedByLuxury)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.swap_horiz,
                                size: 14, color: Colors.orange.shade800),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                "Atleta substituído pelo Reserva de Luxo${replacementName != null ? ' ($replacementName)' : ''} devido à maior pontuação no banco. Os pontos dele não contam na parcial da rodada.",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (isBench)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isAbsenceActivated
                              ? Colors.blue.shade50
                              : (isLuxuryActivated
                                  ? Colors.amber.shade50
                                  : (isLuxury
                                      ? Colors.amber.withValues(alpha: 0.1)
                                      : Colors.blueGrey
                                          .withValues(alpha: 0.08))),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isAbsenceActivated
                                ? Colors.blue.shade400
                                : (isLuxuryActivated
                                    ? Colors.amber.shade400
                                    : (isLuxury
                                        ? Colors.amber.shade300
                                        : Colors.blueGrey.shade200)),
                            width: (isLuxuryActivated || isAbsenceActivated)
                                ? 1.2
                                : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              (isAbsenceActivated || isLuxuryActivated)
                                  ? Icons.check_circle
                                  : (isLuxury
                                      ? Icons.diamond
                                      : Icons.event_seat),
                              size: 14,
                              color: isAbsenceActivated
                                  ? Colors.blue.shade800
                                  : (isLuxuryActivated
                                      ? Colors.amber.shade900
                                      : (isLuxury
                                          ? Colors.amber.shade900
                                          : Colors.blueGrey.shade700)),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                isAbsenceActivated
                                    ? "🔄 Substituição por Ausência ATIVADA! Substituiu ${replacedStarterName ?? 'o titular'} (que não atuou) e seus pontos estão somando na pontuação do time."
                                    : (isLuxuryActivated
                                        ? "💎 Reserva de Luxo ATIVADO! Substituiu ${replacedStarterName ?? 'o titular'} por pontuar mais e seus pontos estão somando no time oficial."
                                        : (isLuxury
                                            ? "Reserva de Luxo: Se pontuar mais que o titular desta posição, substitui automaticamente ao final da rodada."
                                            : "Banco de Reserva: Substitui o titular desta posição caso ele não jogue.")),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight:
                                      (isLuxuryActivated || isAbsenceActivated)
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                  color: isAbsenceActivated
                                      ? Colors.blue.shade900
                                      : (isLuxuryActivated
                                          ? Colors.amber.shade900
                                          : (isLuxury
                                              ? Colors.amber.shade900
                                              : Colors.blueGrey.shade800)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              const Text("Preço",
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.grey)),
                              const SizedBox(height: 2),
                              Text(
                                  "C\$ ${player.currentPrice.toStringAsFixed(2)}",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                            ],
                          ),
                          Container(
                              width: 1,
                              height: 24,
                              color: Colors.grey.shade200),
                          Column(
                            children: [
                              const Text("Últ. Variação",
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.grey)),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    player.lastPriceChange > 0
                                        ? Icons.trending_up
                                        : (player.lastPriceChange < 0
                                            ? Icons.trending_down
                                            : Icons.remove),
                                    size: 13,
                                    color: player.lastPriceChange > 0
                                        ? Colors.green.shade700
                                        : (player.lastPriceChange < 0
                                            ? Colors.red.shade700
                                            : Colors.grey.shade600),
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    "${player.lastPriceChange > 0 ? '+' : ''}${player.lastPriceChange.toStringAsFixed(2)}",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: player.lastPriceChange > 0
                                          ? Colors.green.shade700
                                          : (player.lastPriceChange < 0
                                              ? Colors.red.shade700
                                              : Colors.grey.shade600),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Container(
                              width: 1,
                              height: 24,
                              color: Colors.grey.shade200),
                          Column(
                            children: [
                              const Text("Média",
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.grey)),
                              const SizedBox(height: 2),
                              Text(player.averageScore.toStringAsFixed(2),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                            ],
                          ),
                          Container(
                              width: 1,
                              height: 24,
                              color: Colors.grey.shade200),
                          Column(
                            children: [
                              const Text("Última Pont.",
                                  style: TextStyle(
                                      fontSize: 10, color: Colors.grey)),
                              const SizedBox(height: 2),
                              Text(player.lastScore.toStringAsFixed(2),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
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
                      isCaptain: isEffectiveCaptain,
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

  Widget _buildStatusBadge(String status) {
    Color color;
    IconData icon;
    String label;

    switch (status.toLowerCase()) {
      case 'injured':
        color = Colors.red.shade700;
        icon = Icons.local_hospital;
        label = 'Contundido';
        break;
      case 'eternal':
        color = Colors.yellow;
        icon = Icons.star;
        label = 'Eterno';
        break;
      case 'suspended':
        color = Colors.red.shade700;
        icon = Icons.block;
        label = 'Suspenso';
        break;
      case 'doubt':
      case 'doubtful':
        color = Colors.orange.shade800;
        icon = Icons.help_outline;
        label = 'Dúvida';
        break;
      case 'null':
        color = Colors.grey.shade600;
        icon = Icons.cancel_outlined;
        label = 'Nulo';
        break;
      case 'probable':
      default:
        color = Colors.green.shade700;
        icon = Icons.check_circle;
        label = 'Provável';
        break;
    }

    return Tooltip(
      message: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 9, color: color),
            const SizedBox(width: 2.5),
            Text(
              label,
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
