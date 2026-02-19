import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/team_service.dart';
import '../services/championship_service.dart';
import '../services/auth_service.dart';
import '../models/team_model.dart'; 

import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/ui/shimmer_effect.dart';     // <-- NOVO
import '../widgets/ui/custom_empty_state.dart';  // <-- NOVO
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
        final bool isLoading = champService.isLoading;

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
          body: _buildBody(context, teams, isLoading, champService),
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

  Widget _buildBody(BuildContext context, List<Team> teams, bool isLoading, ChampionshipService service) {
    // 1. Estado de Loading com Shimmer (Melhor que spinner)
    if (isLoading && teams.isEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: 8, // Simula 8 itens
        itemBuilder: (context, index) => _buildSkeletonItem(),
      );
    }

    // 2. Estado Vazio (Bonito)
    if (teams.isEmpty) {
      return CustomEmptyState(
        icon: Icons.groups_outlined,
        title: "Nenhuma equipe",
        message: "Não encontramos equipes cadastradas nesta temporada ainda.",
        buttonText: "Tentar Novamente",
        onButtonPressed: () => service.fetchStaticData(forceRefresh: true),
      );
    }

    // 3. Lista Real
    return RefreshIndicator(
      onRefresh: () => service.fetchStaticData(forceRefresh: true),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 80, top: 8),
        itemCount: teams.length,
        itemBuilder: (context, index) {
          final team = teams[index];
          return _buildTeamCard(context, team, service.currentSeasonId);
        },
      ),
    );
  }

  // --- COMPONENTES VISUAIS ---

  Widget _buildSkeletonItem() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            const ShimmerEffect.circular(size: 40), // Avatar
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  ShimmerEffect.rectangular(height: 16, width: 150), // Título
                  SizedBox(height: 8),
                  ShimmerEffect.rectangular(height: 12, width: 100), // Subtítulo
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamCard(BuildContext context, Team team, String seasonId) {
    final authService = Provider.of<AuthService>(context, listen: false);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => TeamDetailScreen(team: team))),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: [
              // Logo com Hero Animation
              Hero(
                tag: 'team_shield_${team.id}',
                child: SizedBox(
                  width: 50, height: 50,
                  child: CachedNetworkImage(
                    imageUrl: team.shieldUrl,
                    placeholder: (_,__) => Container(color: Colors.grey[100], child: const Icon(Icons.shield, color: Colors.grey)),
                    errorWidget: (_,__,___) => const Icon(Icons.shield, size: 40, color: Colors.grey),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              
              // Textos
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      team.name, 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)
                    ),
                    if (team.shortName.isNotEmpty)
                      Text(
                        team.shortName, 
                        style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500)
                      ),
                  ],
                ),
              ),
              
              // Ações ou Seta
              if (authService.isAuthenticated)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20, color: Colors.blue), 
                      onPressed: () => _handleEdit(context, team, seasonId)
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red), 
                      onPressed: () => _handleDelete(context, team, seasonId)
                    ),
                  ],
                )
              else
                Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}