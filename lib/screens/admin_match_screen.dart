// lib/screens/admin_match_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import '../services/firestore_service.dart';
import '../services/admin_service.dart';

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

  // Mapas de Stats (como antes)
  Map<String, int> _goals = {};
  Map<String, int> _assists = {};
  Map<String, int> _yellowCards = {};
  Map<String, int> _redCards = {};
  Map<String, int> _goalsConceded = {};
  String? _selectedManOfTheMatchId;
  String _selectedStatus = 'pending';

  // Estado para seleção (como antes)
  String? _selectedPlayerId;

  // --- NOVOS ESTADOS PARA DESEMPATE ---
  late TextEditingController _penaltyHomeScoreController;
  late TextEditingController _penaltyAwayScoreController;
  String? _selectedWinnerId; // Para regra de 'standing'
  String _tiebreakerRule = ''; // Regra aplicável a este jogo
  bool _showTiebreakerSection = false; // Controla visibilidade
  // --- FIM ---

  @override
  void initState() {
    // ... (initState como antes, carregando dados) ...
    super.initState();

    final data = widget.match.data() as Map<String, dynamic>;

    _penaltyHomeScoreController = TextEditingController();
    _penaltyAwayScoreController = TextEditingController();

    _penaltyHomeScoreController.text =
        data['penalty_score_home']?.toString() ?? '';
    _penaltyAwayScoreController.text =
        data['penalty_score_away']?.toString() ?? '';

    _homeScoreController = TextEditingController(
      text: data['score_home']?.toString() ?? '',
    )..addListener(_checkShowTiebreakerSection); // Adiciona listener na criação

    _awayScoreController = TextEditingController(
      text: data['score_away']?.toString() ?? '',
    )..addListener(_checkShowTiebreakerSection); // Adiciona listener na criação

    _selectedStatus = data?['status'] ?? 'pending';

    _selectedWinnerId = data['winner_team_id']; // Pode ser null

    if (data.containsKey('stats_applied') && data['stats_applied'] != null) {
      final stats = data['stats_applied']['player_stats'];
      _goals = Map<String, int>.from(stats['goals'] ?? {});
      _assists = Map<String, int>.from(stats['assists'] ?? {});
      _yellowCards = Map<String, int>.from(stats['yellows'] ?? {});
      _redCards = Map<String, int>.from(stats['reds'] ?? {});
      _goalsConceded = Map<String, int>.from(stats['goals_conceded'] ?? {});
      _selectedManOfTheMatchId = data['stats_applied']['man_of_the_match'];
      _penaltyHomeScoreController.text = data['penalty_score_home']?.toString() ?? '';
      _penaltyAwayScoreController.text = data['penalty_score_away']?.toString() ?? '';
      _selectedWinnerId = data['winner_team_id'];
    }

    // --- Determina a regra de desempate para ESTE jogo ---
    final String phase = data['phase'] ?? '';
    if (phase == 'semifinal')
      _tiebreakerRule = AdminService.semifinalTiebreaker;
    else if (phase == 'third_place')
      _tiebreakerRule = AdminService.thirdPlaceTiebreaker;
    else if (phase == 'final')
      _tiebreakerRule = AdminService.finalTiebreaker;
    // --- FIM ---

    

    _fetchPlayers();
    _checkShowTiebreakerSection(); // Verifica se precisa mostrar seção de desempate
  }

  // --- NOVA FUNÇÃO: VERIFICA SE MOSTRA SEÇÃO DESEMPATE ---
  void _checkShowTiebreakerSection() {
    bool needsTiebreaker = false;
    // Só mostra se for mata-mata, finalizado e empatado
    final isPlayoff = [
      'semifinal',
      'third_place',
      'final',
    ].contains(widget.match['phase']);
    if (isPlayoff && _selectedStatus == 'finished') {
      final int scoreHome = int.tryParse(_homeScoreController.text) ?? -1;
      final int scoreAway = int.tryParse(_awayScoreController.text) ?? -1;
      if (scoreHome != -1 && scoreAway != -1 && scoreHome == scoreAway) {
        needsTiebreaker = true;
      }
    }
    // Atualiza estado (se mudou)
    if (needsTiebreaker != _showTiebreakerSection) {
      setState(() {
        _showTiebreakerSection = needsTiebreaker;
      });
    }
  }
  // --- FIM ---

  Future<void> _fetchPlayers() async {
    // Busca jogadores (como antes)
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

      setState(() {
        _isLoadingPlayers = false;
      });
    } catch (e) {
      debugPrint('Erro ao buscar jogadores: $e');
      setState(() {
        _isLoadingPlayers = false;
      });
    } finally {
      if (mounted) setState(() => _isLoadingPlayers = false);
    }
  }

  

  // --- WIDGET EDITOR (AGORA RECEBE playerDoc) ---
  Widget _buildStatEditor(DocumentSnapshot playerDoc) {
    // Não precisa mais verificar _selectedPlayerData == null
    final playerId = playerDoc.id;
    final data = playerDoc.data() as Map<String, dynamic>;
    final bool isGoalkeeper = data['is_goalkeeper'] ?? false;

    int currentGoals = _goals[playerId] ?? 0;
    int currentAssists = _assists[playerId] ?? 0;
    int currentYellows = _yellowCards[playerId] ?? 0;
    int currentReds = _redCards[playerId] ?? 0;
    int currentGoalsConceded = _goalsConceded[playerId] ?? 0;

    // Retorna o Card diretamente
    return Card(
      margin: const EdgeInsets.only(
        top: 0,
        left: 8.0,
        right: 8.0,
        bottom: 8.0,
      ), // Margem ajustada
      elevation: 2,
      color: Colors.blueGrey[50]?.withOpacity(
        0.8,
      ), // Fundo levemente transparente
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Não precisa mais do cabeçalho com nome e botão fechar
            _buildStatCounter(
              icon: Icons.sports_soccer,
              label: "Gols",
              count: currentGoals,
              onAdd: () => setState(() => _goals[playerId] = currentGoals + 1),
              onRemove: () => setState(
                () => _goals[playerId] = (currentGoals > 0)
                    ? currentGoals - 1
                    : 0,
              ),
            ),
            _buildStatCounter(
              icon: Icons.assistant,
              label: "Assist.",
              count: currentAssists,
              onAdd: () =>
                  setState(() => _assists[playerId] = currentAssists + 1),
              onRemove: () => setState(
                () => _assists[playerId] = (currentAssists > 0)
                    ? currentAssists - 1
                    : 0,
              ),
            ),
            _buildStatCounter(
              icon: Icons.style,
              label: "CA",
              color: Colors.yellow[700],
              count: currentYellows,
              onAdd: () =>
                  setState(() => _yellowCards[playerId] = currentYellows + 1),
              onRemove: () => setState(
                () => _yellowCards[playerId] = (currentYellows > 0)
                    ? currentYellows - 1
                    : 0,
              ),
            ),
            _buildStatCounter(
              icon: Icons.style,
              label: "CV",
              color: Colors.red[700],
              count: currentReds,
              onAdd: () => setState(
                () => _redCards[playerId] = 1,
              ), // Só pode ter 1 vermelho
              onRemove: () => setState(() => _redCards[playerId] = 0),
            ),
            // Contador GS (só para goleiro)
            if (isGoalkeeper)
              _buildStatCounter(
                icon: Icons.shield_outlined,
                label: "GS",
                color: Colors.blueGrey,
                count: currentGoalsConceded,
                onAdd: () => setState(
                  () => _goalsConceded[playerId] = currentGoalsConceded + 1,
                ),
                onRemove: () => setState(
                  () => _goalsConceded[playerId] = (currentGoalsConceded > 0)
                      ? currentGoalsConceded - 1
                      : 0,
                ),
              ),
          ],
        ),
      ),
    );
  }
  // --- FIM _buildStatEditor ---

  // Função _buildStatCounter (como antes)
  Widget _buildStatCounter({
    required IconData icon,
    required String label,
    required int count,
    required VoidCallback onAdd,
    required VoidCallback onRemove,
    Color? color,
  }) {
    return Padding(
      // Adiciona padding entre os contadores
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(width: 10),
              Text('$label:', style: const TextStyle(fontSize: 15)),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.remove_circle,
                  size: 26,
                  color: Colors.red,
                ),
                onPressed: onRemove,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              SizedBox(
                // Largura mínima para o número
                width: 30,
                child: Text(
                  count.toString(),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.add_circle,
                  size: 26,
                  color: Colors.green,
                ),
                onPressed: onAdd,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }
  // --- FIM _buildStatCounter ---

  @override
  Widget build(BuildContext context) {
    // ... (allPlayers, data, team names) ...
    final List<DocumentSnapshot> allPlayers = [
      ..._homePlayers,
      ..._awayPlayers,
    ];
    final data = widget.match.data() as Map<String, dynamic>;
    final homeTeamName = data['team_home_name'] ?? 'Casa';
    final awayTeamName = data['team_away_name'] ?? 'Visitante';

    // --- ORDENA AS LISTAS DE JOGADORES ---
    _homePlayers.sort(
      (a, b) => (a.data() as Map<String, dynamic>)['name'].compareTo(
        (b.data() as Map<String, dynamic>)['name'],
      ),
    );
    _awayPlayers.sort(
      (a, b) => (a.data() as Map<String, dynamic>)['name'].compareTo(
        (b.data() as Map<String, dynamic>)['name'],
      ),
    );
    // --- FIM DA ORDENAÇÃO ---

    return Scaffold(
      appBar: AppBar(
        title: Text('$homeTeamName x $awayTeamName'),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(color: Colors.white),
            )
          else
            IconButton(icon: const Icon(Icons.save), onPressed: _saveStats),
        ],
      ),
      body: _isLoadingPlayers
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildScoreCard(),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 4.0,
                      ),
                      child: DropdownButtonFormField<String>(
                        value: _selectedStatus,
                        items: const [
                          DropdownMenuItem(
                            value: 'pending',
                            child: Text('Pendente'),
                          ),
                          DropdownMenuItem(
                            value: 'in_progress',
                            child: Text('Em Andamento'),
                          ), // Ícone simples de live
                          DropdownMenuItem(
                            value: 'finished',
                            child: Text('Finalizado'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _selectedStatus = value);
                            _checkShowTiebreakerSection(); // Verifica ao mudar status
                          }
                          ;
                        },
                      ),
                    ),
                  ),

                  // --- SEÇÃO DE DESEMPATE (CONDICIONAL) ---
                  if (_showTiebreakerSection)
                    _buildTiebreakerSection(), // Chama nova função
                  // --- FIM ---
                  //decoration: const InputDecoration(
                  //labelText: 'Status da Partida',
                  //border: InputBorder.none, // Remove linha inferior
                  //),
                  //),
                  //),
                  //),
                  const SizedBox(height: 24),

                  // Listas de Jogadores
                  Text(
                    homeTeamName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  _buildPlayerSelectList(
                    _homePlayers,
                  ), // Chama a função modificada
                  const SizedBox(height: 20),
                  Text(
                    awayTeamName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  _buildPlayerSelectList(
                    _awayPlayers,
                  ), // Chama a função modificada

                  const SizedBox(height: 24),
                  Text(
                    'Craque do Jogo',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (allPlayers.isNotEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: DropdownButtonFormField<String>(
                          value: _selectedManOfTheMatchId,
                          hint: const Text('Selecione o jogador'),
                          isExpanded: true,
                          items: allPlayers.map((player) {
                            final data = player.data() as Map<String, dynamic>;
                            return DropdownMenuItem<String>(
                              value: player.id,
                              child: Text(
                                '${data['name']} (${data['team_name']})',
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedManOfTheMatchId = value;
                            });
                          },
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    )
                  else
                    const Text('Carregando jogadores...'),
                ],
              ),
            ),
    );
  } // Fim build()

  // --- NOVO WIDGET PARA SEÇÃO DE DESEMPATE ---
  Widget _buildTiebreakerSection() {
    final homeTeamId = widget.match['team_home_id'];
    final homeTeamName = widget.match['team_home_name'] ?? 'Casa';
    final awayTeamId = widget.match['team_away_id'];
    final awayTeamName = widget.match['team_away_name'] ?? 'Visitante';

    return Card(
      margin: const EdgeInsets.only(top: 16.0),
      color: Colors.amber[50],
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Desempate Necessário!',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red[700],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Regra: ${_getTiebreakerRuleName(_tiebreakerRule)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),

            // Campos de Pênaltis (Condicional)
            if (_tiebreakerRule.contains('penalties')) ...[
              Text(
                'Placar Pênaltis:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Text(homeTeamName),
                  SizedBox(
                    width: 50,
                    child: TextField(
                      controller: _penaltyHomeScoreController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(hintText: 'P'),
                    ),
                  ),
                  const Text('x'),
                  SizedBox(
                    width: 50,
                    child: TextField(
                      controller: _penaltyAwayScoreController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(hintText: 'P'),
                    ),
                  ),
                  Text(awayTeamName),
                ],
              ),
            ],

            if (_tiebreakerRule == 'extra_time_standing')
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'O vencedor será determinado automaticamente pela classificação da 1ª Fase ao gerar a Final/3º Lugar.',
                  style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey[700]),
                ),
              ),
          ],
        ),
      ),
    );
  }
  // --- FIM ---

  Future<void> _saveStats() async {
    final int scoreHome = int.tryParse(_homeScoreController.text) ?? 0;
    final int scoreAway = int.tryParse(_awayScoreController.text) ?? 0;
    // Validação de Status vs Placar (como antes)
    if (_selectedStatus == 'finished' &&
        (_homeScoreController.text.isEmpty ||
            _awayScoreController.text.isEmpty ||
            int.tryParse(_homeScoreController.text) == null ||
            int.tryParse(_awayScoreController.text) == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Placar válido é obrigatório para jogos finalizados.'),
        ),
      );
      return;
    }

    // --- VALIDAÇÃO DE DESEMPATE ---
    int? penaltyScoreHome;
    int? penaltyScoreAway;
    String? winnerId; // Usa o estado

    if (_showTiebreakerSection) {
      // Se a seção está visível (empate em jogo finalizado)
      if (_tiebreakerRule.contains('penalties')) {
        penaltyScoreHome = int.tryParse(_penaltyHomeScoreController.text);
        penaltyScoreAway = int.tryParse(_penaltyAwayScoreController.text);
        if (penaltyScoreHome == null || penaltyScoreAway == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Placar dos pênaltis é obrigatório.')),
          );
          return;
        }
        if (penaltyScoreHome == penaltyScoreAway) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Placar dos pênaltis não pode ser empate.'),
            ),
          );
          return;
        }
        // Define o vencedor com base nos pênaltis
        winnerId = (penaltyScoreHome > penaltyScoreAway)
            ? widget.match['team_home_id']
            : widget.match['team_away_id'];
      } else if (_tiebreakerRule == 'extra_time_standing') {

        penaltyScoreHome = null;
        penaltyScoreAway = null;
        winnerId = null;
      }
    } else {
      // Se não precisou de desempate, garante que os campos extras são nulos
      penaltyScoreHome = null;
      penaltyScoreAway = null;
      winnerId = null;
    }
    // --- FIM VALIDAÇÃO DESEMPATE ---

    setState(() {
      _isSaving = true;
    });

    String result = await _firestoreService.updateMatchStats(
      matchSnapshot: widget.match,
      newStatus: _selectedStatus,
      newScoreHome: scoreHome,
      newScoreAway: scoreAway,
      newGoals: _goals,
      newAssists: _assists,
      newYellows: _yellowCards,
      newReds: _redCards,
      newGoalsConceded: _goalsConceded,
      newManOfTheMatchId: _selectedManOfTheMatchId,
      penaltyScoreHome: penaltyScoreHome,
      penaltyScoreAway: penaltyScoreAway,
      winnerTeamId: winnerId,
    );
    
    setState(() {
      _isSaving = false;
    });

    if (result == "Sucesso") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Estatísticas salvas com sucesso!')),
      );
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: $result', maxLines: 5)),
      );
    }
  }

  // Helper para nome da regra
  String _getTiebreakerRuleName(String ruleKey) {
    switch (ruleKey) {
      case 'penalties':
        return 'Pênaltis Direto';
      case 'extra_time_penalties':
        return 'Prorrogação + Pênaltis';
      case 'extra_time_standing':
        return 'Prorrogação + Melhor Classif.';
      default:
        return 'Desconhecida';
    }
  }

  @override
  void dispose() {
    // --- REMOVE LISTENERS E DISPÕE CONTROLLERS ---
    _homeScoreController.removeListener(_checkShowTiebreakerSection);
    _awayScoreController.removeListener(_checkShowTiebreakerSection);
    _homeScoreController.dispose();
    _awayScoreController.dispose();
    _penaltyHomeScoreController.dispose();
    _penaltyAwayScoreController.dispose();
    // --- FIM ---
    super.dispose();
  }

  Widget _buildScoreCard() {
    // A UI do Card permanece a mesma
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Expanded(
              child: Text(
                widget.match['team_home_name'] ?? 'Casa',
                style: const TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(
              width: 60,
              child: TextField(
                controller: _homeScoreController, // Já tem o listener anexado
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(border: OutlineInputBorder()),
                // Chama a verificação também quando o foco muda (opcional, mas seguro)
                onTapOutside: (_) => _checkShowTiebreakerSection(),
                onEditingComplete: _checkShowTiebreakerSection,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: Text('x'),
            ),
            SizedBox(
              width: 60,
              child: TextField(
                controller: _awayScoreController, // Já tem o listener anexado
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(border: OutlineInputBorder()),
                onTapOutside: (_) => _checkShowTiebreakerSection(),
                onEditingComplete: _checkShowTiebreakerSection,
              ),
            ),
            Expanded(
              child: Text(
                widget.match['team_away_name'] ?? 'Visitante',
                style: const TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
  // --- FIM _buildScoreCard ---

  // --- FUNÇÃO ATUALIZADA PARA LISTA COM EDITOR EMBUTIDO ---
  Widget _buildPlayerSelectList(List<DocumentSnapshot> players) {
    if (players.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Text(
          'Nenhum jogador encontrado para este time.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: players.length,
      itemBuilder: (context, index) {
        final player = players[index];
        final playerId = player.id;
        final data = player.data() as Map<String, dynamic>;
        final bool isSelected = _selectedPlayerId == playerId;
        // Monta resumo de stats para o subtitle
        final statsSummary =
            'G:${_goals[playerId] ?? 0} A:${_assists[playerId] ?? 0} '
            'CA:${_yellowCards[playerId] ?? 0} CV:${_redCards[playerId] ?? 0}'
            '${(data['is_goalkeeper'] ?? false) ? ' GS:${_goalsConceded[playerId] ?? 0}' : ''}';

        // --- Retorna uma Column: ListTile + Editor (Condicional) ---
        return Column(
          children: [
            // O ListTile clicável (como antes, mas ajusta a cor/elevação)
            Card(
              margin: const EdgeInsets.symmetric(
                vertical: 2.0,
              ), // Margem vertical menor
              color: isSelected
                  ? Colors.lightBlue[50]
                  : null, // Cor de fundo mais sutil
              elevation: isSelected ? 3 : 1,
              child: ListTile(
                dense: true,
                leading: Icon(
                  data['is_goalkeeper'] == true
                      ? Icons.shield_outlined
                      : Icons.person_outline,
                ),
                title: Text(
                  data['name'] ?? '...',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  statsSummary,
                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                ),
                // Não precisa mais do ícone de edição no trailing
                // trailing: isSelected ? const Icon(Icons.edit, color: Colors.blue) : null,
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedPlayerId = null; // Deseleciona
                    } else {
                      _selectedPlayerId = playerId; // Seleciona
                    }
                    // _selectedPlayerData não é mais necessário aqui
                  });
                },
              ),
            ),

            // --- Editor Condicional ---
            // Usa AnimatedSize para uma transição suave ao aparecer/desaparecer
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: isSelected
                  ? _buildStatEditor(player) // Chama o editor se selecionado
                  : const SizedBox.shrink(), // Widget vazio se não selecionado
            ),
            // --- FIM Editor Condicional ---
          ],
        );
        // --- FIM da Column ---
      },
    );
  }
  // --- FIM _buildPlayerSelectList ---
} // Fim da classe _AdminMatchScreenState

// Cole aqui as implementações de _buildScoreCard, Dropdown Craque do Jogo, etc.
