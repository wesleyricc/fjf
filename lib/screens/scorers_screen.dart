// lib/screens/scorers_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';

class ScorersScreen extends StatelessWidget {
  const ScorersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Artilharia'),
      ),
      drawer: const AppDrawer(),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('players')
            .where('goals', isGreaterThan: 0) // Só mostra quem tem gol
            .orderBy('goals', descending: true)
            .limit(20) // Top 20
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Nenhum artilheiro ainda.'));
          }

          final players = snapshot.data!.docs;

          return ListView.builder(
            itemCount: players.length,
            itemBuilder: (context, index) {
              final player = players[index];
              final data = player.data() as Map<String, dynamic>;
              final rank = index + 1;

              return ListTile(
                leading: CircleAvatar(
                  child: Text(rank.toString()),
                ),
                title: Text(data['name']),
                subtitle: Text(data['team_name']), // Usando o dado denormalizado
                trailing: Text(
                  data['goals'].toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
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