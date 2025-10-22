// lib/screens/assists_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';

class AssistsScreen extends StatelessWidget {
  const AssistsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistências'),
      ),
      drawer: const AppDrawer(),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('players')
            .where('assists', isGreaterThan: 0)
            .orderBy('assists', descending: true) // Apenas muda aqui
            .limit(20)
            .snapshots(),
        builder: (context, snapshot) {
          // ... (O resto do builder é idêntico ao ScorersScreen)
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Nenhum líder em assistências.'));
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
                subtitle: Text(data['team_name']),
                trailing: Text(
                  data['assists'].toString(), // E aqui
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