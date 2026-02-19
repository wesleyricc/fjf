import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import '../services/admin_service.dart';
import '../services/auth_service.dart';
import '../services/championship_service.dart';
import '../screens/player_profile_screen.dart';
import '../widgets/rank_highlight_card.dart';
import '../widgets/rank_indicator.dart'; 
import '../models/player_model.dart';
import '../widgets/ui/custom_empty_state.dart'; // <-- NOVO

class GenericPlayerRankList extends StatelessWidget {
  final List<Player> players;
  final String emptyMessage;
  final IconData? emptyIcon; // <-- NOVO
  final String? statField;
  final String? statLabel;
  final bool isStatusList;
  final bool isSuspendedTab;

  const GenericPlayerRankList({
    super.key,
    required this.players,
    required this.emptyMessage,
    this.emptyIcon,
    this.statField,
    this.statLabel,
    this.isStatusList = false,
    this.isSuspendedTab = false,
  });

  Future<void> _showClearSuspensionDialog(BuildContext context, Player player) async {
    // ... (Código do diálogo mantido igual ao original) ...
     final playerName = player.name;
    final int currentYellows = player.yellowCards;
    final int currentReds = player.redCards;

    bool suspendedByRed = (currentReds > 0 && AdminService.suspensionOnRed);
    bool suspendedByYellow = (currentYellows >= AdminService.suspensionYellowCards);
    
    if (!suspendedByRed && player.isSuspended) {
       suspendedByYellow = true;
    }
    
    String reason = "Motivo desconhecido.";
    if (suspendedByRed && suspendedByYellow) {
       reason = "Motivo: Acúmulo de CA e Cartão Vermelho (Suspensão Múltipla).";
    } else if (suspendedByRed) {
       reason = "Motivo: Cartão Vermelho.";
    } else if (suspendedByYellow) {
       reason = "Motivo: Acúmulo de Cartões Amarelos.";
    }

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Limpar Suspensão'),
          content: Text('Tem certeza que deseja liberar $playerName?\n\n$reason\n\nIsso definirá "Suspenso=Falso" e zerará os cartões da suspensão atual.'),
          actions: <Widget>[
            TextButton(child: const Text('Cancelar'), onPressed: () => Navigator.of(dialogContext).pop()),
            TextButton(
              child: const Text('Confirmar Liberação'),
              onPressed: () async {
                try {
                  final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
                  final playerRef = FirebaseFirestore.instance.collection('championships').doc(seasonId).collection('player_stats').doc(player.id);

                  Map<String, dynamic> updateData = {
                    'is_suspended': false,
                    'red_cards': 0, 
                    if (suspendedByYellow) 'yellow_cards': 0,
                  };

                  await playerRef.update(updateData);
                  
                  final logQuery = await FirebaseFirestore.instance.collection('championships').doc(seasonId).collection('disciplinary_log').where('playerId', isEqualTo: player.id).orderBy('timestamp', descending: true).limit(1).get();
                  if (logQuery.docs.isNotEmpty) {
                    await logQuery.docs.first.reference.update({'return_date': FieldValue.serverTimestamp()});
                  }

                  if(dialogContext.mounted) Navigator.of(dialogContext).pop();
                  if (context.mounted) { 
                     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$playerName liberado da suspensão.')));
                     Provider.of<ChampionshipService>(context, listen: false).fetchStaticData(forceRefresh: true);
                  }
                } catch (e) {
                   if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
                }
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // --- ESTADO VAZIO BONITO ---
    if (players.isEmpty) {
      return CustomEmptyState(
        icon: emptyIcon ?? Icons.person_off,
        title: "Nada por aqui",
        message: emptyMessage,
      );
    }

    final int displayCount = players.length > 50 ? 50 : players.length;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 20, top: 8),
      itemCount: displayCount,
      itemBuilder: (context, index) {
        final player = players[index];
        final rank = index + 1;

        if (index < 3 && !isStatusList) {
          return _buildTopRankItem(context, player, rank);
        }

        return Column(
          children: [
            _buildCompactPlayerItem(context, player, rank),
            const Divider(height: 1, indent: 60),
          ],
        );
      },
    );
  }

  // ... (Resto dos widgets auxiliares _buildTopRankItem e _buildCompactPlayerItem mantidos iguais) ...
  Widget _buildTopRankItem(BuildContext context, Player player, int rank) {
    String val = '';
    if (statField == 'goals') val = '${player.goals}';
    else if (statField == 'assists') val = '${player.assists}';
    else if (statField == 'goalsConceded') val = '${player.goalsConceded}';
    else if (statField == 'motmAwards') val = '${player.motmAwards}';
    else if (statField == 'totalYellowCards') val = '${player.totalYellowCards}';
    else if (statField == 'totalRedCards') val = '${player.totalRedCards}';

    IconData icon = Icons.star;
    if (statLabel == 'Gols') icon = Icons.sports_soccer;
    else if (statLabel == 'Ass') icon = Icons.assistant;
    else if (statLabel == 'GS') icon = Icons.pan_tool_outlined;
    else if (statLabel == 'CA' || statLabel == 'CV') icon = Icons.style;

    Color? customColor;
    if (statLabel == 'CA') customColor = Colors.amber[800];
    if (statLabel == 'CV') customColor = Colors.red;

    return RankHighlightCard(
      rank: rank,
      title: player.name,
      subtitle: player.teamName,
      imageUrl: player.photoUrl,
      statValue: val,
      statLabel: statLabel ?? '',
      statIcon: icon,
      customColor: customColor,
      isPlayer: true,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerProfileScreen(playerId: player.id))),
    );
  }

  Widget _buildCompactPlayerItem(BuildContext context, Player player, int rank) {
    final isAdmin = Provider.of<AuthService>(context).isAuthenticated;

    Widget trailing;
    if (isStatusList) {
      List<Widget> icons = [];
      if (isSuspendedTab) {
        if (player.redCards > 0) icons.add(const Icon(Icons.style, color: Colors.red, size: 18));
        if (player.yellowCards >= (AdminService.suspensionYellowCards > 0 ? AdminService.suspensionYellowCards : 3)) {
           if (icons.isNotEmpty) icons.add(const SizedBox(width: 4));
           icons.add(Icon(Icons.style, color: Colors.amber[700], size: 18));
        }
      } else {
        for(int i=0; i<player.yellowCards; i++) icons.add(Icon(Icons.style, color: Colors.amber[700], size: 18));
      }
      trailing = Row(mainAxisSize: MainAxisSize.min, children: icons);
    } else {
      String val = '';
      if (statField == 'goals') val = '${player.goals}';
      else if (statField == 'assists') val = '${player.assists}';
      else if (statField == 'goalsConceded') val = '${player.goalsConceded}';
      else if (statField == 'motmAwards') val = '${player.motmAwards}';
      else if (statField == 'totalYellowCards') val = '${player.totalYellowCards}';
      else if (statField == 'totalRedCards') val = '${player.totalRedCards}';

      trailing = Text(
        "$val ${statLabel ?? ''}", 
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)
      );
    }

    return ListTile(
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      leading: RankIndicator(rank: rank, size: 28, fontSize: 12),
      title: Text(
        player.name,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          fontStyle: player.isStaff ? FontStyle.italic : FontStyle.normal
        ),
      ),
      subtitle: Row(
        children: [
          if (player.teamShieldUrl.isNotEmpty) ...[
            CachedNetworkImage(
              imageUrl: player.teamShieldUrl, width: 14, height: 14, fit: BoxFit.contain,
              memCacheWidth: 42,
              errorWidget: (_,__,___)=>const Icon(Icons.shield, size: 14, color: Colors.grey),
            ),
            const SizedBox(width: 4),
          ],
          Flexible(child: Text(player.teamName, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
        ],
      ),
      trailing: trailing,
      onTap: () {
        if (isSuspendedTab && isAdmin) {
          _showClearSuspensionDialog(context, player);
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerProfileScreen(playerId: player.id)));
        }
      },
    );
  }
}