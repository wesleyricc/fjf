import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import '../../services/analytics_service.dart';
import '../../screens/bolao/mini_bolao_ranking_screen.dart';

class MiniBolaoCard extends StatelessWidget {
  final String userId;
  final String leagueId;
  final Map<String, dynamic> leagueData;
  final Map<String, dynamic>? currentUserData;
  final bool profileComplete;
  
  final Function(String, String, double, Map<String, dynamic>?) onGeneratePix;
  final Function(Map<String, dynamic>?) onProfileRequired;
  final Function(BuildContext, String, Map<String, dynamic>, Map<String, dynamic>) onPredict;

  const MiniBolaoCard({
    super.key,
    required this.userId,
    required this.leagueId,
    required this.leagueData,
    required this.currentUserData,
    required this.profileComplete,
    required this.onGeneratePix,
    required this.onProfileRequired,
    required this.onPredict,
  });

  @override
  Widget build(BuildContext context) {
    final String title = leagueData['title'] ?? 'Liga';
    final double fee = (leagueData['entry_fee'] as num?)?.toDouble() ?? 10.0;
    final double prizePool = (leagueData['prize_pool'] as num?)?.toDouble() ?? 0.0;
    final double adminFeePct = (leagueData['admin_fee_percentage'] as num?)?.toDouble() ?? 30.0;
    
    final double netPrize = prizePool * (1 - (adminFeePct / 100));

    final Timestamp? deadlineTs = leagueData['deadline'] as Timestamp?;
    String deadlineText = "Prazo não definido";
    bool isDeadlinePassed = false;
    
    if (deadlineTs != null) {
      final dt = deadlineTs.toDate();
      deadlineText = "Encerra: ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} às ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
      isDeadlinePassed = DateTime.now().isAfter(dt);
    }

    final bool isFinished = leagueData['status'] == 'finished'; 
    final bool isLocked = isFinished || isDeadlinePassed;
    
    return StreamBuilder<DocumentSnapshot?>(
      stream: (userId.isNotEmpty)
          ? FirebaseFirestore.instance.collection('mini_bolao_leagues').doc(leagueId).collection('participants').doc(userId).snapshots()
          : Stream<DocumentSnapshot?>.value(null),
      builder: (ctx, partSnap) {
        final bool isParticipating = partSnap.hasData && partSnap.data != null && partSnap.data!.exists;
        final Map<String, dynamic> participantData = isParticipating ? (partSnap.data!.data() as Map<String, dynamic>? ?? <String, dynamic>{}) : <String, dynamic>{};
        final bool hasPredicted = participantData.containsKey('pred_score_home');

        return Card(
          elevation: 2, margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: isParticipating ? const Color(0xFF1B5E20) : Colors.transparent, width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: isFinished ? Colors.grey.shade200 : Colors.amber.shade100, shape: BoxShape.circle),
                      child: Icon(isFinished ? Icons.lock : Icons.workspace_premium, color: isFinished ? Colors.grey : Colors.amber.shade900),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20))),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.access_time, size: 12, color: isDeadlinePassed && !isFinished ? Colors.red : Colors.grey),
                              const SizedBox(width: 4),
                              Text(deadlineText, style: TextStyle(color: isDeadlinePassed && !isFinished ? Colors.red : Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!isFinished)
                      IconButton(
                        icon: const Icon(Icons.share, color: Colors.blue),
                        tooltip: "Convidar Amigos",
                        onPressed: () {
                          AnalyticsService.logShare('mini_bolao_invite', leagueId);
                          final shareText = "🔥 Palpite no mini bolão FJF '$title'! O prêmio já está em R\$ ${netPrize.toStringAsFixed(2)}. Acesse o app FJF, pague a taxa de inscrição e vem pro jogo! Acesse: https://acefjf.web.app";
                          Clipboard.setData(ClipboardData(text: shareText));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Texto copiado! Cole no WhatsApp e chame a galera.", style: TextStyle(color: Colors.white)), backgroundColor: Colors.green, duration: Duration(seconds: 3)));
                        },
                      )
                  ],
                ),
                const SizedBox(height: 16),
                
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
                  child: Column(
                    children: [
                      Text(isFinished ? "PRÊMIO FINAL" : "PRÊMIO ACUMULADO AO VIVO", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
                      Text("R\$ ${netPrize.toStringAsFixed(2)}", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.amber.shade700)),
                      const SizedBox(height: 4),
                      Text("Taxa de administração de ${adminFeePct.toStringAsFixed(0)}% inclusa", style: const TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (isParticipating && isFinished) ...[
                  SizedBox(
                    width: double.infinity, height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      icon: const Icon(Icons.emoji_events),
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => MiniBolaoRankingScreen(leagueId: leagueId, leagueData: leagueData, currentUserId: userId)));
                      },
                      label: const Text("🏆 VER RANKING FINAL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  )
                ] else if (isParticipating && isLocked) ...[
                  SizedBox(
                    width: double.infinity, height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      icon: const Icon(Icons.sensors),
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => MiniBolaoRankingScreen(leagueId: leagueId, leagueData: leagueData, currentUserId: userId)));
                      },
                      label: const Text("📊 ACOMPANHAR AO VIVO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  )
                ] else if (isParticipating && !isLocked) ...[
                  SizedBox(
                    width: double.infinity, height: 50,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1B5E20), side: const BorderSide(color: Color(0xFF1B5E20)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      icon: Icon(hasPredicted ? Icons.edit : Icons.ads_click),
                      onPressed: () => onPredict(context, leagueId, leagueData, participantData),
                      label: Text(hasPredicted ? "EDITAR MEUS PALPITES" : "FAZER PALPITES", style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  )
                ] else if (!isParticipating && !isLocked) ...[
                  SizedBox(
                    width: double.infinity, height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E20), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      icon: const Icon(Icons.pix),
                      label: Text("ENTRAR (R\$ ${fee.toStringAsFixed(2)})", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      onPressed: () {
                        if (!profileComplete) onProfileRequired(currentUserData);
                        else onGeneratePix(leagueId, title, fee, currentUserData);
                      },
                    ),
                  )
                ] else ...[
                  Container(
                    width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
                    child: Center(
                      child: Text(
                        isFinished ? "SALA ENCERRADA" : "SALA FECHADA PARA INSCRIÇÕES", 
                        style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)
                      )
                    ),
                  )
                ]
              ],
            ),
          ),
        );
      }
    );
  }
}
