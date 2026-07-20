import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../viewmodels/mini_bolao_home_viewmodel.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_theme.dart';

// ==========================================================
// 🚨 TELA EM TELA CHEIA (FULL SCREEN) PARA O RANKING
// ==========================================================

class MiniBolaoRankingScreen extends StatefulWidget {
  final String leagueId;
  final Map<String, dynamic> leagueData;
  final String currentUserId;

  const MiniBolaoRankingScreen({super.key, required this.leagueId, required this.leagueData, required this.currentUserId});

  @override
  State<MiniBolaoRankingScreen> createState() => _MiniBolaoRankingScreenState();
}

class _MiniBolaoRankingScreenState extends State<MiniBolaoRankingScreen> {
  final MiniBolaoHomeViewModel _viewModel = MiniBolaoHomeViewModel();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    // 🚨 Analytics: Rastreia a visualização do ranking detalhado
    AnalyticsService.logCustomScreenView('Mini_Bolao_Ranking_Screen', parameters: {'mini_bolao_id': widget.leagueId});
  }

  Widget _buildOfficialRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.bold))),
          Expanded(flex: 3, child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.black87), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _buildPredictionRow(IconData icon, String label, String prediction, String points, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(prediction, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3))),
            child: Text(points, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prizePool = widget.leagueData['prize_pool'] ?? 0.0;
    final adminFeePct = widget.leagueData['admin_fee_percentage'] ?? 30.0;
    final double netPrize = prizePool * (1 - (adminFeePct / 100));

    final int realHome = widget.leagueData['real_score_home'] ?? 0;
    final int realAway = widget.leagueData['real_score_away'] ?? 0;
    final List<String> realScorers = List<String>.from(widget.leagueData['real_scorers'] ?? []);
    final String realFirstGoal = widget.leagueData['real_first_goal_team'] ?? '-';
    // 🚨 MINUTO NO GABARITO OFICIAL
    final int realFirstGoalMinute = widget.leagueData['real_first_goal_minute'] ?? 0;
    final bool realHalfTimeDraw = widget.leagueData['real_half_time_draw'] ?? false;
    final String realHighestScoringHalf = widget.leagueData['real_highest_scoring_half'] ?? '-';

    final bool isFinished = widget.leagueData['status'] == 'finished';
    final String appBarTitle = isFinished ? "Ranking Oficial" : "Ranking Ao Vivo";
    final String gabaritoTitle = isFinished ? "GABARITO DA SALA (OFICIAL)" : "GABARITO DA SALA (AO VIVO)";

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(appBarTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.brazilGradient)),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: Column(
              children: [
                const Icon(Icons.emoji_events, color: Colors.amber, size: 60),
                const SizedBox(height: 8),
                Text(widget.leagueData['title'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                  child: Text("PRÊMIO: R\$ ${netPrize.toStringAsFixed(2)}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.amber)),
                )
              ],
            ),
          ),
          
          Card(
            margin: const EdgeInsets.all(16),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(isFinished ? Icons.check_circle : Icons.sensors, color: isFinished ? Colors.green : Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Text(gabaritoTitle, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF1B5E20))),
                    ],
                  ),
                  const Divider(),
                  _buildOfficialRow("Placar da Partida:", "$realHome x $realAway"),
                  _buildOfficialRow("Artilheiros do Jogo:", realScorers.isEmpty ? "Nenhum" : realScorers.join(', ')),
                  _buildOfficialRow("Primeiro Gol:", realFirstGoal),
                  _buildOfficialRow("Minuto do 1º Gol:", "$realFirstGoalMinute'"),
                  _buildOfficialRow("Empate no Intervalo:", realHalfTimeDraw ? "Sim" : "Não"),
                  _buildOfficialRow("Metade c/ Mais Gols:", realHighestScoringHalf),
                ]
              )
            )
          ),

          Expanded(
            child: FutureBuilder<QuerySnapshot>(
              future: _viewModel.getLeagueParticipants(widget.leagueId),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFF1B5E20)));
                if (!snap.hasData || snap.data!.docs.isEmpty) return const Center(child: Text("Ninguém pontuou nesta sala."));

                // 🚨 NOVA LÓGICA DE ORDENAÇÃO: 1º Pontos, 2º Diferença do Minuto do Gol
                final docs = snap.data!.docs.toList();
                docs.sort((a, b) {
                  final dataA = a.data() as Map<String, dynamic>;
                  final dataB = b.data() as Map<String, dynamic>;
                  
                  final ptsA = dataA['points'] ?? 0;
                  final ptsB = dataB['points'] ?? 0;
                  
                  if (ptsA != ptsB) return ptsB.compareTo(ptsA); // Maior ponto sobe
                  
                  final diffA = dataA['first_goal_minute_diff'] ?? 999;
                  final diffB = dataB['first_goal_minute_diff'] ?? 999;
                  
                  return diffA.compareTo(diffB); // Menor diferença sobe (Quem chegou mais perto)
                });

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: docs.length,
                  itemBuilder: (ctx, index) {
                    final partDoc = docs[index];
                    final pData = partDoc.data() as Map<String, dynamic>;
                    final bool isMe = partDoc.id == widget.currentUserId;

                    final int totalPts = pData['points'] ?? 0;
                    final int scorersPts = pData['breakdown_scorers'] ?? 0;
                    final int firstGoalPts = pData['breakdown_first_goal'] ?? 0;
                    
                    bool hitHalfTime = pData['pred_half_time_draw'] == realHalfTimeDraw;
                    int halfTimePts = hitHalfTime && pData.containsKey('pred_half_time_draw') ? 1 : 0;
                    
                    bool hitHighestHalf = pData['pred_highest_scoring_half'] == realHighestScoringHalf;
                    int highestHalfPts = hitHighestHalf && pData.containsKey('pred_highest_scoring_half') ? 1 : 0;

                    final int scorePts = totalPts - (scorersPts + firstGoalPts + halfTimePts + highestHalfPts);

                    final int minuteDiff = pData['first_goal_minute_diff'] ?? 999;

                    Color medalColor; Color bgColor;
                    if (index == 0) { medalColor = Colors.amber.shade600; bgColor = Colors.amber.shade50; } 
                    else if (index == 1) { medalColor = Colors.grey.shade600; bgColor = Colors.grey.shade100; } 
                    else if (index == 2) { medalColor = Colors.brown.shade400; bgColor = Colors.brown.shade50; } 
                    else { medalColor = Colors.blueGrey.shade400; bgColor = Colors.white; }

                    if (isMe) bgColor = Colors.green.shade50; 

                    return FutureBuilder<DocumentSnapshot>(
                      future: _viewModel.getUser(partDoc.id),
                      builder: (ctx, userSnap) {
                        if (!userSnap.hasData || !userSnap.data!.exists) {
                           return const Padding(
                             padding: EdgeInsets.all(8.0),
                             child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey))),
                           );
                        }

                        final uData = userSnap.data!.data() as Map<String, dynamic>;
                        final String name = uData['name'] ?? "Desconhecido";
                        final String? photo = uData['photo_url'];

                        return Card(
                          elevation: isMe ? 4 : 1,
                          margin: const EdgeInsets.only(bottom: 12),
                          color: bgColor,
                          shape: RoundedRectangleBorder(
                            side: isMe ? const BorderSide(color: Color(0xFF1B5E20), width: 2) : BorderSide(color: Colors.grey.shade300), 
                            borderRadius: BorderRadius.circular(16)
                          ),
                          child: ExpansionTile(
                            leading: CircleAvatar(
                              radius: 22, backgroundColor: Colors.grey.shade300,
                              backgroundImage: photo != null ? NetworkImage(photo) : null, 
                              child: photo == null ? const Icon(Icons.person, color: Colors.grey) : null
                            ),
                            title: Row(
                              children: [
                                Text("${index + 1}º ", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: medalColor)),
                                Expanded(child: Text(name, style: TextStyle(fontWeight: isMe ? FontWeight.w900 : FontWeight.bold, fontSize: 14))),
                              ],
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(color: isMe ? const Color(0xFF1B5E20) : medalColor, borderRadius: BorderRadius.circular(12)),
                              child: Text("$totalPts pts", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.white)),
                            ),
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)), border: Border(top: BorderSide(color: Colors.grey.shade200))),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildPredictionRow(Icons.sports_score, "Placar Exato", "${pData['pred_score_home'] ?? '-'} x ${pData['pred_score_away'] ?? '-'}", "+$scorePts pts", Colors.blue.shade700),
                                    const Divider(height: 16),
                                    _buildPredictionRow(Icons.star, "O Craque do Jogo", (pData['pred_goal_scorers'] as List?)?.join(', ') ?? 'Nenhum', "+$scorersPts pts", Colors.orange.shade800),
                                    const Divider(height: 16),
                                    _buildPredictionRow(Icons.bolt, "Primeiro Gol", pData['pred_first_goal_team'] ?? '-', "+$firstGoalPts pts", Colors.amber.shade900),
                                    const Divider(height: 16),
                                    // 🚨 EXIBIÇÃO DA LÓGICA DE DESEMPATE NO APP
                                    _buildPredictionRow(Icons.timer, "Minuto do 1º Gol (Desempate)", "Palpite: ${pData['pred_first_goal_minute'] ?? 0}' (Erro: $minuteDiff min)", "-", Colors.cyan.shade700),
                                    const Divider(height: 16),
                                    _buildPredictionRow(Icons.timelapse, "Empate no Intervalo", pData['pred_half_time_draw'] == true ? 'Sim' : 'Não', "+$halfTimePts pts", Colors.teal.shade700),
                                    const Divider(height: 16),
                                    _buildPredictionRow(Icons.balance, "Metade c/ Mais Gols", pData['pred_highest_scoring_half'] ?? '-', "+$highestHalfPts pts", Colors.indigo.shade700),
                                  ],
                                ),
                              )
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              }
            ),
          ),
        ],
      ),
    );
  }
}

