import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/fantasy_models.dart';
import '../../services/analytics_service.dart';
import '../../services/fantasy_scout_service.dart';
import '../../services/fantasy_service.dart';
import '../team_logo_widget.dart';
import '../ui/optimized_network_image.dart';

class FantasyTeamLineupModal extends StatefulWidget {
  final String seasonId;
  final int round;
  final String teamId;
  final String userId;
  final String teamName;
  final String ownerName;
  final String shieldType;
  final String? customLogoUrl;
  final double roundScore;
  final double totalPoints;
  final double teamValue;
  final String? captainId;
  final List<FantasySubstitutionItem> substitutions;
  final List<String>? finalLineup;
  final int playersPlayed;
  final int playersTotal;
  final bool isMe;
  final FantasyTeam? myTeam;
  final bool isMarketOpen;
  final FantasyTeam? detailedTeam;

  const FantasyTeamLineupModal({
    super.key,
    required this.seasonId,
    required this.round,
    required this.teamId,
    required this.userId,
    required this.teamName,
    required this.ownerName,
    required this.shieldType,
    this.customLogoUrl,
    required this.roundScore,
    required this.totalPoints,
    required this.teamValue,
    this.captainId,
    this.substitutions = const [],
    this.finalLineup,
    this.playersPlayed = 0,
    this.playersTotal = 6,
    required this.isMe,
    this.myTeam,
    required this.isMarketOpen,
    this.detailedTeam,
  });

  static void show(
    BuildContext context, {
    required String seasonId,
    required int round,
    required String teamId,
    required String userId,
    required String teamName,
    required String ownerName,
    required String shieldType,
    String? customLogoUrl,
    required double roundScore,
    required double totalPoints,
    required double teamValue,
    String? captainId,
    List<FantasySubstitutionItem> substitutions = const [],
    List<String>? finalLineup,
    int playersPlayed = 0,
    int playersTotal = 6,
    required bool isMe,
    FantasyTeam? myTeam,
    required bool isMarketOpen,
    FantasyTeam? detailedTeam,
  }) {
    AnalyticsService.logCustomScreenView('Fantasy_Team_Lineup_Modal');
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
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return FantasyTeamLineupModal(
              seasonId: seasonId,
              round: round,
              teamId: teamId,
              userId: userId,
              teamName: teamName,
              ownerName: ownerName,
              shieldType: shieldType,
              customLogoUrl: customLogoUrl,
              roundScore: roundScore,
              totalPoints: totalPoints,
              teamValue: teamValue,
              captainId: captainId,
              substitutions: substitutions,
              finalLineup: finalLineup,
              playersPlayed: playersPlayed,
              playersTotal: playersTotal,
              isMe: isMe,
              myTeam: myTeam,
              isMarketOpen: isMarketOpen,
              detailedTeam: detailedTeam,
            );
          },
        );
      },
    );
  }

  @override
  State<FantasyTeamLineupModal> createState() => _FantasyTeamLineupModalState();
}

class _FantasyTeamLineupModalState extends State<FantasyTeamLineupModal> {
  // FINOPS: Cache em memória de equipes para evitar re-leituras do Firestore
  static final Map<String, FantasyTeam> _teamMemoryCache = {};

  int _selectedTab = 0; // 0 = Escalação, 1 = Duelo 1x1

  FantasyTeam? _detailedTeam;
  List<FantasyPlayer> _allPlayers = [];
  bool _isLoadingPlayers = true;

  @override
  void initState() {
    super.initState();
    // Se o mercado estiver aberto, a escalação da próxima rodada é secreta (regra Cartola)
    // então abre direto no confronto 1x1
    if (widget.isMarketOpen && !widget.isMe && widget.myTeam != null) {
      _selectedTab = 1;
    }
    _loadSquad();
  }

  Future<void> _loadSquad() async {
    final fantasyService = Provider.of<FantasyService>(context, listen: false);

    // 1. Obtém o FantasyTeam detalhado (tenta parâmetro -> cache de memória -> Firestore)
    if (widget.detailedTeam != null) {
      _detailedTeam = widget.detailedTeam;
      if (widget.teamId.isNotEmpty) {
        _teamMemoryCache[widget.teamId] = widget.detailedTeam!;
      }
    } else if (widget.teamId.isNotEmpty &&
        _teamMemoryCache.containsKey(widget.teamId)) {
      _detailedTeam = _teamMemoryCache[widget.teamId];
    } else if (widget.userId.isNotEmpty &&
        _teamMemoryCache.containsKey(widget.userId)) {
      _detailedTeam = _teamMemoryCache[widget.userId];
    } else {
      try {
        DocumentSnapshot? doc;
        if (widget.teamId.isNotEmpty) {
          doc = await FirebaseFirestore.instance
              .collection('fantasy_teams')
              .doc(widget.teamId)
              .get();
        }
        if ((doc == null || !doc.exists) &&
            widget.userId.isNotEmpty &&
            widget.userId != widget.teamId) {
          doc = await FirebaseFirestore.instance
              .collection('fantasy_teams')
              .doc(widget.userId)
              .get();
        }
        if (doc == null || !doc.exists) {
          final querySnap = await FirebaseFirestore.instance
              .collection('fantasy_teams')
              .where('user_id',
                  isEqualTo: widget.userId.isNotEmpty
                      ? widget.userId
                      : widget.teamId)
              .limit(1)
              .get();
          if (querySnap.docs.isNotEmpty) {
            doc = querySnap.docs.first;
          }
        }

        if (doc != null && doc.exists) {
          _detailedTeam = FantasyTeam.fromFirestore(doc);
          if (widget.teamId.isNotEmpty) {
            _teamMemoryCache[widget.teamId] = _detailedTeam!;
          }
          if (widget.userId.isNotEmpty) {
            _teamMemoryCache[widget.userId] = _detailedTeam!;
          }
        }
      } catch (e) {
        debugPrint("Erro ao buscar detalhes do time: $e");
      }
    }

    // 2. Coleta todos os IDs necessários: titulares, reservas e substituições
    final Set<String> idsToFetch = {};
    if (widget.finalLineup != null && widget.finalLineup!.isNotEmpty) {
      idsToFetch.addAll(widget.finalLineup!);
    }
    if (_detailedTeam != null) {
      idsToFetch.addAll(_detailedTeam!.lineupPlayerIds);
      idsToFetch.addAll(_detailedTeam!.benchPlayerIds);
    }
    for (var sub in widget.substitutions) {
      if (sub.outPlayerId.isNotEmpty) idsToFetch.add(sub.outPlayerId);
      if (sub.inPlayerId.isNotEmpty) idsToFetch.add(sub.inPlayerId);
    }

    if (idsToFetch.isNotEmpty) {
      try {
        final players =
            await fantasyService.getPlayersByIds(idsToFetch.toList());
        if (mounted) {
          setState(() {
            _allPlayers = players;
            _isLoadingPlayers = false;
          });
        }
        return;
      } catch (e) {
        debugPrint("Erro ao buscar jogadores: $e");
      }
    }

    if (mounted) {
      setState(() {
        _isLoadingPlayers = false;
      });
    }
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
        return 6;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool canShowDuelo = !widget.isMe && widget.myTeam != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        children: [
          // Puxador do Modal
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
          const SizedBox(height: 12),

          // Header do Time
          _buildTeamHeader(),
          const SizedBox(height: 12),

          // Seletor de Abas (Escalação vs Duelo 1x1)
          if (canShowDuelo) ...[
            _buildTabSelector(),
            const SizedBox(height: 12),
          ],

          // Conteúdo da Aba
          Expanded(
            child: _selectedTab == 0
                ? _buildLineupTab()
                : _buildHeadToHeadTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          TeamLogoWidget(
            logoUrl: widget.customLogoUrl,
            shieldType: widget.shieldType,
            radius: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.teamName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.isMe) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.shade700,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          "VOCÊ",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  "Técnico: ${widget.ownerName}",
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        "⚽ ${widget.playersPlayed}/${widget.playersTotal} jogaram",
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Total: ${widget.totalPoints.toStringAsFixed(1)} pts",
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Badge da Parcial da Rodada
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.shade800, Colors.green.shade600],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.greenAccent.shade400, width: 1),
            ),
            child: Column(
              children: [
                Text(
                  "RODADA ${widget.round}",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
                Text(
                  "${widget.roundScore.toStringAsFixed(2)} pts",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSelector() {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _selectedTab = 0),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: BoxDecoration(
                  color: _selectedTab == 0 ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _selectedTab == 0
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          )
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 15,
                      color: _selectedTab == 0
                          ? Theme.of(context).primaryColor
                          : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "Escalação da Rodada",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _selectedTab == 0
                            ? Theme.of(context).primaryColor
                            : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => setState(() => _selectedTab = 1),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: BoxDecoration(
                  color: _selectedTab == 1 ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _selectedTab == 1
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          )
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.compare_arrows_rounded,
                      size: 16,
                      color: _selectedTab == 1
                          ? Colors.deepOrange
                          : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "Duelo 1x1",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _selectedTab == 1
                            ? Colors.deepOrange
                            : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineupTab() {
    // Caso especial: Mercado ABERTO
    if (widget.isMarketOpen && !widget.isMe) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.amber.shade300, width: 2),
                ),
                child: Icon(Icons.lock_outline_rounded,
                    size: 36, color: Colors.amber.shade800),
              ),
              const SizedBox(height: 16),
              const Text(
                "Escalação Protegida",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                "O mercado da Rodada ${widget.round} está ABERTO para alterações. Por regra de confidencialidade do Fantasy, a escalação dos adversários é revelada apenas após o fechamento do mercado.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => setState(() => _selectedTab = 1),
                icon: const Icon(Icons.compare_arrows_rounded, size: 16),
                label: const Text("Ver Confronto Direto 1x1"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoadingPlayers) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Identifica capitão ativo da rodada
    final activeCaptainId = widget.captainId ?? _detailedTeam?.captainId;

    // Titulares originais escalados pela equipe
    final List<String> starterPids = _detailedTeam != null &&
            _detailedTeam!.lineupPlayerIds.isNotEmpty
        ? _detailedTeam!.lineupPlayerIds
        : (widget.finalLineup ?? []);

    // Reservas originais do banco de reservas
    final List<String> benchPids = _detailedTeam?.benchPlayerIds ?? [];

    final starters =
        _allPlayers.where((p) => starterPids.contains(p.playerId)).toList();
    final bench =
        _allPlayers.where((p) => benchPids.contains(p.playerId)).toList();

    starters.sort(
        (a, b) => _rankingPos(a.position).compareTo(_rankingPos(b.position)));
    bench.sort(
        (a, b) => _rankingPos(a.position).compareTo(_rankingPos(b.position)));

    return StreamBuilder<Map<String, FantasyScoutDetail>>(
      stream: FantasyScoutService()
          .streamLiveScores(widget.seasonId, widget.round),
      builder: (context, scoreSnap) {
        final scoresMap = scoreSnap.data ?? {};

        return ListView(
          padding: const EdgeInsets.only(top: 4, bottom: 20),
          children: [
            // Banner explicativo do status
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.bolt, color: Colors.blue.shade700, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "Pontuação parcial ao vivo dos atletas escalados na Rodada ${widget.round}.",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Cabeçalho Titulares
            Row(
              children: [
                const Icon(Icons.shield, size: 16, color: Colors.blueGrey),
                const SizedBox(width: 6),
                const Text(
                  "Titulares em Campo",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                  ),
                ),
                const Spacer(),
                Text(
                  "${starters.length} atletas",
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            if (starters.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                alignment: Alignment.center,
                child: Text(
                  "Nenhum atleta titular escalado.",
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              )
            else
              ...starters.map((p) {
                final isCap = p.playerId == activeCaptainId;
                final scout = scoresMap[p.playerId];
                final double rawScore = scout?.totalScore ?? 0.0;

                // Verifica se este titular foi substituído na rodada
                final sub = widget.substitutions
                    .where((s) => s.outPlayerId == p.playerId)
                    .firstOrNull;

                final bool wasSubstitutedOut = sub != null;
                final double effectiveScore = wasSubstitutedOut
                    ? 0.0
                    : (isCap ? (rawScore * 2) : rawScore);

                String? subNote;
                if (sub != null) {
                  final inP = _allPlayers
                      .where((item) => item.playerId == sub.inPlayerId)
                      .firstOrNull;
                  final inName = inP?.name ?? "Reserva";
                  subNote = sub.type == 'luxury'
                      ? "Substituído na pontuação por $inName (Reserva de Luxo)"
                      : "Não jogou • Substituído por $inName";
                }

                return _buildPlayerCard(
                  player: p,
                  isCaptain: isCap,
                  rawScore: rawScore,
                  effectiveScore: effectiveScore,
                  scout: scout,
                  subNote: subNote,
                  isBench: false,
                  wasSubstitutedOut: wasSubstitutedOut,
                  hasEntered: false,
                );
              }),

            // Seção Banco de Reservas
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.event_seat, size: 16, color: Colors.blueGrey),
                const SizedBox(width: 6),
                const Text(
                  "Banco de Reservas",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                  ),
                ),
                const Spacer(),
                Text(
                  "${bench.length} suplentes",
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            if (bench.isEmpty)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.event_seat_outlined,
                        size: 18, color: Colors.grey.shade500),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Nenhum atleta suplente escalado no banco de reservas.",
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...bench.map((p) {
                final isLuxury =
                    (_detailedTeam?.luxuryReserveId == p.playerId);
                final scout = scoresMap[p.playerId];
                final double rawScore = scout?.totalScore ?? 0.0;

                // Verifica se este reserva entrou em campo somando pontos
                final sub = widget.substitutions
                    .where((s) => s.inPlayerId == p.playerId)
                    .firstOrNull;

                final bool hasEntered = sub != null;
                final double effectiveScore = hasEntered ? rawScore : 0.0;

                String? subNote;
                if (sub != null) {
                  final outP = _allPlayers
                      .where((item) => item.playerId == sub.outPlayerId)
                      .firstOrNull;
                  final outName = outP?.name ?? "Titular";
                  subNote = sub.type == 'luxury'
                      ? "Entrou como Reserva de Luxo no lugar de $outName (+${rawScore.toStringAsFixed(1)} pts)"
                      : "Entrou por Ausência de $outName (+${rawScore.toStringAsFixed(1)} pts)";
                } else if (isLuxury) {
                  subNote = "Reserva de Luxo";
                }

                return _buildPlayerCard(
                  player: p,
                  isCaptain: false,
                  rawScore: rawScore,
                  effectiveScore: effectiveScore,
                  scout: scout,
                  isLuxury: isLuxury,
                  subNote: subNote,
                  isBench: true,
                  wasSubstitutedOut: false,
                  hasEntered: hasEntered,
                );
              }),
          ],
        );
      },
    );
  }

  Widget _buildPlayerCard({
    required FantasyPlayer player,
    required bool isCaptain,
    required double rawScore,
    required double effectiveScore,
    FantasyScoutDetail? scout,
    String? subNote,
    bool isBench = false,
    bool isLuxury = false,
    bool wasSubstitutedOut = false,
    bool hasEntered = false,
  }) {
    final bool hasScore = rawScore != 0.0;
    final bool isPositive = effectiveScore > 0;
    final bool isNegative = effectiveScore < 0;

    final Color scoreColor = !hasScore
        ? Colors.grey.shade700
        : (isPositive
            ? const Color(0xFF047857)
            : (isNegative ? const Color(0xFFDC2626) : Colors.grey.shade800));

    final Color cardBgColor = isCaptain
        ? const Color(0xFFFEF9C3)
        : (wasSubstitutedOut
            ? const Color(0xFFFFFBEB)
            : (hasEntered
                ? const Color(0xFFF0FDF4)
                : (isLuxury
                    ? const Color(0xFFEFF6FF)
                    : (isBench ? Colors.grey.shade50 : Colors.white))));

    final Color cardBorderColor = isCaptain
        ? const Color(0xFFFACC15)
        : (wasSubstitutedOut
            ? Colors.amber.shade300
            : (hasEntered
                ? Colors.green.shade400
                : (isLuxury
                    ? const Color(0xFF93C5FD)
                    : Colors.grey.shade200)));

    final double displayScore = wasSubstitutedOut
        ? rawScore
        : (isBench && !hasEntered ? rawScore : effectiveScore);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cardBorderColor,
          width: isCaptain || isLuxury || hasEntered || wasSubstitutedOut
              ? 1.5
              : 1,
        ),
      ),
      child: Row(
        children: [
          // Foto do Atleta
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              width: 38,
              height: 38,
              child: player.photoUrl.isNotEmpty
                  ? OptimizedNetworkImage(
                      imageUrl: player.photoUrl,
                      memCacheWidth: 80,
                      memCacheHeight: 80,
                    )
                  : Container(
                      color: Colors.grey.shade300,
                      child: Icon(Icons.person,
                          color: Colors.grey.shade600, size: 22),
                    ),
            ),
          ),
          const SizedBox(width: 10),

          // Informações do Atleta
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        player.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: wasSubstitutedOut
                              ? Colors.grey.shade600
                              : const Color(0xFF0F172A),
                          decoration: wasSubstitutedOut
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isCaptain) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade700,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          "CAP (2x)",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                    if (isLuxury) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade700,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          "LUXO",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                    if (hasEntered) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.green.shade700,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          "ENTROU",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                    if (wasSubstitutedOut) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade800,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          "SUBSTITUÍDO",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  "${player.position} • C\$ ${player.currentPrice.toStringAsFixed(2)}",
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subNote != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subNote,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: wasSubstitutedOut
                          ? Colors.amber.shade900
                          : (hasEntered
                              ? Colors.green.shade800
                              : Colors.blue.shade800),
                    ),
                  ),
                ],
                // Scouts destacados se houver
                if (scout != null && scout.hasStats) ...[
                  const SizedBox(height: 3),
                  _buildScoutChips(scout),
                ],
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Pontuação Parcial
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "${displayScore >= 0 ? '+' : ''}${displayScore.toStringAsFixed(2)}",
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: wasSubstitutedOut
                      ? Colors.grey.shade400
                      : (isBench && !hasEntered
                          ? Colors.grey.shade600
                          : scoreColor),
                  decoration:
                      wasSubstitutedOut ? TextDecoration.lineThrough : null,
                ),
              ),
              Text(
                wasSubstitutedOut
                    ? "substituído"
                    : (hasEntered
                        ? "pts (somou)"
                        : (isBench
                            ? "pts (banco)"
                            : (isCaptain ? "pts (dobro)" : "pts"))),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: wasSubstitutedOut
                      ? Colors.amber.shade900
                      : (hasEntered
                          ? Colors.green.shade700
                          : Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScoutChips(FantasyScoutDetail scout) {
    final chips = <Widget>[];

    if (scout.goals > 0) {
      chips.add(_chip("⚽ ${scout.goals}", Colors.green.shade700));
    }
    if (scout.assists > 0) {
      chips.add(_chip("🅰️ ${scout.assists}", Colors.blue.shade700));
    }
    if (scout.difficultSaves > 0) {
      chips.add(_chip("🧤 ${scout.difficultSaves} DEF", Colors.cyan.shade800));
    }
    if (scout.cleanSheets > 0) {
      chips.add(_chip("SG", Colors.teal.shade700));
    }
    if (scout.penaltiesSaved > 0) {
      chips.add(_chip("🧤 PÊNALTI", Colors.purple.shade700));
    }
    if (scout.yellows > 0) {
      chips.add(_chip("🟨 ${scout.yellows}", Colors.amber.shade800));
    }
    if (scout.reds > 0) {
      chips.add(_chip("🟥 ${scout.reds}", Colors.red.shade700));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: chips,
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildHeadToHeadTab() {
    final my = widget.myTeam!;
    final double pointsDiff = my.totalPoints - widget.totalPoints;
    final double valueDiff = my.teamValue - widget.teamValue;
    final double roundDiff = my.lastScore - widget.roundScore;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 4, bottom: 20),
      child: Column(
        children: [
          // Arena 1x1
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  offset: Offset(0, 4),
                )
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Meu Time
                Expanded(
                  child: Column(
                    children: [
                      TeamLogoWidget(
                        shieldType: my.shieldType,
                        logoUrl: my.customLogoUrl,
                        radius: 24,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        my.teamName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        "Você",
                        style: TextStyle(
                          color: Colors.greenAccent.shade400,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                // VS Badge
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade600,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Text(
                    "VS",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),

                // Time Rival
                Expanded(
                  child: Column(
                    children: [
                      TeamLogoWidget(
                        shieldType: widget.shieldType,
                        logoUrl: widget.customLogoUrl,
                        radius: 24,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.teamName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        widget.ownerName,
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Métricas Comparativas
          _buildComparisonRow(
            label: "Pontuação Geral",
            myValue: "${my.totalPoints.toStringAsFixed(1)} pts",
            rivalValue: "${widget.totalPoints.toStringAsFixed(1)} pts",
            isMyWinning: pointsDiff >= 0,
            diffLabel:
                "${pointsDiff >= 0 ? '+' : ''}${pointsDiff.toStringAsFixed(1)} pts",
          ),
          const SizedBox(height: 8),
          _buildComparisonRow(
            label: "Patrimônio",
            myValue: "C\$ ${my.teamValue.toStringAsFixed(2)}",
            rivalValue: "C\$ ${widget.teamValue.toStringAsFixed(2)}",
            isMyWinning: valueDiff >= 0,
            diffLabel:
                "${valueDiff >= 0 ? '+' : ''}C\$ ${valueDiff.toStringAsFixed(2)}",
          ),
          const SizedBox(height: 8),
          _buildComparisonRow(
            label: "Parcial da Rodada",
            myValue: "${my.lastScore.toStringAsFixed(1)} pts",
            rivalValue: "${widget.roundScore.toStringAsFixed(1)} pts",
            isMyWinning: roundDiff >= 0,
            diffLabel:
                "${roundDiff >= 0 ? '+' : ''}${roundDiff.toStringAsFixed(1)} pts",
          ),
          const SizedBox(height: 20),

          // Botão Compartilhar Desafio no WhatsApp
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                HapticFeedback.mediumImpact();
                AnalyticsService.logShare('fantasy_h2h_challenge', widget.teamName);

                final message =
                    "⚔️ *DESAFIO 1x1 NO FANTASY CARTOLA FJF!* ⚽🔥\n\n"
                    "🛡️ *${my.teamName}* (${my.totalPoints.toStringAsFixed(1)} pts)\n"
                    "⚡ *VERSUS*\n"
                    "🛡️ *${widget.teamName}* (${widget.totalPoints.toStringAsFixed(1)} pts)\n\n"
                    "Quem vai mitar na próxima rodada? Monte seu time no app:\n"
                    "👉 https://acefjf.web.app\n\n#CartolaFJF #Duelo1x1";

                await SharePlus.instance.share(
                  ShareParams(
                    text: message,
                    subject: "Desafio 1x1: ${my.teamName} vs ${widget.teamName}",
                  ),
                );
              },
              icon: const Icon(Icons.share, size: 18),
              label: const Text("Desafiar no WhatsApp"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonRow({
    required String label,
    required String myValue,
    required String rivalValue,
    required bool isMyWinning,
    required String diffLabel,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              myValue,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isMyWinning ? Colors.green.shade700 : Colors.black87,
              ),
            ),
          ),
          Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                diffLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isMyWinning ? Colors.green.shade700 : Colors.red.shade700,
                ),
              ),
            ],
          ),
          Expanded(
            child: Text(
              rivalValue,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: !isMyWinning ? Colors.green.shade700 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
