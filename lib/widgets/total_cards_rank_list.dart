// lib/widgets/total_cards_rank_list.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../screens/player_profile_screen.dart';
import '../utils/custom_cache_manager.dart';
import '../widgets/rank_highlight_card.dart'; 

class TotalCardsRankList extends StatefulWidget {
  final Query baseQuery;
  final String emptyMessage;

  const TotalCardsRankList({
    super.key, 
    required this.baseQuery, 
    required this.emptyMessage
  });

  @override
  State<TotalCardsRankList> createState() => _TotalCardsRankListState();
}

class _TotalCardsRankListState extends State<TotalCardsRankList> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _sortedPlayers = [];
  List<Map<String, dynamic>> _displayedList = [];
  bool _isLoading = true;
  int _currentMax = 20;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchAndProcess();
  }

  Future<void> _fetchAndProcess() async {
    try {
      final snapshot = await widget.baseQuery.get();
      List<Map<String, dynamic>> temp = [];

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final int y = data['total_yellow_cards'] ?? 0;
        final int r = data['total_red_cards'] ?? 0;
        final int total = y + r;

        if (total > 0) {
          temp.add({
            'doc': doc,
            'data': data,
            'total': total,
            'y': y,
            'r': r,
          });
        }
      }

      temp.sort((a, b) {
        int comp = b['total'].compareTo(a['total']);
        if (comp != 0) return comp;
        return (a['data']['name'] ?? '').compareTo(b['data']['name'] ?? '');
      });

      if (mounted) {
        setState(() {
          _sortedPlayers = temp;
          _updateDisplayed();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _updateDisplayed() {
    int end = (_currentMax > _sortedPlayers.length) ? _sortedPlayers.length : _currentMax;
    _displayedList = _sortedPlayers.sublist(0, end);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_sortedPlayers.isEmpty) return Center(child: Text(widget.emptyMessage));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _displayedList.length + (_displayedList.length < _sortedPlayers.length ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _displayedList.length) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(child: ElevatedButton(
              onPressed: () => setState(() { _currentMax += 20; _updateDisplayed(); }),
              child: const Text("Carregar mais")
            )),
          );
        }

        final item = _displayedList[index];
        final data = item['data'];
        final doc = item['doc'] as DocumentSnapshot;
        final rank = index + 1;
        
        final int y = item['y'];
        final int r = item['r'];

        if (index < 3) {
          Color detailColor = (rank == 3) ? Colors.white70 : Colors.black54;

          return RankHighlightCard(
            rank: rank,
            title: data['name'] ?? 'Nome',
            subtitle: data['team_name'] ?? '',
            imageUrl: data['photo_url'] ?? '',
            statValue: '${item['total']}',
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
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerProfileScreen(playerId: doc.id))),
          );
        }

        final name = data['name'] ?? 'Nome';
        final isStaff = data['is_staff'] ?? false;
        final photoUrl = data['photo_url'] ?? '';
        final shieldUrl = data['team_shield_url'] ?? '';
        final teamName = data['team_name'] ?? '';

        return Column(
          children: [
            ListTile(
              leading: CircleAvatar(
                radius: 22,
                backgroundColor: Colors.grey[200],
                // PERFORMANCE: Controle de memória aplicado
                child: photoUrl.isNotEmpty 
                  ? ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: photoUrl,
                        width: 44, height: 44,
                        fit: BoxFit.cover,
                        memCacheWidth: 150,
                        cacheManager: PlayerCacheManager.instance,
                        placeholder: (context, url) => const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        errorWidget: (context, url, error) => const Icon(Icons.person, color: Colors.grey),
                      ),
                    )
                  : Icon(isStaff ? Icons.assignment_ind : Icons.person, color: Colors.grey),
              ),
              title: Text(name, style: TextStyle(fontStyle: isStaff ? FontStyle.italic : FontStyle.normal)),
              subtitle: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(4)),
                    child: Text("$rankº", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 6),
                  if (shieldUrl.isNotEmpty) ...[
                    CachedNetworkImage(
                      imageUrl: shieldUrl, width: 16, height: 16, fit: BoxFit.contain, 
                      memCacheWidth: 48,
                      errorWidget: (_,__,___)=>const Icon(Icons.shield, size:16)
                    ),
                    const SizedBox(width: 4)
                  ],
                  Flexible(child: Text(teamName, overflow: TextOverflow.ellipsis)),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${item['total']} Cartões', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$y', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      Icon(Icons.style, color: Colors.yellow[700], size: 12),
                      const SizedBox(width: 4),
                      Text('$r', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      const Icon(Icons.style, color: Colors.red, size: 12),
                    ],
                  )
                ],
              ),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerProfileScreen(playerId: doc.id))),
            ),
            const Divider(height: 1, indent: 70),
          ],
        );
      },
    );
  }
}