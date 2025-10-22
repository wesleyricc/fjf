// lib/screens/least_conceded_gk_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';

class LeastConcededGkScreen extends StatelessWidget {
  const LeastConcededGkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Goleiro Menos Vazado'),
      ),
      drawer: const AppDrawer(),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('players')
            .where('is_goalkeeper', isEqualTo: true) // Filtra só goleiros
            .where('goals_conceded', isGreaterThanOrEqualTo: 0) // Garante que o campo existe
            .orderBy('goals_conceded', descending: false) // Menos gols primeiro
            // Adicionar mais critérios se necessário (ex: orderBy('name'))
            .limit(20)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Nenhum goleiro encontrado.'));
          }

          final goalkeepers = snapshot.data!.docs;

          return ListView.builder(
            itemCount: goalkeepers.length,
            itemBuilder: (context, index) {
              final gk = goalkeepers[index];
              final data = gk.data() as Map<String, dynamic>;
              final rank = index + 1;

              return ListTile(
                leading: CircleAvatar(child: Text(rank.toString())),
                title: Text(data['name']),
                subtitle: Text(data['team_name']),
                trailing: Text(
                  '${data['goals_conceded'] ?? 0} GS', // Gols Sofridos
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              );
            },
          );
        },
      ),
    );
  }
}