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

  // --- FUNÇÃO QUE FALTAVA ---
  Future<void> _extractStatsAndFetchPlayers() async {
    // Garante que o estado de loading está ativo
    if (mounted) {
      setState(() {
        _isLoadingPlayerData = true;
      });
    }

    // 1. Extrai as estatísticas do documento do jogo
    final data = widget.match.data() as Map<String, dynamic>;
    Map<String, dynamic> statsApplied = {};
    if (data.containsKey('stats_applied') && data['stats_applied'] != null) {
       statsApplied = data['stats_applied'];
    }
    Map<String, dynamic> playerStats = statsApplied['player_stats'] ?? {};
    _manOfTheMatchId = statsApplied['man_of_the_match']; // Define o ID do MotM

    // Preenche os mapas de estatísticas da tela
    _goals = Map<String, int>.from(playerStats['goals'] ?? {});
    _assists = Map<String, int>.from(playerStats['assists'] ?? {});
    _yellows = Map<String, int>.from(playerStats['yellows'] ?? {});
    _reds = Map<String, int>.from(playerStats['reds'] ?? {});
    // Adicionar _goalsConceded se for usar:
    // _goalsConceded = Map<String, int>.from(playerStats['goals_conceded'] ?? {});


    // 2. Coleta todos os IDs de jogadores únicos mencionados
    Set<String> playerIds = {};
    playerIds.addAll(_goals.keys);
    playerIds.addAll(_assists.keys);
    playerIds.addAll(_yellows.keys);
    playerIds.addAll(_reds.keys);
    // playerIds.addAll(_goalsConceded.keys); // Se usar GS
    if (_manOfTheMatchId != null) {
      playerIds.add(_manOfTheMatchId!);
    }
    playerIds.removeWhere((id) => id.isEmpty); // Remove IDs vazios

    // 3. Chama a função para buscar os dados desses jogadores
    // _fetchPlayerData atualizará _isLoadingPlayerData para false no final
    await _fetchPlayerData(playerIds);
  }
  // --- FIM DA FUNÇÃO QUE FALTAVA ---

  // Função para extrair stats do jogo e buscar dados dos jogadores
  Future<void> _fetchPlayerData(Set<String> playerIds) async {
    if (playerIds.isEmpty) {
      if (mounted) setState(() => _isLoadingPlayerData = false);
      return;
    }

    try {
      // Busca documentos dos jogadores cujos IDs estão na lista
      // Firestore limita 'whereIn' a 10 itens por consulta,
      // então dividimos em lotes se necessário.
      List<String> idList = playerIds.toList();
      Map<String, Map<String, dynamic>> fetchedData = {};

      for (int i = 0; i < idList.length; i += 10) {
        int end = (i + 10 < idList.length) ? i + 10 : idList.length;
        List<String> subList = idList.sublist(i, end);

        final snapshot = await _firestore
            .collection('players')
            .where(FieldPath.documentId, whereIn: subList)
            .get();

        for (var doc in snapshot.docs) {
          fetchedData[doc.id] = doc.data();
        }
      }
       _playerDataCache = fetchedData;

       // Busca o nome do Craque do Jogo separadamente se houver ID
       if (_manOfTheMatchId != null && _playerDataCache.containsKey(_manOfTheMatchId)) {
         _manOfTheMatchName = _playerDataCache[_manOfTheMatchId]?['name'] ?? 'Não encontrado';
       }


    } catch (e) {
      debugPrint("Erro ao buscar dados dos jogadores: $e");
      // Tratar erro, talvez mostrando uma mensagem
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPlayerData = false;
        });
      }
    }
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
          child: SizedBox( // Garante que o Text possa ocupar a largura necessária para centralizar
            width: double.infinity,
            child: Text(
              teamName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center, // <-- ADICIONA CENTRALIZAÇÃO AQUI
            ),
        ),
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
     // Usa Align para controlar a posição do conteúdo (Row)
     return Align(
       alignment: alignment == CrossAxisAlignment.start ? Alignment.centerLeft : Alignment.centerRight,
       child: Padding(
         padding: const EdgeInsets.only(bottom: 4.0, left: 8.0, right: 8.0), // Padding lateral
         child: Row(
            mainAxisSize: MainAxisSize.min, // Row encolhe para o conteúdo
            children: [
              // Ordem Ícone/Texto baseada no alinhamento
              if (alignment == CrossAxisAlignment.end) ...[
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  Icon(icon, color: iconColor ?? Colors.black54, size: 16),
              ] else ...[
                  Icon(icon, color: iconColor ?? Colors.black54, size: 16),
                  const SizedBox(width: 6),
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ]
            ],
          ),
       ),
     );
  }

  // --- FUNÇÃO ATUALIZADA PARA ACEITAR ALINHAMENTO ---
  Widget _buildStatItem(String playerName, int count, CrossAxisAlignment alignment, [IconData? cardIcon, Color? cardColor]) {
    String text = playerName;
    // Só adiciona contagem para Gols/Assist (quando não há ícone de cartão)
    if (count > 1 && cardIcon == null) {
      text += ' ($count)';
    }

    // Para cartões, mostra ícone e nome
    if (cardIcon != null) {
      // Usa Align para forçar o alinhamento da Row interna
      return Align(
         alignment: alignment == CrossAxisAlignment.start ? Alignment.centerLeft : Alignment.centerRight,
         child: Padding(
          padding: const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 2.0),
          child: Row(
            mainAxisSize: MainAxisSize.min, // Row encolhe para o conteúdo
            children: [
              // Ordem Ícone/Texto baseada no alinhamento
              if (alignment == CrossAxisAlignment.end) ...[
                // Usar Flexible aqui é importante caso o nome seja muito longo
                Flexible(child: Text(text, style: const TextStyle(fontSize: 14), textAlign: TextAlign.end)),
                const SizedBox(width: 4),
                //Icon(cardIcon, color: cardColor, size: 16),
              ] else ...[
                //Icon(cardIcon, color: cardColor, size: 16),
                const SizedBox(width: 4),
                Flexible(child: Text(text, style: const TextStyle(fontSize: 14), textAlign: TextAlign.start)),
              ]
            ]),
         ),
      );
    }

    // Para gols e assists, só o texto, alinhado com Align
    return Align(
       alignment: alignment == CrossAxisAlignment.start ? Alignment.centerLeft : Alignment.centerRight,
       child: Padding(
         padding: const EdgeInsets.only(left: 8.0, right: 8.0, bottom: 2.0),
         // Usar Flexible + Text com textAlign garante alinhamento correto mesmo com quebra de linha
         child: Flexible(
             child: Text(
               text,
               style: const TextStyle(fontSize: 14),
               textAlign: alignment == CrossAxisAlignment.start ? TextAlign.start : TextAlign.end,
             )
         ),
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
    final String location = data['location'] ?? '';
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
                   Text(
                     '$formattedDate - $location', // Combina as duas
                     style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
                     textAlign: TextAlign.center,
                    ),
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