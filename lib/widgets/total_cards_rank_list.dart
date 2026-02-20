import 'package:flutter/material.dart';
// import 'package:cached_network_image/cached_network_image.dart'; // Pode remover se não for usar em outro lugar do arquivo
import '../models/player_model.dart';
import '../screens/player_profile_screen.dart';
import '../widgets/rank_highlight_card.dart';
import '../widgets/rank_indicator.dart';

class TotalCardsRankList extends StatefulWidget {
  final List<Player> allPlayers;

  const TotalCardsRankList({super.key, required this.allPlayers});

  @override
  State<TotalCardsRankList> createState() => _TotalCardsRankListState();
}

class _TotalCardsRankListState extends State<TotalCardsRankList> {
  // --- CONTROLE DE PAGINAÇÃO ---
  int _displayLimit = 10;

  @override
  Widget build(BuildContext context) {
    // Processamento Local: Filtra quem tem cartões e ordena
    final List<Player> sortedList = widget.allPlayers.where((p) {
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

    // Lógica de Paginação
    final bool hasMore = sortedList.length > _displayLimit;
    final int displayCount = hasMore ? _displayLimit : sortedList.length;
    final int itemCount = displayCount + (hasMore ? 1 : 0);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
      itemCount: itemCount,
      itemBuilder: (context, index) {

        // --- BOTÃO CARREGAR MAIS ---
        if (index == displayCount) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 32),
            child: OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _displayLimit += 10; // Adiciona mais 10 à lista
                });
              },
              icon: const Icon(Icons.add),
              label: const Text("CARREGAR MAIS", style: TextStyle(fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                foregroundColor: Theme.of(context).primaryColor,
                side: BorderSide(color: Theme.of(context).primaryColor),
              ),
            ),
          );
        }

        final player = sortedList[index];
        final rank = index + 1;
        final int y = player.totalYellowCards;
        final int r = player.totalRedCards;
        final int total = y + r;

        // --- DESTAQUE TOP 3 (Com Foto e Hero Animation) ---
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
            onTap: () => Navigator.push(
              context, 
              MaterialPageRoute(
                builder: (_) => PlayerProfileScreen(
                  playerId: player.id, 
                  heroTag: 'rank_player_cards_${player.id}' // <-- HERO TAG DINÂMICA
                )
              )
            ),
          );
        }

        // --- LISTA COMPACTA (Do 4º em diante) ---
        return Column(
          children: [
            ListTile(
              visualDensity: VisualDensity.compact,
              leading: RankIndicator(rank: rank, size: 28, fontSize: 12),
              title: Text(player.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Row(
                children: [
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
              onTap: () => Navigator.push(
                context, 
                MaterialPageRoute(builder: (_) => PlayerProfileScreen(playerId: player.id))
              ),
            ),
            const Divider(height: 1, indent: 60),
          ],
        );
      },
    );
  }
}