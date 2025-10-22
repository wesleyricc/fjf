// lib/screens/man_of_the_match_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';

class ManOfTheMatchScreen extends StatelessWidget {
  const ManOfTheMatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Craque do Jogo (Ranking)'),
      ),
      drawer: const AppDrawer(),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('players')
            .where('man_of_the_match_awards', isGreaterThan: 0) // Só quem já foi craque
            .orderBy('man_of_the_match_awards', descending: true) // Mais vezes primeiro
            .limit(20)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Ranking de Craque do Jogo vazio.'));
          }

          final players = snapshot.data!.docs;

          return ListView.builder(
            itemCount: players.length,
            itemBuilder: (context, index) {
              final player = players[index];
              final data = player.data() as Map<String, dynamic>;
              final rank = index + 1;

              return ListTile(
                leading: CircleAvatar(child: Text(rank.toString())),
                title: Text(data['name']),
                subtitle: Text(data['team_name']),
                trailing: Text(
                  '${data['man_of_the_match_awards'] ?? 0} vezes',
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