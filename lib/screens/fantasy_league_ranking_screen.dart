import 'package:flutter/material.dart';
import '../models/fantasy_league_model.dart';
import '../services/fantasy_league_service.dart';
import '../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../widgets/team_logo_widget.dart';

class FantasyLeagueRankingScreen extends StatefulWidget {
  final FantasyLeague league;

  const FantasyLeagueRankingScreen({super.key, required this.league});

  @override
  State<FantasyLeagueRankingScreen> createState() => _FantasyLeagueRankingScreenState();
}

class _FantasyLeagueRankingScreenState extends State<FantasyLeagueRankingScreen> {
  final FantasyLeagueService _leagueService = FantasyLeagueService();
  
  bool _isLoading = true;
  List<Map<String, dynamic>> _rankedTeams = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    
    // 🚨 Analytics: Registro da visualização do ranking de UMA liga privada específica
    AnalyticsService.logViewItem(
      contentType: 'fantasy_private_league',
      itemId: widget.league.id,
      itemName: widget.league.name,
    );

    _loadLeagueRanking(forceRefresh: false);
  }

  Future<void> _loadLeagueRanking({bool forceRefresh = false}) async {
    setState(() => _isLoading = true);
    
    try {
      final teamsData = await _leagueService.getLeagueRanking(
        widget.league, 
        forceRefresh: forceRefresh
      );

      if (mounted) {
        setState(() {
          _rankedTeams = teamsData;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Erro ao carregar ranking da liga: $e");
      if (mounted) {
        setState(() {
          _errorMessage = "Não foi possível carregar o ranking.";
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.league.name),
            Text("Código: ${widget.league.inviteCode}", style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
      body: _buildBody(primaryColor),
    );
  }

  Widget _buildBody(Color primaryColor) {
    if (_isLoading && _rankedTeams.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _rankedTeams.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: Colors.grey)),
            TextButton(
              onPressed: () => _loadLeagueRanking(forceRefresh: true), 
              child: const Text("Tentar Novamente")
            )
          ],
        ),
      );
    }

    if (_rankedTeams.isEmpty) {
      return const Center(child: Text("Nenhum time encontrado nesta liga."));
    }

    return RefreshIndicator(
      onRefresh: () => _loadLeagueRanking(forceRefresh: true),
      color: primaryColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: _rankedTeams.length,
        itemBuilder: (context, index) {
          final team = _rankedTeams[index];
          final String teamName = team['team_name'] ?? 'Time Sem Nome';
          final String? logoUrl = team['custom_logo_url'];
          final double points = (team['total_points'] ?? 0.0).toDouble();
          
          final int rank = index + 1;
          
          Color rankColor = Colors.grey.shade300;
          if (rank == 1) rankColor = Colors.amber; 
          else if (rank == 2) rankColor = Colors.grey.shade400; 
          else if (rank == 3) rankColor = Colors.brown.shade300; 

          return Card(
            elevation: rank <= 3 ? 4 : 1,
            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: rank <= 3 ? BorderSide(color: rankColor, width: 2) : BorderSide.none,
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "$rankº", 
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: rank <= 3 ? rankColor : Colors.grey),
                  ),
                  const SizedBox(width: 12),
                  
                  TeamLogoWidget(
                    logoUrl: logoUrl,
                    radius: 20,
                  ),
                ],
              ),
              title: Text(teamName, style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: Text(
                points.toStringAsFixed(2),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: primaryColor),
              ),
            ),
          );
        },
      ),
    );
  }
}