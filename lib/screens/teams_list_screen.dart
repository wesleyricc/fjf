// lib/screens/teams_list_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import 'team_detail_screen.dart'; // <-- Tela de detalhes que vamos criar
import 'package:cached_network_image/cached_network_image.dart';

class TeamsListScreen extends StatelessWidget {
  const TeamsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Equipes do Campeonato'),
      ),
      drawer: const AppDrawer(),
      body: StreamBuilder<QuerySnapshot>(
        // Busca todos os times, ordenados por nome
        stream: FirebaseFirestore.instance
            .collection('teams')
            .orderBy('name')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Nenhuma equipe encontrada.'));
          }

          final teams = snapshot.data!.docs;

          return SingleChildScrollView(
            child: Column(
              children: [
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: teams.length,
                  itemBuilder: (context, index) {
                    final teamDoc = teams[index];
                    try {
                      final data = teamDoc.data() as Map<String, dynamic>;
                      final shieldUrl = data['shield_url'] ?? '';

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                        child: ListTile(
                          leading: SizedBox( // Garante tamanho fixo
                            width: 40,
                            height: 40,
                            child: CachedNetworkImage(
                              imageUrl: shieldUrl, // shieldUrl já é pego acima
                              placeholder: (context, url) => const Center(child: Icon(Icons.shield, size: 30, color: Colors.grey)),
                              errorWidget: (context, url, error) => const Icon(Icons.shield, size: 40, color: Colors.grey),
                              fit: BoxFit.contain,
                            ),
                          ),
                          title: Text(data['name'] ?? 'Nome Indisponível', style: const TextStyle(fontWeight: FontWeight.bold)),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () {
                            // Navega para a tela de detalhes passando o documento do time
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (ctx) => TeamDetailScreen(teamDoc: teamDoc),
                              ),
                            );
                          },
                        ),
                      );
                    } catch (e) {
                      return ListTile(title: Text('Erro ao carregar time ${teamDoc.id}'));
                    }
                  },
                ), // Fim ListView
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: const SponsorBannerRotator(),
    );
  }
}