// lib/screens/match_stats_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../widgets/sponsor_banner_rotator.dart';

class MatchStatsScreen extends StatefulWidget {
  final DocumentSnapshot match;
  const MatchStatsScreen({super.key, required this.match});

  @override
  State<MatchStatsScreen> createState() => _MatchStatsScreenState();
}

class _MatchStatsScreenState extends State<MatchStatsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<String, Map<String, dynamic>> _playerDataCache = {};
  bool _isLoadingPlayerData = true;
  String? _manOfTheMatchName;
  Map<String, int> _goals = {};
  Map<String, int> _assists = {};
  Map<String, int> _yellows = {};
  Map<String, int> _reds = {};
  String? _manOfTheMatchId;

  @override
  void initState() {
    super.initState();
    _extractStatsAndFetchPlayers();
  }

  // Função _extractStatsAndFetchPlayers (sem mudanças)
  Future<void> _extractStatsAndFetchPlayers() async {
    // ... (código como antes) ...
  }

  // Função _fetchPlayerData (sem mudanças)
  Future<void> _fetchPlayerData(Set<String> playerIds) async {
    // ... (código como antes) ...
  }


  // --- FUNÇÃO ATUALIZADA PARA ACEITAR ALINHAMENTO ---
  Widget _buildTeamStatsColumn(String teamId, String teamName, CrossAxisAlignment alignment) {
    // Listas para guardar os widgets de cada estatística
    List<Widget> goalWidgets = [];
    _goals.forEach((playerId, count) {
      if (_playerDataCache[playerId]?['team_id'] == teamId) {
        String name = _playerDataCache[playerId]?['name'] ?? 'Jogador desc.';
        goalWidgets.add(_buildStatItem(name, count, alignment)); // Passa o alinhamento
      }
    });

    List<Widget> assistWidgets = [];
    _assists.forEach((playerId, count) {
      if (_playerDataCache[playerId]?['team_id'] == teamId) {
        String name = _playerDataCache[playerId]?['name'] ?? 'Jogador desc.';
        assistWidgets.add(_buildStatItem(name, count, alignment)); // Passa o alinhamento
      }
    });

     List<Widget> yellowWidgets = [];
    _yellows.forEach((playerId, count) {
      if (_playerDataCache[playerId]?['team_id'] == teamId) {
        String name = _playerDataCache[playerId]?['name'] ?? 'Jogador desc.';
        yellowWidgets.add(_buildStatItem(name, count, alignment, Icons.style, Colors.yellow[700])); // Passa o alinhamento
      }
    });

     List<Widget> redWidgets = [];
    _reds.forEach((playerId, count) {
      if (_playerDataCache[playerId]?['team_id'] == teamId) {
        String name = _playerDataCache[playerId]?['name'] ?? 'Jogador desc.';
        redWidgets.add(_buildStatItem(name, 0, alignment, Icons.style, Colors.red[700])); // Passa o alinhamento
      }
    });


    return Column(
      // --- USA O PARÂMETRO DE ALINHAMENTO ---
      crossAxisAlignment: alignment,
      // --- FIM ---
      children: [
        // Mostra o nome do time alinhado
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Text(teamName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),

        // --- GOLS ---
        if (goalWidgets.isNotEmpty) ...[
          _buildStatHeader('Gols', Icons.sports_soccer, alignment), // Passa alinhamento
          ...goalWidgets,
          const SizedBox(height: 12),
        ],
        // --- ASSISTÊNCIAS ---
        if (assistWidgets.isNotEmpty) ...[
          _buildStatHeader('Assistências', Icons.assistant, alignment), // Passa alinhamento
          ...assistWidgets,
           const SizedBox(height: 12),
        ],
         // --- AMARELOS ---
        if (yellowWidgets.isNotEmpty) ...[
          _buildStatHeader('Cartões Amarelos', Icons.style, alignment, Colors.yellow[700]), // Passa alinhamento
          ...yellowWidgets,
           const SizedBox(height: 12),
        ],
         // --- VERMELHOS ---
        if (redWidgets.isNotEmpty) ...[
          _buildStatHeader('Cartões Vermelhos', Icons.style, alignment, Colors.red[700]), // Passa alinhamento
          ...redWidgets,
        ],
      ],
    );
  }

  // --- FUNÇÃO ATUALIZADA PARA ACEITAR ALINHAMENTO ---
  Widget _buildStatHeader(String title, IconData icon, CrossAxisAlignment alignment, [Color? iconColor]) {
     // A Row agora ocupa o espaço, o alinhamento da Column externa controla a posição
     return Padding(
       padding: const EdgeInsets.only(bottom: 4.0),
       child: Row(
          // O MainAxisAlignment depende do alinhamento geral da coluna
          mainAxisAlignment: alignment == CrossAxisAlignment.start ? MainAxisAlignment.start : MainAxisAlignment.end,
          children: [
            // Reordena ícone e texto para o alinhamento à direita
            if (alignment == CrossAxisAlignment.end) ...[
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                Icon(icon, color: iconColor ?? Colors.black54, size: 18),
            ] else ...[
                Icon(icon, color: iconColor ?? Colors.black54, size: 18),
                const SizedBox(width: 6),
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ]
          ],
        ),
     );
  }

  // --- FUNÇÃO ATUALIZADA PARA ACEITAR ALINHAMENTO ---
  Widget _buildStatItem(String playerName, int count, CrossAxisAlignment alignment, [IconData? cardIcon, Color? cardColor]) {
    String text = playerName;
    if (count > 1 && cardIcon == null) { // Só adiciona (count) para gols/assists
      text += ' ($count)';
    }

    // Para cartões, mostra ícone e nome
    if (cardIcon != null) {
      return Padding(
        padding: const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 2.0),
        child: Row(
          mainAxisAlignment: alignment == CrossAxisAlignment.start ? MainAxisAlignment.start : MainAxisAlignment.end,
          children: [
            // Reordena para alinhamento à direita
            if (alignment == CrossAxisAlignment.end) ...[
              Flexible(child: Text(text, style: const TextStyle(fontSize: 14), textAlign: TextAlign.end)), // Garante quebra de linha à direita
              const SizedBox(width: 4),
              Icon(cardIcon, color: cardColor, size: 16),
            ] else ...[
              Icon(cardIcon, color: cardColor, size: 16),
              const SizedBox(width: 4),
              Flexible(child: Text(text, style: const TextStyle(fontSize: 14))), // Garante quebra de linha à esquerda
            ]
          ]),
      );
    }

    // Para gols e assists, só o texto, alinhado
    return Padding(
       padding: const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 2.0),
       // Define a largura máxima e alinha o texto
       child: Container(
         alignment: alignment == CrossAxisAlignment.start ? Alignment.centerLeft : Alignment.centerRight,
         child: Text(text, style: const TextStyle(fontSize: 14)),
       ),
    );
  }


  @override
  Widget build(BuildContext context) {
    // ... (extração de dados como antes: scoreHome, scoreAway, ids, nomes, escudos, data) ...
    final data = widget.match.data() as Map<String, dynamic>;
    final scoreHome = data['score_home']?.toString() ?? '-';
    final scoreAway = data['score_away']?.toString() ?? '-';
    final homeTeamId = data['team_home_id'] ?? '';
    final awayTeamId = data['team_away_id'] ?? '';
    final homeTeamName = data['team_home_name'] ?? 'Time Casa';
    final awayTeamName = data['team_away_name'] ?? 'Time Visitante';
    final homeShield = data['team_home_shield'] ?? '';
    final awayShield = data['team_away_shield'] ?? '';
    String formattedDate = 'Data Indisponível';
    if (data['datetime'] != null && data['datetime'] is Timestamp) {
      formattedDate = DateFormat('dd/MM/yyyy HH:mm').format((data['datetime'] as Timestamp).toDate());
    }


    return Scaffold(
      appBar: AppBar(
        title: Text('$homeTeamName $scoreHome x $scoreAway $awayTeamName', overflow: TextOverflow.ellipsis),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: Column(
          children: [
            // --- Info Cabeçalho (sem mudanças) ---
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                       if (homeShield.isNotEmpty) Image.network(homeShield, height: 40),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Text(
                          '$scoreHome x $scoreAway',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                       if (awayShield.isNotEmpty) Image.network(awayShield, height: 40),
                    ],
                  ),
                   const SizedBox(height: 8),
                   Text(formattedDate, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1),

            // --- SEÇÃO DE ESTATÍSTICAS ---
            _isLoadingPlayerData
                ? const Padding( // Loading enquanto busca jogadores
                    padding: EdgeInsets.symmetric(vertical: 40.0),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                    child: IntrinsicHeight(
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // --- Coluna Time da Casa (Alinhada à Esquerda) ---
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                // Passa o alinhamento start
                                child: _buildTeamStatsColumn(homeTeamId, homeTeamName, CrossAxisAlignment.start),
                              ),
                            ),
                            // --- Linha Divisória (sem mudanças) ---
                            Container(width: 1, color: const Color.fromARGB(255, 39, 39, 39)),
                            // --- Coluna Time Visitante (Alinhada à Direita) ---
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                // Passa o alinhamento end
                                child: _buildTeamStatsColumn(awayTeamId, awayTeamName, CrossAxisAlignment.end),
                              ),
                            ),
                          ],
                      ),
                    )
                  ),

            // --- MOVER CRAQUE DO JOGO PARA CÁ ---
            if (_manOfTheMatchName != null && !_isLoadingPlayerData) ...[ // Só mostra se não estiver carregando
              const Divider(height: 1, thickness: 1), // Divisor opcional
              Center( // Mantém o Card centralizado
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
                  child: Card(
                     elevation: 2,
                     child: Padding( // Adiciona padding interno ao Card
                       padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
                       child: Column( // Usa Column para centralizar o conteúdo
                         mainAxisSize: MainAxisSize.min, // Encolhe na vertical
                         children: [
                           const Icon(Icons.star, color: Colors.amber, size: 30),
                           const SizedBox(height: 8), // Espaço entre ícone e texto
                           const Text(
                             'Craque do Jogo',
                             style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                             textAlign: TextAlign.center, // Garante centralização do texto
                           ),
                           const SizedBox(height: 4), // Espaço entre textos
                           Text(
                             _manOfTheMatchName!,
                             style: const TextStyle(fontSize: 18), // Fonte maior para o nome
                             textAlign: TextAlign.center, // Garante centralização do texto
                           ),
                         ],
                       ),
                     ),
                   ),
                ),
              ),
            ],
            // --- FIM DA MOVIMENTAÇÃO ---

             // --- Banner ---
             const SizedBox(height: 32),
             Padding(
               padding: const EdgeInsets.symmetric(horizontal: 16.0),
               child: Text('Patrocinadores', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
             ),
             const SizedBox(height: 8),
             const SponsorBannerRotator(),
          ],
        ),
      ),
    );
  }
} // Fim da classe _MatchStatsScreenState