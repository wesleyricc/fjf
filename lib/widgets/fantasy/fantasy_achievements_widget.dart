import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/fantasy_models.dart';
import '../../services/analytics_service.dart';

class FantasyAchievement {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final bool isUnlocked;
  final double progress;
  final String progressLabel;

  const FantasyAchievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.isUnlocked,
    required this.progress,
    required this.progressLabel,
  });
}

class FantasyAchievementsService {
  static List<FantasyAchievement> evaluateAchievements({
    required FantasyTeam team,
    FantasyRoundSummary? roundSummary,
    double? bestRoundScore,
  }) {
    final double patrimony = team.teamValue;
    final double totalPoints = team.totalPoints;
    final double highestScore = (bestRoundScore != null && bestRoundScore > team.lastScore)
        ? bestRoundScore
        : team.lastScore;

    // 1. Magnata da FJF (Patrimônio >= 75)
    final bool isMagnata = patrimony >= 75.0;
    final double magnataProg = (patrimony / 75.0).clamp(0.0, 1.0);

    // 2. Pontuador de Elite (Total Points >= 500)
    final bool isPontuador = totalPoints >= 500.0;
    final double pontuadorProg = (totalPoints / 500.0).clamp(0.0, 1.0);

    // 3. Capitão de Ouro (Capitão definido)
    final bool isCapitao = team.captainId != null && team.captainId!.isNotEmpty;

    // 4. Estrategista de Luxo (Reserva de luxo definido)
    final bool isLuxo =
        team.luxuryReserveId != null && team.luxuryReserveId!.isNotEmpty;

    // 5. Elenco Completo (6 titulares + 5 reservas)
    final int totalEscalados =
        team.lineupPlayerIds.length + team.benchPlayerIds.length;
    final bool isCompleto =
        team.lineupPlayerIds.length == 6 && team.benchPlayerIds.length == 5;
    final double completoProg = (totalEscalados / 11.0).clamp(0.0, 1.0);

    // 6. Rodada Monstruosa / Mito da Rodada (Qualquer rodada com >= 100 pontos)
    final bool isMito = highestScore >= 100.0;
    final double mitoProg = (highestScore / 100.0).clamp(0.0, 1.0);

    return [
      FantasyAchievement(
        id: 'magnata',
        title: 'Magnata da FJF',
        description: 'Alcance um patrimônio de pelo menos C\$ 75,00.',
        icon: Icons.monetization_on,
        color: const Color(0xFF10B981), // Emerald
        isUnlocked: isMagnata,
        progress: magnataProg,
        progressLabel: 'C\$ ${patrimony.toStringAsFixed(2)} / C\$ 75,00',
      ),
      FantasyAchievement(
        id: 'pontuador',
        title: 'Pontuador de Elite',
        description: 'Atinja 500 pontos acumulados no campeonato.',
        icon: Icons.emoji_events,
        color: const Color(0xFFF59E0B), // Amber
        isUnlocked: isPontuador,
        progress: pontuadorProg,
        progressLabel: '${totalPoints.toStringAsFixed(1)} / 500 pts',
      ),
      FantasyAchievement(
        id: 'capitao',
        title: 'Faixa no Braço',
        description: 'Escale seu time com um Capitão para pontuação em dobro.',
        icon: Icons.star,
        color: const Color(0xFFF97316), // Orange
        isUnlocked: isCapitao,
        progress: isCapitao ? 1.0 : 0.0,
        progressLabel: isCapitao ? 'Concluído' : 'Sem Capitão',
      ),
      FantasyAchievement(
        id: 'luxo',
        title: 'Diamante Bruto',
        description:
            'Escale um Reserva de Luxo para garantir substituição automática.',
        icon: Icons.diamond,
        color: const Color(0xFF38BDF8), // Sky Blue
        isUnlocked: isLuxo,
        progress: isLuxo ? 1.0 : 0.0,
        progressLabel: isLuxo ? 'Concluído' : 'Sem Reserva de Luxo',
      ),
      FantasyAchievement(
        id: 'completo',
        title: 'Esquadrão Cheio',
        description:
            'Escale os 6 titulares e preencha todos os 5 suplentes do banco.',
        icon: Icons.groups,
        color: const Color(0xFF8B5CF6), // Purple
        isUnlocked: isCompleto,
        progress: completoProg,
        progressLabel: '$totalEscalados / 11 atletas',
      ),
      FantasyAchievement(
        id: 'mito',
        title: 'Mito da Rodada',
        description: 'Alcance mais de 100 pontos em uma única rodada oficial.',
        icon: Icons.bolt,
        color: const Color(0xFFEF4444), // Red
        isUnlocked: isMito,
        progress: mitoProg,
        progressLabel: isMito
            ? '${highestScore.toStringAsFixed(1)} pts (Mito!)'
            : '${highestScore.toStringAsFixed(1)} / 100 pts',
      ),
    ];
  }
}

class FantasyAchievementsSection extends StatelessWidget {
  final FantasyTeam team;
  final FantasyRoundSummary? roundSummary;
  final double? bestRoundScore;
  final bool isCompact;

  const FantasyAchievementsSection({
    super.key,
    required this.team,
    this.roundSummary,
    this.bestRoundScore,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final achievements = FantasyAchievementsService.evaluateAchievements(
      team: team,
      roundSummary: roundSummary,
      bestRoundScore: bestRoundScore,
    );
    final unlockedCount = achievements.where((a) => a.isUnlocked).length;

    if (isCompact) {
      return _buildCompact(context, achievements, unlockedCount);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.military_tech, color: Colors.amber, size: 22),
                const SizedBox(width: 8),
                const Text(
                  "Conquistas & Medalhas",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            InkWell(
              onTap: () => _showAchievementsModal(context, achievements),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  "$unlockedCount de ${achievements.length} ➔",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: achievements.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final a = achievements[index];
              return _buildBadgeChip(context, a,
                  () => _showAchievementsModal(context, achievements));
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCompact(
      BuildContext context, List<FantasyAchievement> achievements, int unlockedCount) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.shade300, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            _showAchievementsModal(context, achievements);
          },
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.military_tech_rounded,
                      color: Colors.amber.shade900, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Text(
                            "Conquistas & Medalhas",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: unlockedCount > 0
                                  ? const Color(0xFFD1FAE5)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "$unlockedCount/${achievements.length}",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: unlockedCount > 0
                                    ? const Color(0xFF065F46)
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        unlockedCount == achievements.length
                            ? "Todas as medalhas desbloqueadas! 🏆"
                            : "Toque para ver seus objetivos e progresso",
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: achievements.map((a) {
                    return Padding(
                      padding: const EdgeInsets.only(left: 3),
                      child: Icon(
                        a.isUnlocked ? a.icon : Icons.lock_outline,
                        size: 15,
                        color: a.isUnlocked ? a.color : Colors.grey.shade300,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadgeChip(
      BuildContext context, FantasyAchievement a, VoidCallback onTap) {
    final bool unlocked = a.isUnlocked;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 120,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color:
              unlocked ? a.color.withValues(alpha: 0.12) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: unlocked
                ? a.color.withValues(alpha: 0.4)
                : Colors.grey.shade300,
            width: unlocked ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  unlocked ? a.icon : Icons.lock_outline,
                  size: 20,
                  color: unlocked ? a.color : Colors.grey.shade400,
                ),
                if (unlocked) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.check_circle, size: 12, color: a.color),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              a.title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: unlocked ? Colors.black87 : Colors.grey.shade500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            Text(
              unlocked ? "Desbloqueado" : a.progressLabel,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: unlocked ? a.color : Colors.grey.shade500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _showAchievementsModal(
      BuildContext context, List<FantasyAchievement> achievements) {
    AnalyticsService.logCustomScreenView('Fantasy_Achievements_Modal');
    HapticFeedback.lightImpact();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            final unlocked = achievements.where((a) => a.isUnlocked).length;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Galeria de Conquistas",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.shade400),
                        ),
                        child: Text(
                          "$unlocked de ${achievements.length} Completas",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  Expanded(
                    child: ListView.separated(
                      controller: scrollController,
                      itemCount: achievements.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final a = achievements[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 6),
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: a.isUnlocked
                                  ? a.color.withValues(alpha: 0.15)
                                  : Colors.grey.shade100,
                              border: Border.all(
                                color: a.isUnlocked
                                    ? a.color
                                    : Colors.grey.shade300,
                                width: a.isUnlocked ? 2 : 1,
                              ),
                            ),
                            child: Icon(
                              a.isUnlocked ? a.icon : Icons.lock_outline,
                              color:
                                  a.isUnlocked ? a.color : Colors.grey.shade400,
                              size: 22,
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(
                                a.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: a.isUnlocked
                                      ? Colors.black87
                                      : Colors.grey.shade600,
                                ),
                              ),
                              if (a.isUnlocked) ...[
                                const SizedBox(width: 6),
                                Icon(Icons.check_circle,
                                    size: 14, color: a.color),
                              ],
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 2),
                              Text(
                                a.description,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: a.progress,
                                        backgroundColor: Colors.grey.shade200,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                a.isUnlocked
                                                    ? a.color
                                                    : Colors.grey.shade400),
                                        minHeight: 6,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    a.progressLabel,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: a.isUnlocked
                                          ? a.color
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
