import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Services & Models
import '../services/championship_service.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../models/player_model.dart'; 

// Screens
import '../screens/player_profile_screen.dart';
import '../screens/edit_player_screen.dart';
import '../utils/custom_cache_manager.dart';

class TeamRosterList extends StatelessWidget {
  final String teamId;
  final String teamName;

  const TeamRosterList({super.key, required this.teamId, required this.teamName});

  @override
  Widget build(BuildContext context) {
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    final authService = Provider.of<AuthService>(context);
    final firestoreService = FirestoreService();

    return StreamBuilder<List<Player>>(
      stream: firestoreService.streamPlayers(seasonId, teamId: teamId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
        }
        
        final allMembers = snapshot.data ?? [];
        if (allMembers.isEmpty) {
          return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Nenhum membro ativo.')));
        }

        final players = allMembers.where((p) => !p.isStaff).toList();
        final staff = allMembers.where((p) => p.isStaff).toList();

        // Ordenação: Goleiros primeiro, depois por número da camisa
        players.sort((a, b) {
          if (a.isGoalkeeper && !b.isGoalkeeper) return -1;
          if (!a.isGoalkeeper && b.isGoalkeeper) return 1;
          final na = a.jerseyNumber ?? 999;
          final nb = b.jerseyNumber ?? 999;
          return na.compareTo(nb);
        });

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- GRID DE JOGADORES (2 Colunas) ---
            _buildSectionTitle(context, 'Elenco (${players.length})'),
            if (players.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('Sem jogadores.'))
            else
              GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, 
                  childAspectRatio: 0.70, // Ajustado para ficar proporcional com a linha única
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: players.length,
                itemBuilder: (context, index) {
                  return _MemberCard(
                    member: players[index],
                    teamId: teamId,
                    teamName: teamName,
                    isAdmin: authService.isAuthenticated,
                    onDelete: () => _showDeletePlayerDialog(context, players[index], seasonId),
                  );
                },
              ),

            // --- LISTA DE COMISSÃO TÉCNICA (Vertical) ---
            if (staff.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildSectionTitle(context, 'Comissão Técnica'),
              ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: staff.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: SizedBox(
                      height: 260, // Altura fixa para manter a proporção
                      child: _MemberCard(
                        member: staff[index],
                        teamId: teamId,
                        teamName: teamName,
                        isAdmin: authService.isAuthenticated,
                        onDelete: () => _showDeletePlayerDialog(context, staff[index], seasonId),
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
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

  Future<void> _showDeletePlayerDialog(BuildContext context, Player player, String seasonId) async {
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
        // ALTERAÇÃO: Referência padronizada para a subcoleção da temporada
        // Removemos a verificação de LEGACY_ID
        final ref = FirebaseFirestore.instance
            .collection('championships')
            .doc(seasonId)
            .collection('player_stats')
            .doc(player.id);
        
        final snap = await ref.get();
        if (snap.exists) {
          final result = await FirestoreService().deletePlayer(snap, seasonId);
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
        }
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erro: $e")));
      }
    }
  }
}

// --- WIDGET UNIFICADO: CARD DE MEMBRO ---
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

    return Card(
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
                // 1. FOTO
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
                          placeholder: (c, u) => Center(child: Icon(isStaff ? Icons.assignment_ind : Icons.person, size: 50, color: Colors.grey.shade400)),
                          errorWidget: (c, u, e) => Center(child: Icon(isStaff ? Icons.assignment_ind : Icons.person, size: 50, color: Colors.grey.shade400)),
                        )
                      else
                        Center(child: Icon(isStaff ? Icons.assignment_ind : Icons.person, size: 80, color: Colors.grey.shade400)),

                      if (!isStaff && member.jerseyNumber != null)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: isGoalkeeper ? Colors.black87 : primaryColor,
                              shape: BoxShape.circle,
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                            ),
                            child: Text(
                              '${member.jerseyNumber}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // 2. DADOS E ESTATÍSTICAS
                Container(
                  padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
                  color: Colors.white,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        member.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, height: 1.1),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        isStaff 
                            ? (member.staffRole ?? 'Comissão')
                            : (isGoalkeeper ? 'Goleiro' : (member.position ?? 'Atleta')),
                        style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      
                      // 3. BARRA DE ESTATÍSTICAS (Compacta)
                      FittedBox( // Garante que cabe numa linha
                        fit: BoxFit.scaleDown,
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 3, // Espaçamento reduzido
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

            // 4. MENU ADMIN
            if (isAdmin)
              Positioned(
                top: 0,
                right: 0,
                child: PopupMenuButton<String>(
                  icon: const CircleAvatar(backgroundColor: Colors.white70, radius: 12, child: Icon(Icons.more_vert, size: 16, color: Colors.black)),
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
    );
  }
}

// --- WIDGET AUXILIAR: BADGE DE ESTATÍSTICA (Versão Compacta) ---
class _StatIcon extends StatelessWidget {
  final IconData icon;
  final int value;
  final Color color;
  final String tooltip;

  const _StatIcon(this.icon, this.value, this.color, this.tooltip);

  @override
  Widget build(BuildContext context) {
    // SEMPRE usa a cor oficial, mesmo se for zero.
    // Fundo sutil para não poluir
    final Color bgColor = color.withOpacity(0.08); 
    final Color borderColor = color.withOpacity(0.2);

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: borderColor, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 10, color: color), // Ícone um pouco menor
            const SizedBox(width: 2),
            Text(
              '$value',
              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: color), // Texto menor
            ),
          ],
        ),
      ),
    );
  }
}