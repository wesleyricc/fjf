import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/fantasy_service.dart';
import '../models/fantasy_models.dart';
import '../services/fantasy_auth_service.dart';
import '../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../widgets/ui/shimmer_effect.dart';     
import '../widgets/ui/custom_empty_state.dart';  
import '../widgets/team_logo_widget.dart';

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
    
    // 🚨 Analytics: Acesso inicial ao ranking (Aba da Rodada como Padrão)
    AnalyticsService.logCustomScreenView('Fantasy_Ranking_Tab_Rodada');

    // 🚨 Analytics: Monitora qual ranking os usuários mais olham
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final tabName = _tabController.index == 0 ? 'Rodada' : 'Geral';
        AnalyticsService.logCustomScreenView('Fantasy_Ranking_Tab_$tabName');
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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

class _RankingList extends StatefulWidget {
  final bool isGlobal;

  const _RankingList({required this.isGlobal});

  @override
  State<_RankingList> createState() => _RankingListState();
}

class _RankingListState extends State<_RankingList> {
  @override
  Widget build(BuildContext context) {
    final fantasyService = Provider.of<FantasyService>(context, listen: false);
    final authService = Provider.of<FantasyAuthService>(context, listen: false);
    final currentUserId = authService.user?.uid;

    return StreamBuilder<List<FantasyTeam>>(
      stream: fantasyService.streamRanking(isGlobal: widget.isGlobal),
      builder: (context, snapshot) {
        
        // 1. ESTADO OFFLINE/ERRO
        if (snapshot.hasError) {
          return CustomEmptyState.offline(
            onRetry: () => setState(() {}), 
          );
        }

        // 2. LOADING
        if (snapshot.connectionState == ConnectionState.waiting) {
          return ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: 8,
            itemBuilder: (_, __) => _buildSkeletonItem(),
          );
        }

        // 3. EMPTY STATE
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const CustomEmptyState(
            icon: Icons.emoji_events_outlined,
            title: "Sem Classificação",
            message: "Nenhum time pontuou nesta liga ainda.",
          );
        }

        final teams = snapshot.data!;

        // 4. LISTA REAL
        return ListView.builder(
          itemCount: teams.length,
          padding: const EdgeInsets.only(bottom: 20, top: 10),
          itemBuilder: (ctx, index) {
            final team = teams[index];
            final int rank = index + 1;
            final bool isMe = team.userId == currentUserId;

            return _buildRankingCard(context, rank, team, isMe, widget.isGlobal);
          },
        );
      },
    );
  }

  Widget _buildSkeletonItem() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: const [
            ShimmerEffect.rectangular(height: 20, width: 30), 
            SizedBox(width: 12),
            ShimmerEffect.circular(size: 40), 
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShimmerEffect.rectangular(height: 16, width: 120), 
                  SizedBox(height: 6),
                  ShimmerEffect.rectangular(height: 12, width: 80), 
                ],
              ),
            ),
            ShimmerEffect.rectangular(height: 20, width: 40), 
          ],
        ),
      ),
    );
  }

  Widget _buildRankingCard(BuildContext context, int rank, FantasyTeam team, bool isMe, bool isGlobal) {
    Color? rankColor;
    IconData? rankIcon; 
    double elevation = 1;

    if (rank == 1) { rankColor = const Color(0xFFFFD700); rankIcon = Icons.emoji_events; elevation = 4; } 
    else if (rank == 2) { rankColor = const Color(0xFFC0C0C0); rankIcon = Icons.looks_two; } 
    else if (rank == 3) { rankColor = const Color(0xFFCD7F32); rankIcon = Icons.looks_3; }

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
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 30,
              child: rankIcon != null 
                  ? Icon(rankIcon, color: rankColor, size: 24)
                  : Text("$rankº", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey), textAlign: TextAlign.center),
            ),
            const SizedBox(width: 8),
            
            TeamLogoWidget(
              logoUrl: team.customLogoUrl,
              radius: 20,
            ),
          ],
        ),
        title: Text(team.teamName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(team.ownerName, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade300)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(displayPoints.toStringAsFixed(2), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue[800])),
              Text("pts", style: TextStyle(fontSize: 10, color: Colors.grey[600])),
          ]),
        ),
      ),
    );
  }
}