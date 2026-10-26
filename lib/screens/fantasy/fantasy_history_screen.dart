import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/fantasy_auth_service.dart';
import '../../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../../services/fantasy_service.dart';
import '../../widgets/fantasy/fantasy_bottom_nav_bar.dart';

class FantasyHistoryScreen extends StatefulWidget {
  const FantasyHistoryScreen({super.key});

  @override
  State<FantasyHistoryScreen> createState() => _FantasyHistoryScreenState();
}

class _FantasyHistoryScreenState extends State<FantasyHistoryScreen> {
  @override
  void initState() {
    super.initState();
    // 🚨 Analytics: Rastreia a visualização do histórico do usuário no Fantasy
    AnalyticsService.logCustomScreenView('Fantasy_History_Screen');
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<FantasyAuthService>(context, listen: false);
    final userId = authService.user?.uid;

    if (userId == null) {
      return const Scaffold(body: Center(child: Text("Erro de usuário")));
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo_fjf_fantasy.webp', height: 28),
            const SizedBox(width: 8),
            const Text("Minha Evolução"),
          ],
        ),
      ),
      bottomNavigationBar:
          const FantasyBottomNavBar(currentRoute: '/fantasy-history'),
      body: StreamBuilder<QuerySnapshot>(
        stream: FantasyService().streamHistory(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history_edu, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text("Nenhum histórico disponível.",
                      style: TextStyle(color: Colors.grey)),
                  const Text("Participe das rodadas para ver sua evolução.",
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            );
          }

          final rawDocs = snapshot.data!.docs;

          // 1. Ordena cópia cronológica (R1 em diante) para reconstruir a evolução financeira real
          final sortedAsc = List<QueryDocumentSnapshot>.from(rawDocs)
            ..sort((a, b) => ((a.data() as Map<String, dynamic>)['round'] ?? 0)
                .compareTo((b.data() as Map<String, dynamic>)['round'] ?? 0));

          double runningPatrimony = 50.0;
          final Map<int, double> roundPatrimonyMap = {};
          final Map<int, double> roundVariationMap = {};
          double totalPointsSum = 0.0;
          double bestScore = 0.0;

          for (final doc in sortedAsc) {
            final data = doc.data() as Map<String, dynamic>;
            final int round = data['round'] ?? 0;
            final double points = (data['points'] ?? 0).toDouble();
            final double? docVar = (data['variation'] as num?)?.toDouble();
            final double? docPat = (data['patrimony'] as num?)?.toDouble();

            totalPointsSum += points;
            if (points > bestScore) bestScore = points;

            double roundPat;
            double roundVar;

            if (docVar != null) {
              roundVar = docVar;
              roundPat = double.parse((runningPatrimony + docVar).toStringAsFixed(2));
            } else if (docPat != null) {
              roundPat = docPat;
              roundVar = double.parse((roundPat - runningPatrimony).toStringAsFixed(2));
            } else {
              roundPat = runningPatrimony;
              roundVar = 0.0;
            }

            // Auto-cura no Firestore: se o patrimônio salvo no doc foi sobrescrito ou difere do real
            if (docPat == null || (docPat - roundPat).abs() > 0.01) {
              doc.reference.update({'patrimony': roundPat}).catchError((e) {
                debugPrint("Aviso ao auto-curar patrimônio histórico da rodada $round: $e");
              });
            }

            roundPatrimonyMap[round] = roundPat;
            roundVariationMap[round] = roundVar;
            runningPatrimony = roundPat;
          }

          // 2. Ordena da rodada mais recente para a mais antiga para exibição
          final displayDocs = List<QueryDocumentSnapshot>.from(rawDocs)
            ..sort((a, b) => ((b.data() as Map<String, dynamic>)['round'] ?? 0)
                .compareTo((a.data() as Map<String, dynamic>)['round'] ?? 0));

          final double currentPatrimony = runningPatrimony;
          final double totalVariation = currentPatrimony - 50.0;
          final double avgPoints =
              sortedAsc.isNotEmpty ? (totalPointsSum / sortedAsc.length) : 0.0;

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // 🏆 Card de Resumo da Evolução (Header)
              _buildSummaryHeader(
                currentPatrimony: currentPatrimony,
                totalVariation: totalVariation,
                totalPoints: totalPointsSum,
                avgPoints: avgPoints,
                roundsCount: sortedAsc.length,
              ),

              const SizedBox(height: 16),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  "Histórico Rodada a Rodada",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // 📋 Lista de Cards de Rodadas
              ...displayDocs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final int round = data['round'] ?? 0;
                final double points = (data['points'] ?? 0).toDouble();
                final double patrimony = roundPatrimonyMap[round] ??
                    (data['patrimony'] ?? 50.0).toDouble();
                final double variation = roundVariationMap[round] ??
                    (data['variation'] ?? 0.0).toDouble();

                // Feedback visual de pontuação
                Color scoreColor = Colors.grey[700]!;
                if (points >= 60) {
                  scoreColor = Colors.green[700]!;
                } else if (points >= 40) {
                  scoreColor = Colors.blue[700]!;
                } else if (points >= 20) {
                  scoreColor = Colors.orange[800]!;
                } else {
                  scoreColor = Colors.red[700]!;
                }

                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 16),
                    child: Row(
                      children: [
                        // Círculo com a Rodada
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                "RODADA",
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                "$round",
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 16),

                        // Dados (Patrimônio e Variação daquela rodada)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Patrimônio da Rodada",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  const Icon(Icons.monetization_on,
                                      size: 15, color: Colors.green),
                                  const SizedBox(width: 4),
                                  Text(
                                    "C\$ ${patrimony.toStringAsFixed(2)}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              _buildVariationBadge(variation),
                            ],
                          ),
                        ),

                        // Pontuação daquela rodada
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "Pontos",
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: scoreColor,
                              ),
                            ),
                            Text(
                              points.toStringAsFixed(2),
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: scoreColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  /// Badge de Variação da Rodada (Cartoletas)
  Widget _buildVariationBadge(double variation) {
    final bool isPositive = variation > 0;
    final bool isZero = variation == 0;
    final Color badgeColor = isPositive
        ? Colors.green[700]!
        : (isZero ? Colors.grey[600]! : Colors.red[700]!);
    final Color bgColor = isPositive
        ? Colors.green[50]!
        : (isZero ? Colors.grey[100]! : Colors.red[50]!);
    final IconData icon = isPositive
        ? Icons.trending_up
        : (isZero ? Icons.trending_flat : Icons.trending_down);
    final String text = isPositive
        ? "+C\$ ${variation.toStringAsFixed(2)}"
        : (isZero ? "C\$ 0.00" : "-C\$ ${variation.abs().toStringAsFixed(2)}");

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: badgeColor.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: badgeColor),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: badgeColor,
            ),
          ),
        ],
      ),
    );
  }

  /// Card de Resumo de Evolução Geral no Topo
  Widget _buildSummaryHeader({
    required double currentPatrimony,
    required double totalVariation,
    required double totalPoints,
    required double avgPoints,
    required int roundsCount,
  }) {
    final bool isPositive = totalVariation >= 0;
    final String varSign = isPositive ? "+" : "";

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.green[900]!,
            Colors.green[700]!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Evolução na Temporada",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "$roundsCount ${roundsCount == 1 ? 'rodada disputada' : 'rodadas disputadas'}",
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Patrimônio Atual
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Patrimônio Atual",
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "C\$ ${currentPatrimony.toStringAsFixed(2)}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "$varSign C\$ ${totalVariation.toStringAsFixed(2)} desde o início",
                      style: TextStyle(
                        color: isPositive ? Colors.lightGreenAccent : Colors.orangeAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 40,
                width: 1,
                color: Colors.white24,
              ),
              const SizedBox(width: 16),
              // Pontuação Geral
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Pontuação Total",
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "${totalPoints.toStringAsFixed(2)} pts",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Média: ${avgPoints.toStringAsFixed(2)} pts/rodada",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

