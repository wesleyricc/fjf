import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../theme/app_theme.dart'; // <-- NOVO: Import do Tema
import '../services/team_service.dart';
import '../services/championship_service.dart';
import '../services/auth_service.dart';
import '../models/team_model.dart'; 

import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/ui/shimmer_effect.dart';     
import '../widgets/ui/custom_empty_state.dart';  
import 'team_detail_screen.dart';
import 'edit_team_screen.dart';

class TeamsListScreen extends StatefulWidget {
  const TeamsListScreen({super.key});

  @override
  State<TeamsListScreen> createState() => _TeamsListScreenState();
}

class _TeamsListScreenState extends State<TeamsListScreen> {
  
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
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            // 🚨 NOVO: Gradiente da Copa aplicado
            flexibleSpace: Container(
              decoration: const BoxDecoration(
                gradient: AppTheme.brazilGradient,
              ),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Equipes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
          body: _buildBody(context, teams, isLoading, champService, authService.isAuthenticated, seasonId),
          bottomNavigationBar: const SponsorBannerRotator(),
          floatingActionButton: authService.isAuthenticated
              ? FloatingActionButton.extended(
                  onPressed: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const EditTeamScreen(team: null)));
                    if (context.mounted) {
                      champService.fetchStaticData(forceRefresh: true);
                    }
                  },
                  backgroundColor: Theme.of(context).primaryColor,
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text("Nova Equipe", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                )
              : null,
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, List<Team> teams, bool isLoading, ChampionshipService service, bool isAdmin, String seasonId) {
    if (service.isOffline && teams.isEmpty) {
      return CustomEmptyState.offline(
        onRetry: () => service.fetchStaticData(forceRefresh: true),
      );
    }

    if (isLoading && teams.isEmpty) {
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, 
          crossAxisSpacing: 16, 
          mainAxisSpacing: 16, 
          childAspectRatio: 0.85
        ),
        itemCount: 8,
        itemBuilder: (context, index) => _buildSkeletonCard(),
      );
    }

    if (teams.isEmpty) {
      return CustomEmptyState(
        icon: Icons.shield_outlined,
        title: "Nenhuma equipe",
        message: "As equipes desta temporada ainda estão sendo cadastradas.",
        buttonText: "Tentar Novamente",
        onButtonPressed: () => service.fetchStaticData(forceRefresh: true),
      );
    }

    return RefreshIndicator(
      onRefresh: () => service.fetchStaticData(forceRefresh: true),
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, 
          crossAxisSpacing: 16, 
          mainAxisSpacing: 16, 
          childAspectRatio: 0.85 
        ),
        itemCount: teams.length,
        itemBuilder: (context, index) {
          final team = teams[index];
          return _buildTeamGridCard(context, team, seasonId, isAdmin);
        },
      ),
    );
  }

  Widget _buildTeamGridCard(BuildContext context, Team team, String seasonId, bool isAdmin) {
    final String heroTag = 'team_shield_${team.id}';

    return Card(
      elevation: 3,
      shadowColor: Colors.black.withOpacity(0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias, 
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TeamDetailScreen(team: team, heroTag: heroTag))),
        child: Stack(
          children: [
            Positioned.fill(
              bottom: 50, 
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Hero(
                  tag: heroTag,
                  child: team.shieldUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: team.shieldUrl,
                          fit: BoxFit.contain,
                          memCacheHeight: 300, 
                          memCacheWidth: 300,
                          placeholder: (_, __) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          errorWidget: (_, __, ___) => const Icon(Icons.shield, size: 60, color: Colors.grey),
                        )
                      : const Icon(Icons.shield, size: 60, color: Colors.grey),
                ),
              ),
            ),

            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey.shade100)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      team.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                      maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                    ),
                    if (team.shortName.isNotEmpty)
                      Text(
                        team.shortName,
                        style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.w600),
                        maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                      ),
                  ],
                ),
              ),
            ),

            if (isAdmin)
              Positioned(
                top: 0, right: 0,
                child: PopupMenuButton<String>(
                  icon: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.8), shape: BoxShape.circle),
                    child: const Icon(Icons.more_vert, color: Colors.black87, size: 20),
                  ),
                  onSelected: (val) {
                    if (val == 'edit') _handleEdit(context, team, seasonId);
                    if (val == 'delete') _handleDelete(context, team, seasonId);
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, color: Colors.blue, size: 20), SizedBox(width: 8), Text('Editar')])),
                    const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, color: Colors.red, size: 20), SizedBox(width: 8), Text('Excluir')])),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200)
      ),
      child: Column(
        children: [
          const Expanded(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: ShimmerEffect.circular(size: double.infinity), 
            )
          ),
          Container(
            height: 50, 
            padding: const EdgeInsets.all(12),
            child: const ShimmerEffect.rectangular(height: 14, width: double.infinity)
          ),
        ],
      ),
    );
  }
}