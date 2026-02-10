import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; // Para os ícones padrão
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
          _RankingList(isGlobal: false), 
          _RankingList(isGlobal: true),  
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
    Color? rankColor;
    IconData? rankIcon; // Ícone de troféu para TOP 3
    double elevation = 1;

    // Cores para Top 3
    if (rank == 1) {
      rankColor = const Color(0xFFFFD700); 
      rankIcon = Icons.emoji_events;
      elevation = 4;
    } else if (rank == 2) {
      rankColor = const Color(0xFFC0C0C0); 
      rankIcon = Icons.looks_two;
    } else if (rank == 3) {
      rankColor = const Color(0xFFCD7F32); 
      rankIcon = Icons.looks_3;
    }

    final double displayPoints = isGlobal ? team.totalPoints : team.lastScore;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      elevation: elevation,
      color: isMe ? Colors.green[50] : Colors.white, 
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isMe ? const BorderSide(color: Colors.green, width: 2) : BorderSide.none,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        
        // 1. Posição (Rank) e Logo
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Posição
            SizedBox(
              width: 30,
              child: rankIcon != null 
                  ? Icon(rankIcon, color: rankColor, size: 24)
                  : Text("$rankº", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey), textAlign: TextAlign.center),
            ),
            const SizedBox(width: 8),
            
            // LOGO DO TIME (Customizada ou Padrão)
            _buildTeamLogo(team),
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
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue[800]),
              ),
              Text("pts", style: TextStyle(fontSize: 10, color: Colors.grey[600])),
            ],
          ),
        ),
      ),
    );
  }

  // Helper para desenhar a logo
  Widget _buildTeamLogo(FantasyTeam team) {
    if (team.customLogoUrl != null && team.customLogoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 20,
        backgroundColor: Colors.transparent,
        backgroundImage: CachedNetworkImageProvider(team.customLogoUrl!),
      );
    } else {
      return CircleAvatar(
        radius: 20,
        backgroundColor: _getShieldColor(team.shieldType),
        child: Icon(_getShieldIcon(team.shieldType), color: Colors.white, size: 20),
      );
    }
  }

  // Helpers de Iconografia (Copiados para manter consistência com a tela de edição)
  Color _getShieldColor(String type) {
    switch (type) {
      case '1': return Colors.blue; case '2': return Colors.red; case '3': return Colors.green;
      case '4': return Colors.orange; case '5': return Colors.purple; case '6': return Colors.black;
      case '7': return Colors.teal; case '8': return Colors.amber; case '9': return Colors.indigo;
      case '10': return Colors.deepOrange; case '11': return Colors.blueGrey; case '12': return Colors.brown;
      default: return Colors.blue;
    }
  }

  IconData _getShieldIcon(String type) {
    switch (type) {
      case '6': return Icons.sports_soccer;
      case '7': return FontAwesomeIcons.shieldHalved;
      case '8': return FontAwesomeIcons.shieldCat;
      case '9': return FontAwesomeIcons.futbol;
      case '10': return FontAwesomeIcons.userShield;
      case '11': return FontAwesomeIcons.shirt;
      case '12': return FontAwesomeIcons.trophy;
      default: return Icons.shield;
    }
  }
}