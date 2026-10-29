import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/standings_sorter.dart';
import '../screens/championship/team_detail_screen.dart';
import '../models/match_model.dart';
import '../services/admin_service.dart';
import 'ui/optimized_network_image.dart';

class StandingsTableWidget extends StatelessWidget {
  final List<TeamStanding> standings;
  final List<MatchModel> allMatches;
  final Map<String, Map<String, dynamic>> liveScores;
  final String heroTagPrefix;
  final Map<String, int>? officialPositions;

  static const double _headerHeight = 40.0;
  static const double _rowHeight = 48.0;

  const StandingsTableWidget({
    super.key,
    required this.standings,
    this.allMatches = const [],
    this.liveScores = const {},
    this.heroTagPrefix = 'standings_shield_',
    this.officialPositions,
  });

  @override
  Widget build(BuildContext context) {
    if (standings.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text("Sem dados para exibir."),
        ),
      );
    }

    final bool showLast5 = allMatches.isNotEmpty;
    final bool isModel2 = AdminService.tournamentFormat == 'model_2';
    final double leftColWidth = officialPositions != null ? 192.0 : 176.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ===================================================================
          // 📌 COLUNA FIXA À ESQUERDA (# + ESCUDO + EQUIPE)
          // ===================================================================
          Container(
            width: leftColWidth,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(
                right: BorderSide(color: Color(0xFFE2E8F0), width: 1.2),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFixedHeader(),
                ...standings.asMap().entries.map((entry) {
                  final int pos = entry.key + 1;
                  final TeamStanding standing = entry.value;
                  return _buildFixedTeamRow(
                    context: context,
                    pos: pos,
                    standing: standing,
                    isModel2: isModel2,
                    totalTeams: standings.length,
                  );
                }),
              ],
            ),
          ),

          // ===================================================================
          // ↔️ COLUNAS DE ESTATÍSTICAS ROLÁVEIS HORIZONTALMENTE
          // ===================================================================
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatsHeader(showLast5: showLast5),
                  ...standings.asMap().entries.map((entry) {
                    final int pos = entry.key + 1;
                    final TeamStanding standing = entry.value;
                    return _buildStatsRow(
                      pos: pos,
                      standing: standing,
                      showLast5: showLast5,
                      isModel2: isModel2,
                      totalTeams: standings.length,
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CABEÇALHOS
  // ---------------------------------------------------------------------------

  Widget _buildFixedHeader() {
    return Container(
      height: _headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '#',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'EQUIPE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF64748B),
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsHeader({required bool showLast5}) {
    return Container(
      height: _headerHeight,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(
          bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
      ),
      child: Row(
        children: [
          _buildHeaderCell('P', width: 44, isHighlighted: true),
          _buildHeaderCell('J', width: 38),
          _buildHeaderCell('V', width: 38),
          _buildHeaderCell('E', width: 38),
          _buildHeaderCell('D', width: 38),
          _buildHeaderCell('GP', width: 40),
          _buildHeaderCell('GC', width: 40),
          _buildHeaderCell('SG', width: 44),
          _buildHeaderCell('PD', width: 42),
          _buildHeaderCell('PE', width: 40),
          _buildHeaderCell('APR %', width: 56),
          if (showLast5) _buildHeaderCell('ÚLT. 5', width: 112),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String label, {required double width, bool isHighlighted = false}) {
    return Container(
      width: width,
      height: _headerHeight,
      alignment: Alignment.center,
      color: isHighlighted ? const Color(0xFFEFF6FF) : null,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isHighlighted ? FontWeight.w900 : FontWeight.w700,
          color: isHighlighted ? const Color(0xFF1E3A8A) : const Color(0xFF64748B),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LINHAS DA COLUNA FIXA E DAS ESTATÍSTICAS
  // ---------------------------------------------------------------------------

  Color? _getZoneColor(int pos, bool isModel2) {
    if (isModel2) {
      if (pos <= 2) return const Color(0xFF16A34A); // Semifinal Direta (Verde)
      if (pos >= 3 && pos <= 6) return const Color(0xFF2563EB); // Playoff (Azul)
    } else {
      if (pos <= 4) return const Color(0xFF16A34A); // Semifinal (Verde)
    }
    return null;
  }

  bool _isZoneCutoffRow(int pos, bool isModel2, int totalTeams) {
    if (pos >= totalTeams) return false;
    if (isModel2) {
      return pos == 2 || pos == 6;
    } else {
      return pos == 4;
    }
  }

  Border _buildRowBottomBorder(int pos, bool isModel2, int totalTeams) {
    if (pos >= totalTeams) return const Border();
    final bool isCutoff = _isZoneCutoffRow(pos, isModel2, totalTeams);
    return Border(
      bottom: BorderSide(
        color: isCutoff ? const Color(0xFF94A3B8) : const Color(0xFFF1F5F9),
        width: isCutoff ? 1.5 : 1.0,
      ),
    );
  }

  Widget _buildFixedTeamRow({
    required BuildContext context,
    required int pos,
    required TeamStanding standing,
    required bool isModel2,
    required int totalTeams,
  }) {
    final team = standing.team;
    final Color? zoneColor = _getZoneColor(pos, isModel2);
    final bool isEven = pos.isEven;
    final Color rowBg = isEven ? const Color(0xFFFCFDFF) : Colors.white;

    int? posDelta;
    if (officialPositions != null && officialPositions!.containsKey(team.id)) {
      posDelta = officialPositions![team.id]! - pos;
    }

    return Material(
      color: rowBg,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TeamDetailScreen(
                team: team,
                heroTag: '$heroTagPrefix${team.id}',
              ),
            ),
          );
        },
        child: Container(
          height: _rowHeight,
          decoration: BoxDecoration(
            border: _buildRowBottomBorder(pos, isModel2, totalTeams),
          ),
          child: Row(
            children: [
              // Barra vertical indicadora de zona de classificação
              Container(
                width: 4,
                height: _rowHeight,
                color: zoneColor ?? Colors.transparent,
              ),
              const SizedBox(width: 6),
              // Badge de Posição
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: zoneColor != null
                      ? zoneColor.withValues(alpha: 0.14)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$pos',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: zoneColor ?? const Color(0xFF475569),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              // Indicador de subida/queda no Simulador
              if (posDelta != null) ...[
                const SizedBox(width: 3),
                _buildDeltaBadge(posDelta),
              ],
              const SizedBox(width: 6),
              // Escudo com proporção preservada
              if (team.shieldUrl.isNotEmpty)
                Hero(
                  tag: '$heroTagPrefix${team.id}',
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: OptimizedNetworkImage(
                      imageUrl: team.shieldUrl,
                      width: 24,
                      height: 24,
                      memCacheHeight: 72,
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      fallbackIcon: Icons.shield,
                    ),
                  ),
                )
              else
                const Icon(Icons.shield, size: 20, color: Colors.grey),
              const SizedBox(width: 7),
              // Nome da Equipe + Placar ao Vivo (se houver)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      team.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    if (liveScores.containsKey(team.id))
                      Container(
                        margin: const EdgeInsets.only(top: 1),
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                        decoration: BoxDecoration(
                          color: (liveScores[team.id]!['color'] as Color).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'AO VIVO ${liveScores[team.id]!['score']}',
                          style: TextStyle(
                            color: liveScores[team.id]!['color'] as Color,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeltaBadge(int delta) {
    if (delta == 0) {
      return const SizedBox(
        width: 14,
        child: Text(
          '•',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.bold),
        ),
      );
    }
    final bool isUp = delta > 0;
    final Color color = isUp ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    return SizedBox(
      width: 18,
      child: Text(
        isUp ? '▲$delta' : '▼${delta.abs()}',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _buildStatsRow({
    required int pos,
    required TeamStanding standing,
    required bool showLast5,
    required bool isModel2,
    required int totalTeams,
  }) {
    final bool isEven = pos.isEven;
    final Color rowBg = isEven ? const Color(0xFFFCFDFF) : Colors.white;
    final int sg = standing.goalDifference;
    final String sgText = sg > 0 ? '+$sg' : '$sg';
    final Color sgColor = sg > 0
        ? const Color(0xFF15803D)
        : (sg < 0 ? const Color(0xFFB91C1C) : const Color(0xFF64748B));

    final int pe = standing.extraPoints;
    final String peText = pe > 0 ? '+$pe' : '$pe';
    final Color peColor = pe > 0
        ? const Color(0xFF15803D)
        : (pe < 0 ? const Color(0xFFB91C1C) : const Color(0xFF64748B));

    return Container(
      height: _rowHeight,
      decoration: BoxDecoration(
        color: rowBg,
        border: _buildRowBottomBorder(pos, isModel2, totalTeams),
      ),
      child: Row(
        children: [
          // Coluna P (Pontos) em destaque
          Container(
            width: 44,
            height: _rowHeight,
            alignment: Alignment.center,
            color: const Color(0xFFF1F5F9).withValues(alpha: 0.85),
            child: Text(
              '${standing.points}',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13.5,
                color: Color(0xFF0F172A),
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          _buildStatCell('${standing.gamesPlayed}', width: 38),
          _buildStatCell('${standing.wins}', width: 38),
          _buildStatCell('${standing.draws}', width: 38),
          _buildStatCell('${standing.losses}', width: 38),
          _buildStatCell('${standing.goalsFor}', width: 40),
          _buildStatCell('${standing.goalsAgainst}', width: 40),
          _buildStatCell(
            sgText,
            width: 44,
            textColor: sgColor,
            fontWeight: sg != 0 ? FontWeight.w700 : FontWeight.w500,
          ),
          _buildStatCell('${standing.disciplinaryPoints}', width: 42),
          _buildStatCell(
            peText,
            width: 40,
            textColor: peColor,
            fontWeight: pe != 0 ? FontWeight.w700 : FontWeight.w500,
          ),
          _buildStatCell(
            _formatAproveitamento(standing),
            width: 56,
            fontWeight: FontWeight.w700,
            textColor: const Color(0xFF334155),
          ),
          if (showLast5)
            SizedBox(
              width: 112,
              height: _rowHeight,
              child: Center(
                child: _buildLast5Games(standing.team.id, allMatches),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatCell(
    String value, {
    required double width,
    Color textColor = const Color(0xFF475569),
    FontWeight fontWeight = FontWeight.w500,
  }) {
    return SizedBox(
      width: width,
      height: _rowHeight,
      child: Center(
        child: Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: fontWeight,
            color: textColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  String _formatAproveitamento(TeamStanding team) {
    if (team.gamesPlayed == 0) return '-';
    final double apr = (team.matchPoints / (team.gamesPlayed * 3)) * 100;
    return '${apr.toStringAsFixed(0)}%';
  }

  Widget _buildLast5Games(String teamId, List<MatchModel> matches) {
    final teamMatches = matches.where((m) {
      return (m.isFinished || m.isInProgress) &&
          (m.homeTeamId == teamId || m.awayTeamId == teamId);
    }).toList();

    if (teamMatches.isEmpty) {
      return const Text(
        '-',
        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
      );
    }

    teamMatches.sort(
      (a, b) => (b.datetime ?? DateTime(0)).compareTo(a.datetime ?? DateTime(0)),
    );
    final displayList = teamMatches.take(5).toList().reversed.toList();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: displayList.asMap().entries.map((entry) {
        final bool isLatest = entry.key == displayList.length - 1;
        final m = entry.value;
        final scoreH = m.scoreHome ?? 0;
        final scoreA = m.scoreAway ?? 0;
        final isHome = m.homeTeamId == teamId;

        Color bgColor;
        String letter;
        if (scoreH == scoreA) {
          bgColor = const Color(0xFF94A3B8);
          letter = 'E';
        } else if ((isHome && scoreH > scoreA) || (!isHome && scoreA > scoreH)) {
          bgColor = const Color(0xFF16A34A);
          letter = 'V';
        } else {
          bgColor = const Color(0xFFDC2626);
          letter = 'D';
        }

        return Container(
          width: 17,
          height: 17,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(4),
            border: isLatest
                ? Border.all(color: const Color(0xFF0F172A), width: 1.3)
                : null,
          ),
          child: Text(
            letter,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
        );
      }).toList(),
    );
  }
}
