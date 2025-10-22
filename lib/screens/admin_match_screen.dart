// lib/screens/admin_match_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import '../services/firestore_service.dart';

class AdminMatchScreen extends StatefulWidget {
  final DocumentSnapshot match;
  const AdminMatchScreen({super.key, required this.match});

  @override
  State<AdminMatchScreen> createState() => _AdminMatchScreenState();
}

class _AdminMatchScreenState extends State<AdminMatchScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirestoreService _firestoreService = FirestoreService();

  late TextEditingController _homeScoreController;
  late TextEditingController _awayScoreController;

  List<DocumentSnapshot> _homePlayers = [];
  List<DocumentSnapshot> _awayPlayers = [];
  bool _isLoadingPlayers = true;
  bool _isSaving = false;

  // Mapas para contar as estatísticas (ID do Jogador -> Quantidade)
  Map<String, int> _goals = {};
  Map<String, int> _assists = {};
  Map<String, int> _yellowCards = {};
  Map<String, int> _redCards = {};

  @override
  void initState() {
    super.initState();
    
    final data = widget.match.data() as Map<String, dynamic>;

    _homeScoreController = TextEditingController(
      text: data['score_home']?.toString() ?? '0',
    );
    _awayScoreController = TextEditingController(
      text: data['score_away']?.toString() ?? '0',
    );

    // Carrega estatísticas antigas se existirem
    if (data.containsKey('stats_applied') && data['stats_applied'] != null) {
      final stats = data['stats_applied']['player_stats'];
      _goals = Map<String, int>.from(stats['goals'] ?? {});
      _assists = Map<String, int>.from(stats['assists'] ?? {});
      _yellowCards = Map<String, int>.from(stats['yellows'] ?? {});
      _redCards = Map<String, int>.from(stats['reds'] ?? {});
    }

    _fetchPlayers();
  }

  Future<void> _fetchPlayers() async {
    // (Esta função continua idêntica)
    try {
      final String homeTeamId = widget.match['team_home_id'];
      final String awayTeamId = widget.match['team_away_id'];

      final homeQuery = await _firestore
          .collection('players')
          .where('team_id', isEqualTo: homeTeamId)
          .get();
      _homePlayers = homeQuery.docs;

      final awayQuery = await _firestore
          .collection('players')
          .where('team_id', isEqualTo: awayTeamId)
          .get();
      _awayPlayers = awayQuery.docs;

      setState(() { _isLoadingPlayers = false; });
    } catch (e) {
      debugPrint('Erro ao buscar jogadores: $e');
      setState(() { _isLoadingPlayers = false; });
    }
  }

  Future<void> _saveStats() async {
    // (Esta função continua idêntica)
    setState(() { _isSaving = true; });

    final int scoreHome = int.tryParse(_homeScoreController.text) ?? 0;
    final int scoreAway = int.tryParse(_awayScoreController.text) ?? 0;

    String result = await _firestoreService.updateMatchStats(
      matchSnapshot: widget.match,
      newScoreHome: scoreHome,
      newScoreAway: scoreAway,
      newGoals: _goals,
      newAssists: _assists,
      newYellows: _yellowCards,
      newReds: _redCards,
    );

    setState(() { _isSaving = false; });

    if(result == "Sucesso") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Estatísticas salvas com sucesso!')),
      );
      Navigator.of(context).pop(); 
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar: $result', maxLines: 5),
        ),
      );
    }
  }

  // --- NOVO: Função que abre o pop-up de edição ---
  Future<void> _showPlayerStatEditor(DocumentSnapshot player) async {
    final playerId = player.id;
    final data = player.data() as Map<String, dynamic>;

    // Copia os valores atuais para um estado temporário do diálogo
    int tempGoals = _goals[playerId] ?? 0;
    int tempAssists = _assists[playerId] ?? 0;
    int tempYellows = _yellowCards[playerId] ?? 0;
    int tempReds = _redCards[playerId] ?? 0;

    return showDialog<void>(
      context: context,
      barrierDismissible: false, // Usuário deve clicar em Cancelar ou Confirmar
      builder: (BuildContext context) {
        // Usamos um StatefulBuilder para que o diálogo
        // possa ter seu próprio estado e se atualizar
        return StatefulBuilder(
          builder: (context, setDialogState) {

            // Função auxiliar para o contador (agora vive dentro do diálogo)
            Widget buildStatCounter({
              required IconData icon,
              required String label,
              required int count,
              required VoidCallback onAdd,
              required VoidCallback onRemove,
              Color? color,
            }) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 24, color: color),
                      const SizedBox(width: 12),
                      Text('$label:', style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle, size: 28, color: Colors.red),
                        onPressed: onRemove,
                      ),
                      Text(count.toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add_circle, size: 28, color: Colors.green),
                        onPressed: onAdd,
                      ),
                    ],
                  ),
                ],
              );
            }

            return AlertDialog(
              title: Text(data['name']), // Nome do jogador no título
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    buildStatCounter(
                      icon: Icons.sports_soccer,
                      label: "Gols",
                      count: tempGoals,
                      // Atualiza o estado do *diálogo*
                      onAdd: () => setDialogState(() => tempGoals++),
                      onRemove: () => setDialogState(() => tempGoals = (tempGoals > 0) ? tempGoals - 1 : 0),
                    ),
                    buildStatCounter(
                      icon: Icons.assistant,
                      label: "Assist.",
                      count: tempAssists,
                      onAdd: () => setDialogState(() => tempAssists++),
                      onRemove: () => setDialogState(() => tempAssists = (tempAssists > 0) ? tempAssists - 1 : 0),
                    ),
                    buildStatCounter(
                      icon: Icons.style,
                      label: "CA",
                      color: Colors.yellow[700],
                      count: tempYellows,
                      onAdd: () => setDialogState(() => tempYellows++),
                      onRemove: () => setDialogState(() => tempYellows = (tempYellows > 0) ? tempYellows - 1 : 0),
                    ),
                    buildStatCounter(
                      icon: Icons.style,
                      label: "CV",
                      color: Colors.red[700],
                      count: tempReds,
                      onAdd: () => setDialogState(() => tempReds = 1),
                      onRemove: () => setDialogState(() => tempReds = 0),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('Cancelar'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: const Text('Confirmar'),
                  onPressed: () {
                    // Atualiza o estado PRINCIPAL da tela (fora do diálogo)
                    setState(() {
                      _goals[playerId] = tempGoals;
                      _assists[playerId] = tempAssists;
                      _yellowCards[playerId] = tempYellows;
                      _redCards[playerId] = tempReds;
                    });
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    // (O build do Scaffold continua o mesmo)
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.match['team_home_name']} x ${widget.match['team_away_name']}',
        ),
        actions: [
          if (_isSaving) const Padding(
            padding: EdgeInsets.all(16.0),
            child: CircularProgressIndicator(color: Colors.white),
          ) else IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveStats,
          ),
        ],
      ),
      body: _isLoadingPlayers
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  _buildScoreCard(),
                  const SizedBox(height: 16),
                  Text('Time da Casa: ${widget.match['team_home_name']}', style: Theme.of(context).textTheme.headlineSmall),
                  _buildPlayerList(_homePlayers),
                  const SizedBox(height: 16),
                  Text('Time Visitante: ${widget.match['team_away_name']}', style: Theme.of(context).textTheme.headlineSmall),
                  _buildPlayerList(_awayPlayers),
                ],
              ),
            ),
    );
  }

  // Widget para o placar (Idêntico)
  Widget _buildScoreCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Expanded(child: Text(widget.match['team_home_name'], style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
            SizedBox(
              width: 60,
              child: TextField(
                controller: _homeScoreController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: Text('x'),
            ),
            SizedBox(
              width: 60,
              child: TextField(
                controller: _awayScoreController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ),
            Expanded(child: Text(widget.match['team_away_name'], style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }

  // --- ATUALIZADO: _buildPlayerList (Agora é uma lista simples) ---
  Widget _buildPlayerList(List<DocumentSnapshot> players) {
    if (players.isEmpty) {
      return const Text('Nenhum jogador encontrado para este time.');
    }
    
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: players.length,
      itemBuilder: (context, index) {
        final player = players[index];
        final playerId = player.id;
        final data = player.data() as Map<String, dynamic>;

        // Pega as estatísticas atuais do estado da tela
        final int goals = _goals[playerId] ?? 0;
        final int assists = _assists[playerId] ?? 0;
        final int yellows = _yellowCards[playerId] ?? 0;
        final int reds = _redCards[playerId] ?? 0;

        // Monta um subtítulo de resumo
        String statsSummary = 'G: $goals, A: $assists, CA: $yellows, CV: $reds';

        return Card(
          child: ListTile(
            title: Text(data['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(statsSummary), // Mostra o resumo
            trailing: const Icon(Icons.edit_note), // Ícone de edição
            onTap: () {
              // Chama o novo pop-up
              _showPlayerStatEditor(player);
            },
          ),
        );
      },
    );
  }

  // --- REMOVIDO: A função _buildStatCounter foi removida daqui ---
  // (Ela agora vive dentro do _showPlayerStatEditor)
}