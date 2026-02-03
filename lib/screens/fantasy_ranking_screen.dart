import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/fantasy_service.dart';
import '../models/fantasy_models.dart';
import '../services/fantasy_auth_service.dart';

class FantasyRankingScreen extends StatefulWidget {
  const FantasyRankingScreen({super.key});

  @override
  State<FantasyRankingScreen> createState() => _FantasyRankingScreenState();
}

class _FantasyRankingScreenState extends State<FantasyRankingScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Classificação"),
        //backgroundColor: Colors.green[800],
        //foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: "DA RODADA"),
            Tab(text: "GERAL"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _RankingList(isGlobal: false), // Aba Rodada
          _RankingList(isGlobal: true),  // Aba Geral
        ],
      ),
    );
  }
}

class _RankingList extends StatelessWidget {
  final bool isGlobal;

  const _RankingList({required this.isGlobal});

  @override
  Widget build(BuildContext context) {
    final fantasyService = Provider.of<FantasyService>(context, listen: false);
    final authService = Provider.of<FantasyAuthService>(context, listen: false);
    final currentUserId = authService.user?.uid;

    return StreamBuilder<List<FantasyTeam>>(
      stream: fantasyService.streamRanking(isGlobal: isGlobal),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.emoji_events_outlined, size: 60, color: Colors.grey),
                SizedBox(height: 10),
                Text("Nenhum time pontuou ainda.", style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        final teams = snapshot.data!;

        return ListView.builder(
          itemCount: teams.length,
          padding: const EdgeInsets.only(bottom: 20),
          itemBuilder: (ctx, index) {
            final team = teams[index];
            final int rank = index + 1;
            final bool isMe = team.userId == currentUserId;

            return _buildRankingCard(context, rank, team, isMe, isGlobal);
          },
        );
      },
    );
  }

  Widget _buildRankingCard(BuildContext context, int rank, FantasyTeam team, bool isMe, bool isGlobal) {
    // Definição de Cores/Ícones para TOP 3
    Color? rankColor;
    IconData? rankIcon;
    double elevation = 1;

    if (rank == 1) {
      rankColor = const Color(0xFFFFD700); // Dourado
      rankIcon = Icons.emoji_events;
      elevation = 4;
    } else if (rank == 2) {
      rankColor = const Color(0xFFC0C0C0); // Prata
      rankIcon = Icons.looks_two;
    } else if (rank == 3) {
      rankColor = const Color(0xFFCD7F32); // Bronze
      rankIcon = Icons.looks_3;
    }

    // Valor a exibir (Pontos da Rodada ou Total)
    final double displayPoints = isGlobal ? team.totalPoints : team.lastScore;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      elevation: elevation,
      color: isMe ? Colors.green[50] : Colors.white, // Destaca se for o usuário
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isMe ? const BorderSide(color: Colors.green, width: 2) : BorderSide.none,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        // 1. Posição (Rank)
        leading: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (rankIcon != null)
              Icon(rankIcon, color: rankColor, size: 28)
            else
              Text(
                "$rankº",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.grey),
              ),
          ],
        ),
        
        // 2. Dados do Time
        title: Text(
          team.teamName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          team.ownerName,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        
        // 3. Pontuação
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayPoints.toStringAsFixed(2),
                style: TextStyle(
                  fontWeight: FontWeight.bold, 
                  fontSize: 16,
                  color: Colors.blue[800],
                ),
              ),
              Text(
                "pts",
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}