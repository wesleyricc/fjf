import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/fantasy_league_model.dart';
import '../widgets/team_logo_widget.dart'; // 🚨 O nosso componente inteligente!

class FantasyLeagueRankingScreen extends StatefulWidget {
  final FantasyLeague league;

  const FantasyLeagueRankingScreen({super.key, required this.league});

  @override
  State<FantasyLeagueRankingScreen> createState() => _FantasyLeagueRankingScreenState();
}

class _FantasyLeagueRankingScreenState extends State<FantasyLeagueRankingScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _rankedTeams = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadLeagueRanking();
  }

  Future<void> _loadLeagueRanking() async {
    try {
      final firestore = FirebaseFirestore.instance;
      
      // 🚨 OTIMIZAÇÃO FINOPS E CONTORNO DE LIMITES DO FIREBASE
      // Busca todos os times dos membros em paralelo (ignora o limite de 10 do 'whereIn')
      final docs = await Future.wait(
        widget.league.members.map((uid) => firestore.collection('fantasy_teams').doc(uid).get())
      );

      final List<Map<String, dynamic>> teamsData = [];
      for (var doc in docs) {
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          data['uid'] = doc.id;
          teamsData.add(data);
        }
      }

      // 🚨 ORDENAÇÃO LOCAL (Do maior pontuador para o menor)
      // Ajuste 'total_points' para o nome exato do campo que guarda a pontuação no seu banco
      teamsData.sort((a, b) {
        final double pointsA = (a['total_points'] ?? 0.0).toDouble();
        final double pointsB = (b['total_points'] ?? 0.0).toDouble();
        return pointsB.compareTo(pointsA); 
      });

      setState(() {
        _rankedTeams = teamsData;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Erro ao carregar ranking da liga: $e");
      setState(() {
        _errorMessage = "Não foi possível carregar o ranking.";
        _isLoading = false;
      });
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 60, color: Colors.red),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: const TextStyle(color: Colors.grey)),
            TextButton(onPressed: _loadLeagueRanking, child: const Text("Tentar Novamente"))
          ],
        ),
      );
    }

    if (_rankedTeams.isEmpty) {
      return const Center(child: Text("Nenhum time encontrado nesta liga."));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _rankedTeams.length,
      itemBuilder: (context, index) {
        final team = _rankedTeams[index];
        final String teamName = team['team_name'] ?? 'Time Sem Nome';
        final String? logoUrl = team['custom_logo_url'];
        final double points = (team['total_points'] ?? 0.0).toDouble();
        
        // Posição no ranking
        final int rank = index + 1;
        
        // Estilização dos 3 primeiros colocados
        Color rankColor = Colors.grey.shade300;
        if (rank == 1) rankColor = Colors.amber; // Ouro
        else if (rank == 2) rankColor = Colors.grey.shade400; // Prata
        else if (rank == 3) rankColor = Colors.brown.shade300; // Bronze

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
                
                // 🔥 O NOSSO COMPONENTE MÁGICO ENTRA AQUI 🔥
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
    );
  }
}