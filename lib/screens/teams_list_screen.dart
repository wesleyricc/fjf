import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart'; // <-- Importante
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import 'team_detail_screen.dart';
import 'edit_team_screen.dart';
import '../services/firestore_service.dart';
import '../services/championship_service.dart';
import '../services/auth_service.dart'; // <-- Importante
import 'package:cached_network_image/cached_network_image.dart';

class TeamsListScreen extends StatelessWidget {
  const TeamsListScreen({super.key});

  // --- DIÁLOGO DE EXCLUSÃO ---
  Future<void> _showDeleteTeamDialog(BuildContext context, DocumentSnapshot teamDoc, String seasonId) async {
     final teamName = (teamDoc.data() as Map<String, dynamic>?)?['name'] ?? 'Equipe';
     final confirm = await showDialog<bool>(
       context: context,
       builder: (ctx) => AlertDialog(
         title: Text('EXCLUIR $teamName?'),
         content: const Text('ATENÇÃO! Esta ação é permanente.\n\nExcluir esta equipe irá remover também:\n- Todos os jogadores desta equipe.\n- Todas as partidas desta equipe nesta temporada.\n\nDeseja continuar?'),
         actions: [
           TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
           TextButton(
             onPressed: () => Navigator.of(ctx).pop(true),
             child: const Text('Sim, Excluir', style: TextStyle(color: Colors.red)),
           ),
         ],
       ),
     );

     if (confirm == true && context.mounted) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Excluindo...')));
       final result = await FirestoreService().deleteTeam(teamDoc, seasonId);
       if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
     }
  }

  @override
  Widget build(BuildContext context) {
    final championshipService = Provider.of<ChampionshipService>(context);
    final authService = Provider.of<AuthService>(context); // <-- OUVINDO O LOGIN
    
    final String seasonId = championshipService.currentSeasonId;
    final String seasonName = championshipService.currentSeasonName;

    Query teamsQuery;
    if (seasonId == FirestoreService.LEGACY_ID) {
      teamsQuery = FirebaseFirestore.instance.collection('teams').orderBy('name');
    } else {
      teamsQuery = FirebaseFirestore.instance
          .collection('championships').doc(seasonId).collection('teams_participation').orderBy('name');
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Equipes', style: TextStyle(fontSize: 18)),
            Text(seasonName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w300)),
          ],
        ),
      ),
      drawer: const AppDrawer(),
      body: StreamBuilder<QuerySnapshot>(
        stream: teamsQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('Nenhuma equipe encontrada.'));

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
                    final data = teamDoc.data() as Map<String, dynamic>;
                    final shieldUrl = data['shield_url'] ?? '';

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                      child: ListTile(
                        leading: SizedBox(
                          width: 40, height: 40,
                          child: CachedNetworkImage(
                            imageUrl: shieldUrl,
                            placeholder: (c, u) => const Center(child: Icon(Icons.shield, size: 30, color: Colors.grey)),
                            errorWidget: (c, u, e) => const Icon(Icons.shield, size: 40, color: Colors.grey),
                            fit: BoxFit.contain,
                          ),
                        ),
                        title: Text(data['name'] ?? 'Nome Indisponível', style: const TextStyle(fontWeight: FontWeight.bold)),
                        
                        // --- AQUI ESTÁ A CORREÇÃO ---
                        trailing: authService.isAuthenticated // Usa authService em vez de AdminService
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.edit, color: Theme.of(context).primaryColor),
                                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => EditTeamScreen(team: teamDoc))),
                                ),
                                IconButton(
                                  icon: Icon(Icons.delete_forever, color: Colors.red[700]),
                                  onPressed: () => _showDeleteTeamDialog(context, teamDoc, seasonId),
                                ),
                              ],
                            )
                          : const Icon(Icons.arrow_forward_ios, size: 16),
                        // ----------------------------
                        
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => TeamDetailScreen(teamDoc: teamDoc))),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: const SponsorBannerRotator(),
      
      // --- CORREÇÃO DO FAB ---
      floatingActionButton: authService.isAuthenticated
          ? FloatingActionButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const EditTeamScreen(team: null))),
              backgroundColor: Theme.of(context).primaryColor,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }
}