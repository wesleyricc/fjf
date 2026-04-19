import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/poll_model.dart';
import '../models/player_model.dart';
import '../services/championship_service.dart';
import '../services/voting_service.dart';

class AdminPollResultsScreen extends StatelessWidget {
  final Poll poll;

  const AdminPollResultsScreen({super.key, required this.poll});

  // Função auxiliar para descobrir a posição do indicado cruzando com o banco de jogadores
  String _getCategoryForNominee(Nominee nom, List<Player> allPlayers) {
    try {
      final p = allPlayers.firstWhere((player) => player.id == nom.playerId);
      
      if (p.isStaff) {
        final role = ((p as dynamic).staffRole ?? p.position ?? '').toLowerCase();
        if (role.contains('tecnico') || role.contains('técnico')) return 'Treinadores';
        return 'Outros'; 
      }
      
      final pos = (p.position ?? '').toLowerCase();
      if (p.isGoalkeeper || pos.contains('goleiro')) return 'Goleiros';
      if (pos.contains('fixo')) return 'Fixos';
      if (pos.contains('ala')) return 'Alas';
      if (pos.contains('piv')) return 'Pivôs';
      
      return 'Outros';
    } catch (e) {
      return 'Outros'; // Caso o jogador tenha sido excluído do banco, mas ainda tenha votos
    }
  }

  @override
  Widget build(BuildContext context) {
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    final allPlayers = Provider.of<ChampionshipService>(context, listen: false).allPlayers;
    
    final bool isDraftSelection = poll.category == 'selecao_campeonato';

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Resultados em Tempo Real'),
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // CABEÇALHO DA VOTAÇÃO
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(poll.category.toUpperCase().replaceAll('_', ' '), style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                Text(poll.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          
          // CORPO (RESULTADOS)
          Expanded(
            child: StreamBuilder<List<Nominee>>(
              stream: VotingService().streamNominees(seasonId, poll.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('Nenhum voto registrado ainda.'));

                final nominees = snapshot.data!;

                // Roteamento inteligente: Se for Seleção, agrupa por posição. Se não, lista normal.
                if (isDraftSelection) {
                  return _buildDraftResults(nominees, allPlayers);
                } else {
                  return _buildStandardResults(nominees);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // MODO: SELEÇÃO DO CAMPEONATO (AGRUPADO POR POSIÇÃO)
  // ==========================================================
  Widget _buildDraftResults(List<Nominee> nominees, List<Player> allPlayers) {
    // 1. Cria os grupos
    final Map<String, List<Nominee>> groups = {
      'Goleiros': [], 'Fixos': [], 'Alas': [], 'Pivôs': [], 'Treinadores': [], 'Outros': []
    };

    // 2. Distribui os indicados
    for (var nom in nominees) {
      final category = _getCategoryForNominee(nom, allPlayers);
      groups[category]!.add(nom);
    }

    final List<Widget> slivers = [];
    final order = ['Goleiros', 'Fixos', 'Alas', 'Pivôs', 'Treinadores', 'Outros'];

    // 3. Monta a tela por seções
    for (var key in order) {
      if (groups[key]!.isEmpty) continue;
      
      // Ordena quem tem mais votos primeiro dentro de cada posição
      groups[key]!.sort((a, b) => b.voteCount.compareTo(a.voteCount));

      // Calcula o total de votos apenas DESTA posição para gerar a barra de porcentagem
      final int catTotal = groups[key]!.fold(0, (sum, item) => sum + item.voteCount);

      slivers.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Row(
            children: [
              Icon(Icons.sports_soccer, size: 16, color: Colors.blueGrey.shade700),
              const SizedBox(width: 8),
              Text(key.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.blueGrey.shade800, letterSpacing: 1)),
            ],
          ),
        )
      );

      slivers.add(
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: groups[key]!.length,
          itemBuilder: (context, index) {
            return _buildNomineeCard(groups[key]![index], index, catTotal);
          },
        )
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 40),
      children: slivers,
    );
  }

  // ==========================================================
  // MODO: VOTAÇÃO PADRÃO (RANKING ÚNICO)
  // ==========================================================
  Widget _buildStandardResults(List<Nominee> nominees) {
    final int totalVotes = nominees.fold(0, (sum, item) => sum + item.voteCount);

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: nominees.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _buildNomineeCard(nominees[index], index, totalVotes);
      },
    );
  }

  // ==========================================================
  // COMPONENTE: CARD DO JOGADOR
  // ==========================================================
  Widget _buildNomineeCard(Nominee nominee, int index, int totalVotesContext) {
    final double percent = totalVotesContext == 0 ? 0 : (nominee.voteCount / totalVotesContext);
    
    // Cores de medalha para os 3 primeiros colocados (no caso da seleção, ajuda a ver os 4 alas classificados)
    Color rankColor = Colors.grey;
    if (index == 0) rankColor = Colors.amber.shade600;      // Ouro
    if (index == 1) rankColor = Colors.blueGrey.shade300;   // Prata
    if (index == 2) rankColor = Colors.brown.shade400;      // Bronze

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            SizedBox(
              width: 35,
              child: Text('#${index + 1}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: rankColor)),
            ),
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.grey.shade200,
              backgroundImage: nominee.playerPhotoUrl.isNotEmpty ? CachedNetworkImageProvider(nominee.playerPhotoUrl) : null,
              child: nominee.playerPhotoUrl.isEmpty ? const Icon(Icons.person, color: Colors.grey) : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nominee.playerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(nominee.teamName, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${(percent * 100).toStringAsFixed(1)}%', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                      Text('${nominee.voteCount} votos', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: percent,
                    backgroundColor: Colors.grey.shade200,
                    color: index == 0 ? Colors.green : Colors.blueGrey,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}