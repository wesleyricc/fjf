import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/fantasy_auth_service.dart';
import '../services/analytics_service.dart'; // 🚨 RASTREAMENTO

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

    if (userId == null) return const Scaffold(body: Center(child: Text("Erro de usuário")));

    return Scaffold(
      appBar: AppBar(
        title: const Text("Minha Evolução"),
        //backgroundColor: Colors.green[800],
        //foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Busca na sub-coleção history, ordenado por rodada (decrescente)
        stream: FirebaseFirestore.instance
            .collection('fantasy_teams')
            .doc(userId)
            .collection('history')
            .orderBy('round', descending: true)
            .snapshots(),
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
                  const Text("Nenhum histórico disponível.", style: TextStyle(color: Colors.grey)),
                  const Text("Participe das rodadas para ver sua evolução.", style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final int round = data['round'] ?? 0;
              final double points = (data['points'] ?? 0).toDouble();
              final double patrimony = (data['patrimony'] ?? 0).toDouble();

              // Definição de cores baseada na pontuação (Visual Feedback)
              Color scoreColor = Colors.grey;
              if (points >= 60) scoreColor = Colors.green[700]!; // Excelente
              else if (points >= 40) scoreColor = Colors.blue[700]!; // Bom
              else if (points >= 20) scoreColor = Colors.orange[700]!; // Regular
              else scoreColor = Colors.red[700]!; // Ruim

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                  child: Row(
                    children: [
                      // Círculo com a Rodada
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text("R", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                            Text("$round", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                          ],
                        ),
                      ),
                      
                      const SizedBox(width: 20),
                      
                      // Dados (Patrimônio)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Patrimônio", style: TextStyle(fontSize: 12, color: Colors.grey)),
                            Row(
                              children: [
                                const Icon(Icons.monetization_on, size: 14, color: Colors.green),
                                const SizedBox(width: 4),
                                Text(
                                  "C\$ ${patrimony.toStringAsFixed(2)}",
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Pontuação
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text("Pontos", style: TextStyle(fontSize: 12, color: scoreColor)),
                          Text(
                            points.toStringAsFixed(2),
                            style: TextStyle(
                              fontSize: 24, 
                              fontWeight: FontWeight.bold, 
                              color: scoreColor
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}