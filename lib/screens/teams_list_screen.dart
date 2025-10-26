// lib/screens/teams_list_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import 'team_detail_screen.dart';
import 'edit_team_screen.dart';
import '../services/admin_service.dart';
import '../services/firestore_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class TeamsListScreen extends StatelessWidget {
  const TeamsListScreen({super.key});

  // --- FUNÇÃO PARA DIÁLOGO DE EXCLUSÃO ---
  Future<void> _showDeleteTeamDialog(BuildContext context, DocumentSnapshot teamDoc) async {
     final teamName = (teamDoc.data() as Map<String, dynamic>?)?['name'] ?? 'Equipe';
     final confirm = await showDialog<bool>(
       context: context,
       builder: (ctx) => AlertDialog(
         title: Text('EXCLUIR $teamName?'),
         content: const Text('ATENÇÃO! Esta ação é permanente.\n\nExcluir esta equipe irá remover também:\n- Todos os jogadores desta equipe.\n- Todas as partidas (passadas e futuras) desta equipe.\n- A classificação dos oponentes será recalculada.\n\nDeseja continuar?'),
         actions: [
           TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
           TextButton(
             onPressed: () => Navigator.of(ctx).pop(true),
             child: const Text('Sim, Excluir', style: TextStyle(color: Colors.red)),
           ),
         ],
       ),
     );

     if (confirm == true) {
       // Mostra um loading antes de chamar a função pesada
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Excluindo equipe e dados... Isso pode levar um momento.')),
       );
       final result = await FirestoreService().deleteTeam(teamDoc); // Chama o serviço
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text(result)),
       );
     }
  }
  // --- FIM ---

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
                          // --- TRAILING DINÂMICO (ADMIN vs USER) ---
                          trailing: AdminService.isAdmin
                            ? Row( // Mostra botões para Admin
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.edit, color: Theme.of(context).primaryColor),
                                    tooltip: 'Editar Equipe',
                                    onPressed: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (ctx) => EditTeamScreen(team: teamDoc), // Modo Edição
                                        ),
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_forever, color: Colors.red[700]),
                                    tooltip: 'Excluir Equipe',
                                    onPressed: () {
                                      _showDeleteTeamDialog(context, teamDoc); // Chama diálogo de exclusão
                                    },
                                  ),
                                ],
                              )
                            : const Icon(Icons.arrow_forward_ios, size: 16), // Mostra seta para Usuário
                          // --- FIM TRAILING ---
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
      // --- FAB PARA CRIAR EQUIPE (SÓ ADMIN) ---
      floatingActionButton: AdminService.isAdmin
          ? FloatingActionButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (ctx) => const EditTeamScreen(team: null), // Modo Criação
                  ),
                );
              },
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              tooltip: 'Adicionar Nova Equipe',
              child: const Icon(Icons.add),
            )
          : null,
      // --- FIM FAB ---
    );
  }
}