// lib/screens/extra_points_log_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // Para formatar data

class ExtraPointsLogScreen extends StatelessWidget {
  final String teamId;
  final String teamName;

  const ExtraPointsLogScreen({
    super.key,
    required this.teamId,
    required this.teamName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Histórico - $teamName'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Busca na subcoleção, ordenado pelo mais recente primeiro
        stream: FirebaseFirestore.instance
            .collection('teams')
            .doc(teamId)
            .collection('extra_points_log')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Nenhum registro de pontos extras encontrado.'));
          }

          final logs = snapshot.data!.docs;

          return ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final logDoc = logs[index];
              try {
                final data = logDoc.data() as Map<String, dynamic>;
                final points = data['points'] ?? 0;
                final reason = data['reason'] ?? 'Motivo desconhecido';
                String formattedDate = 'Data indisponível';
                if (data['timestamp'] != null) {
                  formattedDate = DateFormat('dd/MM/yyyy HH:mm').format((data['timestamp'] as Timestamp).toDate());
                }

                return ListTile(
                  leading: Icon(
                    points > 0 ? Icons.add_circle : Icons.remove_circle,
                    color: points > 0 ? Colors.green : Colors.red,
                  ),
                  title: Text(reason),
                  subtitle: Text(formattedDate),
                  trailing: Text(
                    '${points > 0 ? '+' : ''}$points Pts',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: points > 0 ? Colors.green : Colors.red,
                    ),
                  ),
                );
              } catch (e) { return ListTile(title: Text('Erro registro ${logDoc.id}')); }
            },
          );
        },
      ),
    );
  }
}