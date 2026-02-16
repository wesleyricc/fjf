import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/championship_service.dart';
import '../services/player_service.dart'; // <-- NOVO SERVICE
import '../models/player_model.dart'; 

import '../screens/player_profile_screen.dart';
import '../screens/edit_player_screen.dart';
import '../utils/custom_cache_manager.dart';

class RosterSectionHeader extends StatelessWidget {
  final String title;
  const RosterSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Container(width: 4, height: 24, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class SliverTeamPlayersGrid extends StatelessWidget {
  final List<Player> players;
  final String teamId;
  final String teamName;
  final bool isAdmin;

  const SliverTeamPlayersGrid({
    super.key,
    required this.players,
    required this.teamId,
    required this.teamName,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context) {
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.70,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final p = players[index];
            return _MemberCard(
              member: p,
              teamId: teamId,
              teamName: teamName,
              isAdmin: isAdmin,
              onDelete: () => _deletePlayer(context, p, seasonId),
            );
          },
          childCount: players.length,
        ),
      ),
    );
  }
}

class SliverTeamStaffList extends StatelessWidget {
  final List<Player> staff;
  final String teamId;
  final String teamName;
  final bool isAdmin;

  const SliverTeamStaffList({
    super.key,
    required this.staff,
    required this.teamId,
    required this.teamName,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context) {
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    final bool usePlayerLayout = staff.length == 2;
    
    final int crossAxisCount = usePlayerLayout ? 2 : 3;
    final double childAspectRatio = usePlayerLayout ? 0.70 : 0.65;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: childAspectRatio,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            return _MemberCard(
              member: staff[index],
              teamId: teamId,
              teamName: teamName,
              isAdmin: isAdmin,
              onDelete: () => _deletePlayer(context, staff[index], seasonId),
            );
          },
          childCount: staff.length,
        ),
      ),
    );
  }
}

Future<void> _deletePlayer(BuildContext context, Player player, String seasonId) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Excluir ${player.name}?'),
      content: const Text('Isso marcará o membro como inativo nesta temporada.\n\nDeseja continuar?'),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Excluir', style: TextStyle(color: Colors.red))),
      ],
    ),
  );

  if (confirm == true && context.mounted) {
    try {
      final playerService = Provider.of<PlayerService>(context, listen: false);
      final ref = FirebaseFirestore.instance
          .collection('championships')
          .doc(seasonId)
          .collection('player_stats')
          .doc(player.id);
      
      final snap = await ref.get();
      if (snap.exists) {
        final result = await playerService.deletePlayer(snap, seasonId);
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
      }
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e")));
    }
  }
}

class _MemberCard extends StatelessWidget {
  final Player member;
  final String teamId;
  final String teamName;
  final bool isAdmin;
  final VoidCallback onDelete;

  const _MemberCard({
    required this.member,
    required this.teamId,
    required this.teamName,
    required this.isAdmin,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final bool isGoalkeeper = member.isGoalkeeper;
    final bool isStaff = member.isStaff;

    return RepaintBoundary(
      child: Card(
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerProfileScreen(playerId: member.id))),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.grey.shade300, Colors.white],
                            ),
                          ),
                        ),
                        if (member.photoUrl.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: member.photoUrl,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            cacheManager: PlayerCacheManager.instance,
                            memCacheWidth: 200, 
                            fadeInDuration: const Duration(milliseconds: 200),
                            placeholder: (c, u) => Center(child: Icon(isStaff ? Icons.assignment_ind : Icons.person, size: 40, color: Colors.grey.shade400)),
                            errorWidget: (c, u, e) => Center(child: Icon(isStaff ? Icons.assignment_ind : Icons.person, size: 40, color: Colors.grey.shade400)),
                          )
                        else
                          Center(child: Icon(isStaff ? Icons.assignment_ind : Icons.person, size: 60, color: Colors.grey.shade400)),

                        if (!isStaff && member.jerseyNumber != null)
                          Positioned(
                            top: 4,
                            left: 4,
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: isGoalkeeper ? Colors.black87 : primaryColor,
                                shape: BoxShape.circle,
                                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                              ),
                              child: Text(
                                '${member.jerseyNumber}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  Container(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
                    color: Colors.white,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          member.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, height: 1.1),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          isStaff 
                              ? (member.staffRole ?? 'Comissão')
                              : (isGoalkeeper ? 'Goleiro' : (member.position ?? 'Atleta')),
                          style: const TextStyle(fontSize: 9, color: Colors.grey, fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        
                        FittedBox( 
                          fit: BoxFit.scaleDown,
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 3,
                            runSpacing: 2,
                            children: [
                              if (!isStaff) ...[
                                _StatIcon(Icons.sports_soccer, member.goals, Colors.black, "Gols"),
                                _StatIcon(Icons.assistant, member.assists, Colors.blue, "Assistências"),
                                if (isGoalkeeper)
                                  _StatIcon(Icons.pan_tool_outlined, member.goalsConceded, Colors.blueGrey, "Gols Sofridos"),
                              ],
                              _StatIcon(Icons.style, member.totalYellowCards, Colors.amber.shade700, "Amarelos"),
                              _StatIcon(Icons.style, member.totalRedCards, Colors.red, "Vermelhos"),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              if (isAdmin)
                Positioned(
                  top: 0,
                  right: 0,
                  child: PopupMenuButton<String>(
                    icon: const CircleAvatar(backgroundColor: Colors.white70, radius: 10, child: Icon(Icons.more_vert, size: 14, color: Colors.black)),
                    padding: EdgeInsets.zero,
                    onSelected: (value) {
                      if (value == 'edit') {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => EditPlayerScreen(teamId: teamId, teamName: teamName, player: member)));
                      } else if (value == 'delete') {
                        onDelete();
                      }
                    },
                    itemBuilder: (BuildContext context) => [
                      const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, color: Colors.blue), SizedBox(width: 8), Text('Editar')])),
                      const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: Colors.red), SizedBox(width: 8), Text('Excluir')])),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatIcon extends StatelessWidget {
  final IconData icon;
  final int value;
  final Color color;
  final String tooltip;

  const _StatIcon(this.icon, this.value, this.color, this.tooltip);

  @override
  Widget build(BuildContext context) {
    final Color bgColor = color.withOpacity(0.08); 
    final Color borderColor = color.withOpacity(0.2);

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: borderColor, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 9, color: color), 
            const SizedBox(width: 2),
            Text('$value', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}