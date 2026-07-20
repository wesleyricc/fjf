import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/fantasy_league_model.dart';
import '../../services/fantasy_auth_service.dart';
import '../../viewmodels/fantasy_league_viewmodel.dart';

class FantasyKnockoutBracketScreen extends StatefulWidget {
  final FantasyLeague league;

  const FantasyKnockoutBracketScreen({super.key, required this.league});

  @override
  State<FantasyKnockoutBracketScreen> createState() => _FantasyKnockoutBracketScreenState();
}

class _FantasyKnockoutBracketScreenState extends State<FantasyKnockoutBracketScreen> {
  @override
  Widget build(BuildContext context) {
    final currentUserId = Provider.of<FantasyAuthService>(context, listen: false).user?.uid;
    final isOwner = widget.league.ownerId == currentUserId;
    final isWaiting = widget.league.status == 'waiting';

    return Scaffold(
      appBar: AppBar(title: Text(widget.league.name)),
      body: Consumer<FantasyLeagueViewModel>(
        builder: (context, vm, child) {
          if (isWaiting) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.sports_kabaddi, size: 80, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    "Aguardando participantes...\n${widget.league.members.length} de ${widget.league.maxTeams}",
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 24),
                  if (isOwner && widget.league.members.length == widget.league.maxTeams)
                    ElevatedButton.icon(
                      onPressed: () async {
                        final success = await vm.generateBracket(widget.league);
                        if (success && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Chaveamento gerado!")));
                          Navigator.pop(context); 
                        } else if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(vm.errorMessage ?? "Erro")));
                        }
                      },
                      icon: const Icon(Icons.shuffle),
                      label: const Text("Sortear Chaves e Iniciar"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    )
                  else if (isOwner)
                    const Text("O sorteio só será liberado quando a liga lotar.", style: TextStyle(color: Colors.grey))
                ],
              ),
            );
          }

          return StreamBuilder<List<KnockoutMatch>>(
            stream: vm.streamKnockoutMatches(widget.league.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text("Nenhum confronto encontrado."));
              }

              final matches = snapshot.data!;
              
              final Map<String, List<KnockoutMatch>> phases = {};
              for (var m in matches) {
                phases.putIfAbsent(m.phase, () => []).add(m);
              }

              return ListView(
                padding: const EdgeInsets.all(16),
                children: phases.entries.map((entry) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(entry.key, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
                      ),
                      ...entry.value.map((match) => _buildMatchCard(match)).toList(),
                      const Divider(height: 32),
                    ],
                  );
                }).toList(),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMatchCard(KnockoutMatch match) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _buildTeamRow(match.teamAId, match.teamAScore, match.winnerId),
            const Divider(),
            _buildTeamRow(match.teamBId, match.teamBScore, match.winnerId),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamRow(String? teamId, double score, String? winnerId) {
    final bool isWinner = winnerId != null && winnerId == teamId;
    final bool isLoser = winnerId != null && winnerId != teamId;
    
    String displayName = teamId ?? 'A Definir';
    if (displayName.length > 10 && teamId != null) {
      displayName = "Time ${teamId.substring(0, 5)}...";
    }

    return Row(
      children: [
        Icon(Icons.shield, color: isWinner ? Colors.green : (isLoser ? Colors.grey : Colors.blue)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            displayName,
            style: TextStyle(
              fontWeight: isWinner ? FontWeight.bold : FontWeight.normal,
              color: isLoser ? Colors.grey : Colors.black,
            ),
          ),
        ),
        Text(
          score.toStringAsFixed(2),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: isWinner ? Colors.green : (isLoser ? Colors.grey : Colors.black87),
          ),
        ),
      ],
    );
  }
}
