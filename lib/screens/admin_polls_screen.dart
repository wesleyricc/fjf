import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../services/championship_service.dart';
import '../models/poll_model.dart';
import 'admin_edit_poll_screen.dart';
import 'admin_poll_results_screen.dart';

class AdminPollsScreen extends StatelessWidget {
  const AdminPollsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciar Votações'),
      ),
      body: seasonId.isEmpty
          ? const Center(child: Text("Nenhuma temporada selecionada."))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('championships')
                  .doc(seasonId)
                  .collection('polls')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('Nenhuma votação criada.'));
                }

                final polls = snapshot.data!.docs.map((doc) => Poll.fromFirestore(doc)).toList();

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: polls.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final poll = polls[index];
                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: Icon(
                          poll.isActive ? Icons.how_to_vote : Icons.lock_clock,
                          color: poll.isActive ? Colors.green : Colors.grey,
                          size: 32,
                        ),
                        title: Text(poll.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("Categoria: ${poll.category}"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.bar_chart, color: Colors.indigo),
                              tooltip: 'Ver Resultados',
                              onPressed: () {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => AdminPollResultsScreen(poll: poll)));
                              },
                            ),
                            const Icon(Icons.arrow_forward_ios, size: 16),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => AdminEditPollScreen(poll: poll)));
                        },
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminEditPollScreen(poll: null)));
        },
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Nova Votação', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).primaryColor,
      ),
    );
  }
}