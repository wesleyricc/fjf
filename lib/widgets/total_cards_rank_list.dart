import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/player_model.dart';
import '../screens/player_profile_screen.dart';
import '../widgets/rank_highlight_card.dart';
import '../widgets/rank_indicator.dart';

class TotalCardsRankList extends StatelessWidget {
  final List<Player> allPlayers;

  const TotalCardsRankList({super.key, required this.allPlayers});

  @override
  Widget build(BuildContext context) {
    // Processamento Local: Filtra quem tem cartões e ordena
    final List<Player> sortedList = allPlayers.where((p) {
      return (p.totalYellowCards + p.totalRedCards) > 0;
    }).toList();

    sortedList.sort((a, b) {
      int totalA = a.totalYellowCards + a.totalRedCards;
      int totalB = b.totalYellowCards + b.totalRedCards;
      int comp = totalB.compareTo(totalA);
      if (comp != 0) return comp;
      return a.name.compareTo(b.name);
    });

    if (sortedList.isEmpty) return const Center(child: Text("Sem cartões registrados."));

    // Paginação simples local para não travar a UI se tiver 500 jogadores
    final int displayCount = sortedList.length > 50 ? 50 : sortedList.length;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: displayCount,
      itemBuilder: (context, index) {
        final player = sortedList[index];
        final rank = index + 1;
        final int y = player.totalYellowCards;
        final int r = player.totalRedCards;
        final int total = y + r;

        // --- DESTAQUE TOP 3 ---
        if (index < 3) {
          Color detailColor = (rank == 3) ? Colors.white70 : Colors.black54;
          return RankHighlightCard(
            rank: rank,
            title: player.name,
            subtitle: player.teamName,
            imageUrl: player.photoUrl,
            statValue: '$total',
            statLabel: 'Cartões',
            statIcon: Icons.layers,
            isPlayer: true,
            extraInfoWidget: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$y', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: detailColor)),
                const SizedBox(width: 2),
                Icon(Icons.style, size: 12, color: Colors.amber[700]),
                const SizedBox(width: 6),
                Text('$r', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: detailColor)),
                const SizedBox(width: 2),
                const Icon(Icons.style, size: 12, color: Colors.red),
              ],
            ),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerProfileScreen(playerId: player.id))),
          );
        }

        // --- LISTA COMPACTA ---
        return Column(
          children: [
            ListTile(
              visualDensity: VisualDensity.compact,
              leading: RankIndicator(rank: rank, size: 28, fontSize: 12),
              title: Text(player.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Row(
                children: [
                  if (player.teamShieldUrl.isNotEmpty) ...[
                    CachedNetworkImage(
                      imageUrl: player.teamShieldUrl, width: 14, height: 14, fit: BoxFit.contain, 
                      memCacheWidth: 42,
                      errorWidget: (_,__,___)=>const Icon(Icons.shield, size:14, color:Colors.grey)
                    ),
                    const SizedBox(width: 4)
                  ],
                  Flexible(child: Text(player.teamName, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$total', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(width: 8),
                  if (y > 0) ...[Text('$y', style: const TextStyle(fontSize: 11, color: Colors.grey)), Icon(Icons.style, color: Colors.amber[700], size: 14)],
                  if (r > 0) ...[const SizedBox(width: 4), Text('$r', style: const TextStyle(fontSize: 11, color: Colors.grey)), const Icon(Icons.style, color: Colors.red, size: 14)],
                ],
              ),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerProfileScreen(playerId: player.id))),
            ),
            const Divider(height: 1, indent: 60),
          ],
        );
      },
    );
  }
}