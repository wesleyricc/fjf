import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/team_service.dart'; // <-- NOVO SERVICE
import '../services/championship_service.dart';
import '../services/auth_service.dart';
import '../models/team_model.dart'; 

import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import 'team_detail_screen.dart';
import 'edit_team_screen.dart';

class TeamsListScreen extends StatelessWidget {
  const TeamsListScreen({super.key});

  Future<void> _handleDelete(BuildContext context, Team team, String seasonId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('EXCLUIR ${team.name}?'),
        content: const Text('ATENÇÃO! Esta ação é permanente e remove também os jogadores e estatísticas.\n\nDeseja continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      final teamService = Provider.of<TeamService>(context, listen: false);
      
      try {
        final docRef = FirebaseFirestore.instance
            .collection('championships')
            .doc(seasonId)
            .collection('teams_participation')
            .doc(team.id);
        
        final docSnap = await docRef.get();
        if (docSnap.exists) {
          final res = await teamService.deleteTeam(docSnap, seasonId);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res)));
            Provider.of<ChampionshipService>(context, listen: false).fetchStaticData(forceRefresh: true);
          }
        }
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro ao excluir: $e")));
      }
    }
  }

  Future<void> _handleEdit(BuildContext context, Team team, String seasonId) async {
    try {
      final docRef = FirebaseFirestore.instance
          .collection('championships')
          .doc(seasonId)
          .collection('teams_participation')
          .doc(team.id);
      
      final docSnap = await docRef.get();
      
      if (docSnap.exists && context.mounted) {
        final teamModel = Team.fromFirestore(docSnap);
        
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (ctx) => EditTeamScreen(team: teamModel))
        );
        if (context.mounted) {
          Provider.of<ChampionshipService>(context, listen: false).fetchStaticData(forceRefresh: true);
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    
    return Consumer<ChampionshipService>(
      builder: (context, champService, child) {
        final seasonName = champService.currentSeasonName;
        final seasonId = champService.currentSeasonId;
        final teams = champService.teams;

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Equipes', style: TextStyle(fontSize: 18)),
                Text(seasonName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w300)),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: "Atualizar Lista",
                onPressed: () => champService.fetchStaticData(forceRefresh: true),
              )
            ],
          ),
          drawer: const AppDrawer(),
          body: teams.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Nenhuma equipe encontrada.'),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: () => champService.fetchStaticData(forceRefresh: true),
                        child: const Text("Tentar Novamente"),
                      )
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => champService.fetchStaticData(forceRefresh: true),
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: teams.length,
                    itemBuilder: (context, index) {
                      final team = teams[index];

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                        child: ListTile(
                          leading: SizedBox(
                            width: 40, height: 40,
                            child: CachedNetworkImage(
                              imageUrl: team.shieldUrl,
                              placeholder: (_,__) => const Center(child: Icon(Icons.shield, size: 30, color: Colors.grey)),
                              errorWidget: (_,__,___) => const Icon(Icons.shield, size: 40, color: Colors.grey),
                              fit: BoxFit.contain,
                            ),
                          ),
                          title: Text(team.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          
                          trailing: authService.isAuthenticated
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(icon: Icon(Icons.edit, color: Theme.of(context).primaryColor), onPressed: () => _handleEdit(context, team, seasonId)),
                                  IconButton(icon: Icon(Icons.delete_forever, color: Colors.red[700]), onPressed: () => _handleDelete(context, team, seasonId)),
                                ],
                              )
                            : const Icon(Icons.arrow_forward_ios, size: 16),
                          
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => TeamDetailScreen(team: team))),
                        ),
                      );
                    },
                  ),
                ),
          bottomNavigationBar: const SponsorBannerRotator(),
          floatingActionButton: authService.isAuthenticated
              ? FloatingActionButton(
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const EditTeamScreen(team: null)));
                    if (context.mounted) {
                      champService.fetchStaticData(forceRefresh: true);
                    }
                  },
                  backgroundColor: Theme.of(context).primaryColor,
                  child: const Icon(Icons.add, color: Colors.white),
                )
              : null,
        );
      },
    );
  }
}