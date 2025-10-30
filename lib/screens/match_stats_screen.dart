// lib/screens/match_stats_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../widgets/sponsor_banner_rotator.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

class MatchStatsScreen extends StatefulWidget {
  final DocumentSnapshot match;
  const MatchStatsScreen({super.key, required this.match});

  @override
  State<MatchStatsScreen> createState() => _MatchStatsScreenState();
}

class _MatchStatsScreenState extends State<MatchStatsScreen> with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<String, Map<String, dynamic>> _playerDataCache = {};
  bool _isLoadingPlayerData = true;
  String? _manOfTheMatchName;
  int? _manOfTheMatchNumber;
  Map<String, int> _goals = {};
  Map<String, int> _assists = {};
  Map<String, int> _yellows = {};
  Map<String, int> _reds = {};
  String? _manOfTheMatchId;


  late TabController _tabController;
  List<Map<String, dynamic>> _mediaLinks = [];

  VideoPlayerController? _activeVideoPlayerController;
  ChewieController? _activeChewieController;
  String _activeMediaTitle = 'Carregando Mídia...';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _extractStatsAndFetchPlayers();
    _loadMediaLinks();
  }

 @override  
 void dispose() {
    _tabController.dispose();
    _activeVideoPlayerController?.dispose();
    _activeChewieController?.dispose();
    super.dispose();
  }

  // Carrega a lista de mídias do documento do jogo
  void _loadMediaLinks() {
    final data = widget.match.data() as Map<String, dynamic>;
    if (data.containsKey('stats_applied') &&
        data['stats_applied'] != null &&
        data['stats_applied']['media_links'] != null)
    {
      final linksFromDb = data['stats_applied']['media_links'] as List<dynamic>;
      _mediaLinks = List<Map<String, dynamic>>.from(
        linksFromDb.map((item) => Map<String, dynamic>.from(item))
      );
      
      // --- 3. INICIALIZA O PRIMEIRO VÍDEO (se houver mídias) ---
      if (_mediaLinks.isNotEmpty) {
        // Atraso de 1 frame para garantir que o build inicial termine
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
             _changeMediaVideo(
                _mediaLinks.first['videoUrl'],
                _mediaLinks.first['title'],
                autoPlay: false
             );
          }
        });
      }
      // --- FIM ---
    }
    
    // Atualiza o estado (mesmo que a lista esteja vazia)
    if(mounted) setState(() {});
  }

  // --- 4. NOVA FUNÇÃO PARA TROCAR O VÍDEO NO PLAYER ---
  void _changeMediaVideo(String videoUrl, String title, {bool autoPlay = true}) {
    if (!mounted) return;
    
    // Se clicar no vídeo que já está carregado, não faz nada
    if (_activeVideoPlayerController?.dataSource == videoUrl) return;

    debugPrint("Trocando mídia para: $title ($videoUrl)");

    // Limpa os controllers antigos (se existirem)
    _activeVideoPlayerController?.dispose();
    _activeChewieController?.dispose();

    // Cria os novos controllers
    try {
      _activeVideoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
      );
      
      _activeChewieController = ChewieController(
        videoPlayerController: _activeVideoPlayerController!,
        autoPlay: autoPlay,
        looping: false,
        autoInitialize: true,
        aspectRatio: 16 / 9,
        allowFullScreen: true, 
        placeholder: Container(
          color: Colors.black,
          child: const Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
        errorBuilder: (context, errorMessage) {
          return Container(
            color: Colors.black,
            child: Center(
              child: Text('Erro ao carregar vídeo: $errorMessage', style: const TextStyle(color: Colors.white)),
            ),
          );
        },
      );

      // Atualiza a UI para mostrar o novo player e título
      setState(() {
        _activeMediaTitle = title;
      });
    } catch (e) {
       debugPrint("Erro ao criar VideoPlayerController: $e");
       setState(() {
         _activeMediaTitle = "Erro ao carregar vídeo";
         _activeChewieController = null; // Remove o player
       });
    }
  }
  // --- FIM DA FUNÇÃO ---
  // --- 5. FUNÇÃO: CONSTRÓI A ABA DE MÍDIAS (REFEITA) ---
  Widget _buildMediaTab() {
    if (_mediaLinks.isEmpty) {
      return const Center(
        child: Text('Nenhuma mídia (vídeo) disponível para esta partida.'),
      );
    }

    // A lógica de inicialização foi movida para _loadMediaLinks

    return SingleChildScrollView( // Permite rolar a lista de vídeos
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- A. O PLAYER ÚNICO ---
          Card(
            elevation: 3,
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 8.0),
                  child: Container(
                    width: double.infinity, // Força largura total
                    alignment: Alignment.center, // Centraliza o filho
                    child: Text(
                    _activeMediaTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                ),
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: (_activeChewieController == null)
                      // Se nenhum vídeo foi carregado (ou deu erro)
                      ? Container(color: Colors.black, child: const Center(child: CircularProgressIndicator()))
                      // Mostra o player de vídeo ativo
                      : Chewie(controller: _activeChewieController!),
                ),
              ],
            ),
          ),
          // --- FIM DO PLAYER ---

          //const SizedBox(height: 5),
          const Divider(),
          Padding(
             padding: const EdgeInsets.symmetric(vertical: 2.0),
             child: Text('Lista de Reprodução', style: Theme.of(context).textTheme.titleMedium),
          ),

          // --- B. A LISTA DE VÍDEOS (PLAYLIST) ---
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _mediaLinks.length,
            itemBuilder: (context, index) {
              final media = _mediaLinks[index];
              final String title = media['title'] ?? 'Vídeo';
              final String videoUrl = media['videoUrl'];
              
              // Verifica se este item é o que está tocando
              final bool isPlaying = (_activeVideoPlayerController?.dataSource == videoUrl);

              return ListTile(
                dense: true, // Reduz altura
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8.0), // Reduz padding
                visualDensity: VisualDensity.compact, // Mais compacto
                leading: Icon(
                  isPlaying ? Icons.play_circle_fill : Icons.play_circle_outline,
                  color: isPlaying ? Theme.of(context).primaryColor : Colors.grey,
                ),
                title: Text(title, style: TextStyle(fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal, fontSize: 14)),
                selected: isPlaying,
                selectedTileColor: Theme.of(context).primaryColor.withOpacity(0.05),
                onTap: () {
                  _changeMediaVideo(videoUrl, title); // Troca o vídeo ao clicar
                },
              );
            },
          ),
          // --- FIM DA LISTA ---
        ],
      ),
    );
  }
  // --- FIM MEDIA TAB ---
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
      if (_manOfTheMatchId != null &&
          _playerDataCache.containsKey(_manOfTheMatchId)) {
        _manOfTheMatchName =
            _playerDataCache[_manOfTheMatchId]?['name'] ?? 'Não encontrado';
        _manOfTheMatchNumber =
            _playerDataCache[_manOfTheMatchId]?['jersey_number']; // Pega o número
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

  // --- 2. ADICIONE A FUNÇÃO _launchURL ---
  Future<void> _launchURL(String? urlString) async {
    if (urlString == null || urlString.isEmpty) {
      debugPrint('URL da súmula está vazia.');
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Súmula não disponível.')));
      return;
    }
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Não foi possível abrir $urlString');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível abrir o link: $urlString')),
        );
      }
    }
  }
  // --- FIM DA ADIÇÃO --

  // --- FUNÇÃO ATUALIZADA PARA CONSTRUIR COLUNA DE STATS ---
  // --- FUNÇÃO ATUALIZADA PARA ORDENAR E MOSTRAR NOME DO TIME ---
  Widget _buildTeamStatsColumn(
    String teamId,
    String teamName,
    CrossAxisAlignment alignment,
  ) {
    // Listas temporárias para guardar jogadores e permitir ordenação

    // Função auxiliar de ordenação
    void sortPlayersByNumber(List<Map<String, dynamic>> players) {
      players.sort((a, b) {
        final int? aNum = a['number'];
        final int? bNum = b['number'];
        if (aNum != null && bNum != null) {
          return aNum.compareTo(bNum); // 1. Numérico
        } else if (aNum != null && bNum == null) {
          return -1; // 2. Com número vem antes
        } else if (aNum == null && bNum != null) {
          return 1; // 3. Com número vem antes
        } else {
          return a['name'].compareTo(b['name']); // 4. Alfabético
        }
      });
    }

    List<Map<String, dynamic>> goalPlayers =
        []; // Guarda {'name': 'Nome', 'count': Qtd}
    _goals.forEach((playerId, count) {
      if (count > 0 && _playerDataCache[playerId]?['team_id'] == teamId) {
        String name = _playerDataCache[playerId]?['name'] ?? 'Jogador desc.';
        int? number = _playerDataCache[playerId]?['jersey_number'];
        goalPlayers.add({'name': name, 'count': count, 'number': number});
      }
    });
    sortPlayersByNumber(goalPlayers); // Ordena

    List<Map<String, dynamic>> assistPlayers = [];
    _assists.forEach((playerId, count) {
      if (count > 0 && _playerDataCache[playerId]?['team_id'] == teamId) {
        String name = _playerDataCache[playerId]?['name'] ?? 'Jogador desc.';
        int? number = _playerDataCache[playerId]?['jersey_number'];
        assistPlayers.add({'name': name, 'count': count, 'number': number});
      }
    });
    sortPlayersByNumber(assistPlayers); // Ordena

    // Lógica unificada para cartões (coleta dados)
    Map<String, Map<String, int>> playersWithCardsData =
        {}; // { playerId: {'yellow': count, 'red': count} }
    _yellows.forEach((playerId, count) {
      if (count > 0 && _playerDataCache[playerId]?['team_id'] == teamId) {
        playersWithCardsData.putIfAbsent(
          playerId,
          () => {'yellow': 0, 'red': 0},
        );
        playersWithCardsData[playerId]!['yellow'] = count;
      }
    });
    _reds.forEach((playerId, count) {
      if (count > 0 && _playerDataCache[playerId]?['team_id'] == teamId) {
        playersWithCardsData.putIfAbsent(
          playerId,
          () => {'yellow': 0, 'red': 0},
        );
        playersWithCardsData[playerId]!['red'] = count;
      }
    });
    // Converte para lista ordenada para exibição
    List<Map<String, dynamic>> cardPlayers = [];
    playersWithCardsData.forEach((playerId, cardCounts) {
      String name = _playerDataCache[playerId]?['name'] ?? 'Jogador desc.';
      int? number = _playerDataCache[playerId]?['jersey_number'];
      cardPlayers.add({'name': name, 'counts': cardCounts, 'number': number});
    });
    sortPlayersByNumber(cardPlayers); // Ordena

    // Constrói a coluna
    return Column(
      crossAxisAlignment: alignment,
      children: [
        // --- 2. MOSTRAR NOME DO TIME ---
        Padding(
          padding: const EdgeInsets.only(
            bottom: 12.0,
          ), // Aumenta espaço abaixo do nome
          child: SizedBox(
            width: double.infinity,
            child: Text(
              teamName, // Usa o nome do time passado como parâmetro
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        // --- FIM ---

        // Seção Gols (Itera sobre a lista ordenada)
        if (goalPlayers.isNotEmpty) ...[
          _buildStatHeader('Gols', Icons.sports_soccer, alignment),
          ...goalPlayers
              .map(
                (player) => _buildStatItem(
                  name: player['name'],
                  count: player['count'],
                  number: player['number'],
                  alignment: alignment,
                ),
              )
              .toList(), // Constrói widgets a partir da lista ordenada
          const SizedBox(height: 12),
        ],
        // Seção Assists (Itera sobre a lista ordenada)
        /*if (assistPlayers.isNotEmpty) ...[
          _buildStatHeader('Assistências', Icons.assistant, alignment),
          ...assistPlayersr
              .map(
                (player) => _buildStatItem(
                  name: player['name'],
                  count: player['count'],
                  number: player['number'],
                  alignment: alignment,
                ),
              )
              .toList(),
          const SizedBox(height: 12),
        ],*/

        // Seção Cartões (Itera sobre a lista ordenada)
        if (cardPlayers.isNotEmpty) ...[
          _buildStatHeader('Cartões', Icons.style_outlined, alignment),
          ...cardPlayers
              .map(
                (player) => _buildCardStatItem(
                  name: player['name'],
                  cardCounts:
                      player['counts']
                          as Map<String, int>, // Pega o mapa de contagens
                  number: player['number'],
                  alignment: alignment,
                ),
              )
              .toList(),
        ],
      ],
    );
  }
  // --- FIM _buildTeamStatsColumn ---

  // Função _buildStatHeader (sem mudanças)
  Widget _buildStatHeader(
    String title,
    IconData icon,
    CrossAxisAlignment alignment, [
    Color? iconColor,
  ]) {
    // Usa Align para controlar a posição do conteúdo (Row)
    return Align(
      alignment: alignment == CrossAxisAlignment.start
          ? Alignment.centerLeft
          : Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(
          bottom: 4.0,
          left: 8.0,
          right: 8.0,
        ), // Padding lateral
        child: Row(
          mainAxisSize: MainAxisSize.min, // Row encolhe para o conteúdo
          children: [
            // Ordem Ícone/Texto baseada no alinhamento
            if (alignment == CrossAxisAlignment.end) ...[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 6),
              Icon(icon, color: iconColor ?? Colors.black54, size: 16),
            ] else ...[
              Icon(icon, color: iconColor ?? Colors.black54, size: 16),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --- FUNÇÃO _buildStatItem SIMPLIFICADA (só para Gols/Assists) ---
  Widget _buildStatItem({
    required String name,
    required int count,
    required CrossAxisAlignment alignment,
    int? number,
  }) {
    // Formata o nome: "Nº. Nome (Qtd)" ou "-. Nome (Qtd)"
    String numberPrefix = number != null ? '#$number ' : '';
    String countSuffix = (count > 1) ? ' ($count)' : '';
    String displayText = '$numberPrefix$name$countSuffix';

    EdgeInsets itemPadding = alignment == CrossAxisAlignment.start
        ? const EdgeInsets.only(left: 8.0, right: 4.0, bottom: 2.0)
        : const EdgeInsets.only(left: 4.0, right: 8.0, bottom: 2.0);

    // Retorna apenas o texto alinhado
    return Align(
      alignment: alignment == CrossAxisAlignment.start
          ? Alignment.centerLeft
          : Alignment.centerRight,
      child: Padding(
        padding: itemPadding,
        child: Text(
          // Removido Flexible, pode não ser necessário aqui
          displayText,
          style: const TextStyle(fontSize: 14),
          textAlign: alignment == CrossAxisAlignment.start
              ? TextAlign.start
              : TextAlign.end,
        ),
      ),
    );
  }
  // --- FIM _buildStatItem ---

  // --- 3. NOVA FUNÇÃO: CONSTRÓI A ABA DE ESTATÍSTICAS ---
  Widget _buildStatsTab() {
    final data = widget.match.data() as Map<String, dynamic>;
    final homeTeamId = data['team_home_id'] ?? '';
    final awayTeamId = data['team_away_id'] ?? '';
    final homeTeamName = data['team_home_name'] ?? 'Time Casa';
    final awayTeamName = data['team_away_name'] ?? 'Time Visitante';
    //final String? sumulaUrl = data['sumula_url'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        children: [
          // SEÇÃO DE ESTATÍSTICAS (O conteúdo antigo)
          _isLoadingPlayerData
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 8.0,
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildTeamStatsColumn(
                            homeTeamId,
                            homeTeamName,
                            CrossAxisAlignment.start,
                          ),
                        ),
                        Container(width: 1, color: Colors.grey.shade300),
                        Expanded(
                          child: _buildTeamStatsColumn(
                            awayTeamId,
                            awayTeamName,
                            CrossAxisAlignment.end,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

          // CRAQUE DO JOGO (O conteúdo antigo)
          if (_manOfTheMatchName != null && !_isLoadingPlayerData) ...[
            const Divider(
              height: 16,
              thickness: 0.5,
              indent: 16,
              endIndent: 16,
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 8.0),
                child: Card(
                   elevation: 2,
                   child: Padding(
                     padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
                     child: Column(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                         const Icon(Icons.star, color: Colors.amber, size: 30),
                         const SizedBox(height: 8),
                         const Text(
                           'Craque do Jogo',
                           style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                           textAlign: TextAlign.center,
                         ),
                         const SizedBox(height: 4),
                         Text(
                           // Formata com número se existir
                           _manOfTheMatchNumber != null
                             ? '${_manOfTheMatchNumber}. $_manOfTheMatchName'
                             : _manOfTheMatchName!,
                           style: const TextStyle(fontSize: 18),
                           textAlign: TextAlign.center,
                         ),
                       ],
                     ),
                   ),
                 ),
              ),
            ),
          ],

        ],
      ),
    );
  }
  // --- FIM STATS TAB ---

  // --- 6. FUNÇÃO: CONSTRÓI A ABA DE MÍDIAS (REFEITA) ---
   
  // --- FIM MEDIA TAB ---

  // --- NOVA FUNÇÃO AUXILIAR PARA ITEM DE CARTÃO ---
  Widget _buildCardStatItem({
    required String name,
    required Map<String, int> cardCounts, // {'yellow': count, 'red': count}
    required CrossAxisAlignment alignment,
    int? number,
  }) {
    int yellowCount = cardCounts['yellow'] ?? 0;
    int redCount = cardCounts['red'] ?? 0;

    // Formata o nome: "Nº. Nome"
    String numberPrefix = number != null ? '#$number ' : '';
    String displayText = '$numberPrefix$name';

    // Adiciona contagem de amarelos (se > 1)
    if (yellowCount > 1) {
      displayText += ' ($yellowCount)';
    }

    EdgeInsets itemPadding = alignment == CrossAxisAlignment.start
        ? const EdgeInsets.only(left: 8.0, right: 4.0, bottom: 2.0)
        : const EdgeInsets.only(left: 4.0, right: 8.0, bottom: 2.0);

    // Cria a lista de ícones/contadores de cartões
    List<Widget> cardIndicators = [];
    if (yellowCount > 0) {
      cardIndicators.add(
        Icon(Icons.style, size: 16, color: Colors.yellow[700]),
      );
      if (yellowCount > 1) {
        // Adiciona contador se for mais de 1 amarelo
        cardIndicators.add(const SizedBox(width: 2));
        cardIndicators.add(
          Text(
            '($yellowCount)',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        );
      }
    }
    if (redCount > 0) {
      if (cardIndicators.isNotEmpty) {
        // Adiciona espaço se já tiver amarelo
        cardIndicators.add(const SizedBox(width: 5));
      }
      cardIndicators.add(Icon(Icons.style, size: 16, color: Colors.red[700]));
      // Vermelho geralmente é só 1, não precisa de contador
    }

    return Align(
      alignment: alignment == CrossAxisAlignment.start
          ? Alignment.centerLeft
          : Alignment.centerRight,
      child: Padding(
        padding: itemPadding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ordem Nome / Indicadores baseada no alinhamento
            if (alignment == CrossAxisAlignment.end) ...[
              Flexible(
                child: Text(
                  displayText,
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.end,
                ),
              ),
              const SizedBox(width: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: cardIndicators,
              ), // Agrupa indicadores
            ] else ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: cardIndicators,
              ), // Agrupa indicadores
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  displayText,
                  style: const TextStyle(fontSize: 14),
                  textAlign: TextAlign.start,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  // --- FIM _buildCardStatItem ---

  @override
  Widget build(BuildContext context) {
    // ... (extração de dados como antes: scoreHome, scoreAway, ids, nomes, escudos, data) ...
    final data = widget.match.data() as Map<String, dynamic>;
    final scoreHome = data['score_home']?.toString() ?? '-';
    final scoreAway = data['score_away']?.toString() ?? '-';

    final homeTeamName = data['team_home_name'] ?? 'Time Casa';
    final awayTeamName = data['team_away_name'] ?? 'Time Visitante';
    final homeShield = data['team_home_shield'] ?? '';
    final awayShield = data['team_away_shield'] ?? '';
    String formattedDate = 'Data Indisponível';
    if (data['datetime'] != null && data['datetime'] is Timestamp) {
      formattedDate = DateFormat(
        'dd/MM/yyyy HH:mm',
        'pt_BR',
      ).format((data['datetime'] as Timestamp).toDate());
    }
    final String location = data['location'] ?? 'Local a definir';
    final String? sumulaUrl = data['sumula_url'] as String?;

    return DefaultTabController(
      length: 2, // Estatísticas e Mídias
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '$homeTeamName $scoreHome x $scoreAway $awayTeamName',
            overflow: TextOverflow.ellipsis,
          ),
          // Adiciona as Abas
          bottom: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: const [
              Tab(icon: Icon(Icons.bar_chart), text: 'Estatísticas'),
              Tab(icon: Icon(Icons.video_library), text: 'Mídias'),
            ],
          ),
        ),
        body: Column(
          children: [
            // --- Info Cabeçalho (sem mudanças) ---
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (homeShield.isNotEmpty)
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: CachedNetworkImage(
                            imageUrl: homeShield,
                            fit: BoxFit.contain,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Text(
                          '$scoreHome x $scoreAway',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (awayShield.isNotEmpty)
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: CachedNetworkImage(
                            imageUrl: awayShield,
                            fit: BoxFit.contain,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$formattedDate - $location',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
                    textAlign: TextAlign.center,
                  ),

                  // --- 4. ADICIONE O BOTÃO DA SÚMULA AQUI ---
                  if (sumulaUrl != null &&
                      sumulaUrl.isNotEmpty) // Mostra só se a URL existir
                    Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: TextButton.icon(
                        icon: const Icon(Icons.description_outlined, size: 20),
                        label: const Text('Súmula da Partida (PDF)'),
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(
                            context,
                          ).primaryColor, // Cor do texto/ícone
                        ),
                        onPressed: () {
                          _launchURL(sumulaUrl); // Chama a função
                        },
                      ),
                    ),

                  // --- FIM DA ADIÇÃO ---
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1),
            Expanded(
              child: TabBarView(
                controller: _tabController, // Usa o controller
                children: [
                  _buildStatsTab(), // Aba 1
                  _buildMediaTab(), // Aba 2
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: const SponsorBannerRotator(),
      ),
    );
    
    // --- FIM DA ATUALIZAÇÃO ---
  }
  
} // Fim da classe _MatchStatsScreenState