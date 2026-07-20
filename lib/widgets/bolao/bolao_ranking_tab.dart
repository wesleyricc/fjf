import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/bolao_models.dart';
import '../../services/bolao_service.dart';
import '../../screens/bolao/bolao_user_dashboard_screen.dart';

class BolaoRankingTab extends StatefulWidget {
  final String currentUserId;
  final BolaoUser? currentUser;

  const BolaoRankingTab({
    super.key,
    required this.currentUserId,
    required this.currentUser,
  });

  @override
  State<BolaoRankingTab> createState() => _BolaoRankingTabState();
}

class _BolaoRankingTabState extends State<BolaoRankingTab> {
  final TextEditingController _searchController = TextEditingController();
  late Stream<List<BolaoUser>> _leaderboardStream;
  String _searchQuery = '';
  int _displayLimit = 10; 

  @override
  void initState() {
    super.initState();
    _leaderboardStream = BolaoService().streamLeaderboard(); // Inicializada e gerenciada dentro da aba
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BolaoUser>>(
      stream: _leaderboardStream, 
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text("Nenhum participante pontuou ainda."));

        final allUsers = snapshot.data!;

        allUsers.sort((a, b) {
          int cmp = b.totalPoints.compareTo(a.totalPoints);
          if (cmp != 0) return cmp;
          cmp = b.exactHits.compareTo(a.exactHits);
          if (cmp != 0) return cmp;
          cmp = b.goalDifferenceHits.compareTo(a.goalDifferenceHits);
          if (cmp != 0) return cmp;
          cmp = b.winnerHits.compareTo(a.winnerHits);
          if (cmp != 0) return cmp;
          cmp = b.bonusPoints.compareTo(a.bonusPoints);
          if (cmp != 0) return cmp;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase()); 
        });

        final filteredUsers = allUsers.where((u) {
          return u.name.toLowerCase().contains(_searchQuery.toLowerCase());
        }).toList();

        final bool hasMore = filteredUsers.length > _displayLimit;
        final displayCount = hasMore ? _displayLimit : filteredUsers.length;
        final int itemCount = displayCount + (hasMore ? 1 : 0);

        return Column(
          children: [
            _buildSearchBar(),

            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                itemCount: itemCount,
                itemBuilder: (context, index) {
                  if (index == displayCount) return _buildLoadMoreButton();

                  final participant = filteredUsers[index];
                  final bool isMe = participant.userId == widget.currentUserId;
                  
                  int realRank = 1;
                  if (_searchQuery.isEmpty) {
                    final pIndex = allUsers.indexOf(participant);
                    if (pIndex > 0) {
                      final prevUser = allUsers[pIndex - 1];
                      if (participant.totalPoints == prevUser.totalPoints &&
                          participant.exactHits == prevUser.exactHits &&
                          participant.goalDifferenceHits == prevUser.goalDifferenceHits &&
                          participant.winnerHits == prevUser.winnerHits &&
                          participant.bonusPoints == prevUser.bonusPoints) {
                        
                        int tempRank = 1;
                        for (int i = 1; i <= pIndex; i++) {
                          final cur = allUsers[i];
                          final pre = allUsers[i-1];
                          if (cur.totalPoints != pre.totalPoints ||
                              cur.exactHits != pre.exactHits ||
                              cur.goalDifferenceHits != pre.goalDifferenceHits ||
                              cur.winnerHits != pre.winnerHits ||
                              cur.bonusPoints != pre.bonusPoints) {
                            tempRank = i + 1;
                          }
                        }
                        realRank = tempRank;
                      } else {
                        realRank = pIndex + 1;
                      }
                    }
                  }

                  return Card(
                    color: isMe ? Colors.green[50] : Colors.white,
                    elevation: isMe ? 4 : 1,
                    margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: isMe ? const BorderSide(color: Color(0xFF1B5E20), width: 1.5) : BorderSide.none),
                    child: ExpansionTile(
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 25,
                            child: Text(
                              '$realRankº',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: realRank == 1 ? Colors.amber[600] : 
                                       realRank == 2 ? Colors.grey[500] : 
                                       realRank == 3 ? Colors.brown[400] : Colors.black54,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(width: 8),
                          CircleAvatar(
                            backgroundColor: Colors.grey[200],
                            backgroundImage: (participant.photoUrl != null && participant.photoUrl!.isNotEmpty)
                                ? CachedNetworkImageProvider(participant.photoUrl!)
                                : null,
                            child: (participant.photoUrl == null || participant.photoUrl!.isEmpty)
                                ? const Icon(Icons.person, color: Colors.grey)
                                : null,
                          ),
                        ],
                      ),
                      title: Text(participant.name, style: TextStyle(fontWeight: isMe ? FontWeight.bold : FontWeight.w500)),
                      trailing: Text("${participant.totalPoints} pts", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1B5E20))),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          color: Colors.grey[50],
                          child: Column(
                            children: [
                              _buildRankingStatRow("Pontuação Total Real", "${participant.totalPoints} pts", Colors.black87, isBold: true),
                              const Divider(),
                              _buildRankingStatRow("1º Placar Exato (Na Mosca)", "${participant.exactHits} acertos", Colors.green),
                              const Divider(),
                              _buildRankingStatRow("2º Acerto de Vencedor + Saldo", "${participant.goalDifferenceHits} acertos", Colors.blue),
                              const Divider(),
                              _buildRankingStatRow("3º Acerto Simples de Vencedor", "${participant.winnerHits} acertos", Colors.orange),
                              const Divider(),
                              _buildRankingStatRow("4º Pontos Extras (Bônus Finais)", "${participant.bonusPoints} pts", Colors.purple),
                              if (participant.champion != null) ...[
                                const SizedBox(height: 4),
                                _buildBonusRow("Campeão", participant.champion, participant.bonusChampionPoints),
                                _buildBonusRow("Vice", participant.runnerUp, participant.bonusRunnerUpPoints),
                                _buildBonusRow("Melhor Ataque", participant.bestOffense, participant.bonusBestOffensePoints),
                                _buildBonusRow("Pior Defesa", participant.worstDefense, participant.bonusWorstDefensePoints),
                                _buildBonusRow("Decepção", participant.disappointment, participant.bonusDisappointmentPoints),
                              ],
                              const SizedBox(height: 16),
                              
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF1B5E20),
                                    side: const BorderSide(color: Color(0xFF1B5E20)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                                  ),
                                  icon: const Icon(Icons.analytics),
                                  label: const Text("VER RAIO-X DO TREINADOR", style: TextStyle(fontWeight: FontWeight.bold)),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => BolaoUserDashboardScreen(user: participant)),
                                    );
                                  },
                                ),
                              )
                            ],
                          ),
                        )
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      }
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _searchController, 
        onChanged: (value) => setState(() {
          _searchQuery = value;
          _displayLimit = 10; 
        }),
        decoration: InputDecoration(
          hintText: 'Pesquisar participante...',
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
        ),
      ),
    );
  }

  Widget _buildLoadMoreButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 32),
      child: OutlinedButton.icon(
        onPressed: () => setState(() => _displayLimit += 10),
        icon: const Icon(Icons.add),
        label: const Text("VER MAIS PARTICIPANTES"),
      ),
    );
  }

  Widget _buildRankingStatRow(String label, String value, Color color, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.w400, color: Colors.black54)),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildBonusRow(String label, String? guess, int? points) {
    if (guess == null || guess.isEmpty) return const SizedBox.shrink();
    
    String pointsText = "(Pendente)";
    Color ptsColor = Colors.grey;
    if (points != null) {
      if (points > 0) {
        pointsText = "(+$points pts)";
        ptsColor = Colors.green;
      } else {
        pointsText = "(0 pts)";
        ptsColor = Colors.redAccent;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(left: 16.0, top: 2, bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text("• $label: $guess", 
              style: const TextStyle(fontSize: 12, color: Colors.black54),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(pointsText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ptsColor)),
        ],
      ),
    );
  }
}
