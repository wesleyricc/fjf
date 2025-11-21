// lib/screens/match_stats_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/sponsor_banner_rotator.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'player_profile_screen.dart';

// --- IMPORTS DE COMPARTILHAMENTO ATUALIZADOS (PWA FRIENDLY) ---
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:typed_data'; // Necessário para Uint8List
// NOTA: Removemos 'dart:io' e 'path_provider' para funcionar na Web
import '../widgets/match_result_card.dart';

class MatchStatsScreen extends StatefulWidget {
  final DocumentSnapshot match;
  const MatchStatsScreen({super.key, required this.match});

  @override
  State<MatchStatsScreen> createState() => _MatchStatsScreenState();
}

class _MatchStatsScreenState extends State<MatchStatsScreen> with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScreenshotController _screenshotController = ScreenshotController();

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

    try {
      final data = widget.match.data() as Map<String, dynamic>? ?? {};
      final String homeName = data['team_home_name'] ?? 'Casa';
      final String awayName = data['team_away_name'] ?? 'Fora';
      FirebaseAnalytics.instance.logScreenView(
        screenName: '/match/stats/$homeName-vs-$awayName',
      );
    } catch (e) {
      debugPrint("Erro ao logar screen_view (MatchStatsScreen): $e");
    }
  }

 @override  
 void dispose() {
    _tabController.dispose();
    _activeVideoPlayerController?.dispose();
    _activeChewieController?.dispose();
    super.dispose();
  }

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
      
      if (_mediaLinks.isNotEmpty) {
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
    }
    if(mounted) setState(() {});
  }

  void _changeMediaVideo(String videoUrl, String title, {bool autoPlay = true}) {
    if (!mounted) return;
    if (_activeVideoPlayerController?.dataSource == videoUrl) return;

    _activeVideoPlayerController?.dispose();
    _activeChewieController?.dispose();

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

      setState(() {
        _activeMediaTitle = title;
      });
    } catch (e) {
       debugPrint("Erro ao criar VideoPlayerController: $e");
       setState(() {
         _activeMediaTitle = "Erro ao carregar vídeo";
         _activeChewieController = null;
       });
    }
  }

  // --- FUNÇÃO ATUALIZADA PARA PWA (WEB) ---
  Future<void> _shareMatchCard() async {
    final data = widget.match.data() as Map<String, dynamic>;
    final homeName = data['team_home_name'] ?? 'Casa';
    final awayName = data['team_away_name'] ?? 'Fora';
    final homeId = data['team_home_id'];
    final awayId = data['team_away_id'];
    final homeShield = data['team_home_shield'] ?? '';
    final awayShield = data['team_away_shield'] ?? '';
    final scoreHome = data['score_home']?.toString() ?? '-';
    final scoreAway = data['score_away']?.toString() ?? '-';
    final location = data['location'] ?? '';
    
    String dateStr = '';
    if (data['datetime'] != null) {
      dateStr = DateFormat('dd/MM/yyyy HH:mm').format((data['datetime'] as Timestamp).toDate());
    }

    // --- NOVA LÓGICA: Preparar lista de autores dos gols ---

    final String phase = data['phase'] ?? 'first';
    final int round = data['round'] ?? 0;
    
    String calculatedLabel = 'JOGO'; // Padrão
    
    if (phase == 'first') {
      calculatedLabel = '${round}ª RODADA';
    } else if (phase == 'semifinal') {
      calculatedLabel = 'SEMIFINAL';
    } else if (phase == 'third_place') {
      calculatedLabel = 'DISPUTA 3º LUGAR';
    } else if (phase == 'final') {
      calculatedLabel = 'GRANDE FINAL';
    }
    List<String> homeScorersList = [];
    List<String> awayScorersList = [];

    // Verifica se os dados dos jogadores já foram carregados no cache
    if (!_isLoadingPlayerData && _goals.isNotEmpty) {
      _goals.forEach((playerId, count) {
        if (count > 0 && _playerDataCache.containsKey(playerId)) {
          final playerData = _playerDataCache[playerId]!;
          final String rawName = playerData['name'] ?? 'Desconhecido';
          
          // Tenta encurtar o nome (Primeiro e Último) para caber melhor no card
          List<String> nameParts = rawName.trim().split(' ');
          String shortName = rawName;
          if (nameParts.length > 1) {
             shortName = "${nameParts[0]} ${nameParts.last}";
          }

          // Formata: "Nome (Qtd)" se for mais de 1 gol, senão só "Nome"
          String scorerText = count > 1 ? "$shortName ($count)" : shortName;
          
          // Adiciona na lista correta baseado no ID do time do jogador
          if (playerData['team_id'] == homeId) {
            homeScorersList.add(scorerText);
          } else if (playerData['team_id'] == awayId) {
            awayScorersList.add(scorerText);
          }
        }
      });
    }
    // -------------------------------------------------------

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Envolve o card no Screenshot para capturar
            Screenshot(
              controller: _screenshotController,
              child: MatchResultCard(
                homeName: homeName,
                awayName: awayName,
                homeShield: homeShield,
                awayShield: awayShield,
                scoreHome: scoreHome,
                scoreAway: scoreAway,
                date: dateStr,
                location: location,
                // Passa as novas listas para o card
                homeScorers: homeScorersList,
                awayScorers: awayScorersList,
                matchLabel: calculatedLabel,
              ),
            ),
            const SizedBox(height: 16),
            // ... (resto do botão de compartilhar igual ao anterior)
            ElevatedButton.icon(
              icon: const Icon(Icons.share),
              label: const Text('Compartilhar'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
              onPressed: () async {
                final Uint8List? imageBytes = await _screenshotController.capture(pixelRatio: 4.0);
                if (imageBytes != null) {
                  if (mounted) Navigator.of(ctx).pop();
                  final XFile file = XFile.fromData(imageBytes, mimeType: 'image/png', name: 'resultado_jogo.png');
                  try {
                    await Share.shareXFiles([file], text: 'Confira o resultado do jogo! #FJF2025');
                  } catch (e) {
                     // Tratamento de erro PWA
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
  // ----------------------------------------

  Widget _buildMediaTab() {
    if (_mediaLinks.isEmpty) {
      return const Center(
        child: Text('Nenhuma mídia (vídeo) disponível para esta partida.'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 3,
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 8.0),
                  child: Container(
                    width: double.infinity,
                    alignment: Alignment.center,
                    child: Text(
                    _activeMediaTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                ),
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: (_activeChewieController == null)
                      ? Container(color: Colors.black, child: const Center(child: CircularProgressIndicator()))
                      : Chewie(controller: _activeChewieController!),
                ),
              ],
            ),
          ),
          const Divider(),
          Padding(
             padding: const EdgeInsets.symmetric(vertical: 2.0),
             child: Text('Lista de Reprodução', style: Theme.of(context).textTheme.titleMedium),
          ),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _mediaLinks.length,
            itemBuilder: (context, index) {
              final media = _mediaLinks[index];
              final String title = media['title'] ?? 'Vídeo';
              final String videoUrl = media['videoUrl'];
              final bool isPlaying = (_activeVideoPlayerController?.dataSource == videoUrl);

              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8.0),
                visualDensity: VisualDensity.compact,
                leading: Icon(
                  isPlaying ? Icons.play_circle_fill : Icons.play_circle_outline,
                  color: isPlaying ? Theme.of(context).primaryColor : Colors.grey,
                ),
                title: Text(title, style: TextStyle(fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal, fontSize: 14)),
                selected: isPlaying,
                selectedTileColor: Theme.of(context).primaryColor.withOpacity(0.05),
                onTap: () {
                  _changeMediaVideo(videoUrl, title);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _extractStatsAndFetchPlayers() async {
    if (mounted) {
      setState(() {
        _isLoadingPlayerData = true;
      });
    }

    final data = widget.match.data() as Map<String, dynamic>;
    Map<String, dynamic> statsApplied = {};
    if (data.containsKey('stats_applied') && data['stats_applied'] != null) {
      statsApplied = data['stats_applied'];
    }
    Map<String, dynamic> playerStats = statsApplied['player_stats'] ?? {};
    _manOfTheMatchId = statsApplied['man_of_the_match'];

    _goals = Map<String, int>.from(playerStats['goals'] ?? {});
    _assists = Map<String, int>.from(playerStats['assists'] ?? {});
    _yellows = Map<String, int>.from(playerStats['yellows'] ?? {});
    _reds = Map<String, int>.from(playerStats['reds'] ?? {});

    Set<String> playerIds = {};
    playerIds.addAll(_goals.keys);
    playerIds.addAll(_assists.keys);
    playerIds.addAll(_yellows.keys);
    playerIds.addAll(_reds.keys);
    if (_manOfTheMatchId != null) {
      playerIds.add(_manOfTheMatchId!);
    }
    playerIds.removeWhere((id) => id.isEmpty);

    await _fetchPlayerData(playerIds);
  }

  Future<void> _fetchPlayerData(Set<String> playerIds) async {
    if (playerIds.isEmpty) {
      if (mounted) setState(() => _isLoadingPlayerData = false);
      return;
    }

    try {
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

      if (_manOfTheMatchId != null &&
          _playerDataCache.containsKey(_manOfTheMatchId)) {
        _manOfTheMatchName =
            _playerDataCache[_manOfTheMatchId]?['name'] ?? 'Não encontrado';
        _manOfTheMatchNumber =
            _playerDataCache[_manOfTheMatchId]?['jersey_number'];
      }
    } catch (e) {
      debugPrint("Erro ao buscar dados dos jogadores: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPlayerData = false;
        });
      }
    }
  }

  Future<void> _launchURL(String? urlString) async {
    if (urlString == null || urlString.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Súmula não disponível.')));
      return;
    }
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível abrir o link: $urlString')),
        );
      }
    }
  }

  Widget _buildTeamStatsColumn(
    String teamId,
    String teamName,
    CrossAxisAlignment alignment,
  ) {
    void sortPlayersByNumber(List<Map<String, dynamic>> players) {
      players.sort((a, b) {
        int staffCompare = (a['is_staff'] ? 1 : 0).compareTo(b['is_staff'] ? 1 : 0);
        if (staffCompare != 0) return staffCompare;

        final int? aNum = a['number'];
        final int? bNum = b['number'];
        if (aNum != null && bNum != null) {
          return aNum.compareTo(bNum);
        } else if (aNum != null && bNum == null) {
          return -1;
        } else if (aNum == null && bNum != null) {
          return 1;
        } else {
          return a['name'].compareTo(b['name']);
        }
      });
    }

    List<Map<String, dynamic>> goalPlayers = [];
    _goals.forEach((playerId, count) {
      if (count > 0 && _playerDataCache[playerId]?['team_id'] == teamId) {
        String name = _playerDataCache[playerId]?['name'] ?? 'Jogador desc.';
        int? number = _playerDataCache[playerId]?['jersey_number'];
        bool isStaff = _playerDataCache[playerId]?['is_staff'] ?? false;
        goalPlayers.add({'id': playerId, 'name': name, 'count': count, 'number': number, 'is_staff': isStaff});
      }
    });
    sortPlayersByNumber(goalPlayers);

    Map<String, Map<String, int>> playersWithCardsData = {}; 
    _yellows.forEach((playerId, count) {
      if (count > 0 && _playerDataCache[playerId]?['team_id'] == teamId) {
        playersWithCardsData.putIfAbsent(playerId, () => {'yellow': 0, 'red': 0});
        playersWithCardsData[playerId]!['yellow'] = count;
      }
    });
    _reds.forEach((playerId, count) {
      if (count > 0 && _playerDataCache[playerId]?['team_id'] == teamId) {
        playersWithCardsData.putIfAbsent(playerId, () => {'yellow': 0, 'red': 0});
        playersWithCardsData[playerId]!['red'] = count;
      }
    });
    
    List<Map<String, dynamic>> cardPlayers = [];
    playersWithCardsData.forEach((playerId, cardCounts) {
      String name = _playerDataCache[playerId]?['name'] ?? 'Jogador desc.';
      int? number = _playerDataCache[playerId]?['jersey_number'];
      bool isStaff = _playerDataCache[playerId]?['is_staff'] ?? false;
      cardPlayers.add({'id': playerId, 'name': name, 'counts': cardCounts, 'number': number, 'is_staff': isStaff});
    });
    sortPlayersByNumber(cardPlayers);

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: SizedBox(
            width: double.infinity,
            child: Text(
              teamName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
        ),

        if (goalPlayers.isNotEmpty) ...[
          _buildStatHeader('Gols', Icons.sports_soccer, alignment),
          ...goalPlayers.map((player) => _buildStatItem(
                  playerId: player['id'],
                  name: player['name'],
                  count: player['count'],
                  number: player['number'],
                  isStaff: player['is_staff'], 
                  alignment: alignment,
                )).toList(),
          const SizedBox(height: 12),
        ],
        
        if (cardPlayers.isNotEmpty) ...[
          _buildStatHeader('Cartões', Icons.style_outlined, alignment),
          ...cardPlayers.map((player) => _buildCardStatItem(
                  playerId: player['id'],
                  name: player['name'],
                  cardCounts: player['counts'] as Map<String, int>,
                  number: player['number'],
                  isStaff: player['is_staff'],
                  alignment: alignment,
                )).toList(),
        ],
      ],
    );
  }

  Widget _buildStatHeader(String title, IconData icon, CrossAxisAlignment alignment, [Color? iconColor]) {
    return Align(
      alignment: alignment == CrossAxisAlignment.start
          ? Alignment.centerLeft
          : Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4.0, left: 8.0, right: 8.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (alignment == CrossAxisAlignment.end) ...[
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Icon(icon, color: iconColor ?? Colors.black54, size: 16),
            ] else ...[
              Icon(icon, color: iconColor ?? Colors.black54, size: 16),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required String playerId,
    required String name,
    required int count,
    required CrossAxisAlignment alignment,
    required bool isStaff,
    int? number,
  }) {
    String numberPrefix = number != null ? '#$number ' : '';
    String countSuffix = (count > 1) ? ' ($count)' : '';
    String staffSuffix = isStaff ? ' (Comissão)' : '';
    String displayText = '$numberPrefix$name$staffSuffix$countSuffix';

    EdgeInsets itemPadding = alignment == CrossAxisAlignment.start
        ? const EdgeInsets.only(left: 8.0, right: 4.0, bottom: 2.0)
        : const EdgeInsets.only(left: 4.0, right: 8.0, bottom: 2.0);

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (ctx) => PlayerProfileScreen(playerId: playerId),
          ),
        );
      },
      child: Align(
      alignment: alignment == CrossAxisAlignment.start
          ? Alignment.centerLeft
          : Alignment.centerRight,
      child: Padding(
        padding: itemPadding,
        child: Text(
          displayText,
          style: TextStyle(
            fontSize: 14,
            fontStyle: isStaff ? FontStyle.italic : FontStyle.normal,
          ),
          textAlign: alignment == CrossAxisAlignment.start
              ? TextAlign.start
              : TextAlign.end,
        ),
      ),
      ),
    );
  }

  Widget _buildStatsTab(String status) {
    final data = widget.match.data() as Map<String, dynamic>;
    final homeTeamId = data['team_home_id'] ?? '';
    final awayTeamId = data['team_away_id'] ?? '';
    final homeTeamName = data['team_home_name'] ?? 'Time Casa';
    final awayTeamName = data['team_away_name'] ?? 'Time Visitante';

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        children: [
          _isLoadingPlayerData
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildTeamStatsColumn(homeTeamId, homeTeamName, CrossAxisAlignment.start),
                        ),
                        Container(width: 1, color: Colors.grey.shade300),
                        Expanded(
                          child: _buildTeamStatsColumn(awayTeamId, awayTeamName, CrossAxisAlignment.end),
                        ),
                      ],
                    ),
                  ),
                ),

          if (status == 'finished' && _manOfTheMatchName != null && !_isLoadingPlayerData) ...[
            const Divider(height: 16, thickness: 0.5, indent: 16, endIndent: 16),
            Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 8.0),
                child: Card(
                   elevation: 2,
                   clipBehavior: Clip.antiAlias,
                   child: InkWell(
                    onTap: () {
                      if (_manOfTheMatchId != null && _manOfTheMatchId!.isNotEmpty) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (ctx) => PlayerProfileScreen(playerId: _manOfTheMatchId!),
                          ),
                        );
                      }
                    },
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
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCardStatItem({
    required String playerId,
    required String name,
    required Map<String, int> cardCounts,
    required CrossAxisAlignment alignment,
    required bool isStaff,
    int? number,
  }) {
    int yellowCount = cardCounts['yellow'] ?? 0;
    int redCount = cardCounts['red'] ?? 0;

    String numberPrefix = number != null ? '#$number ' : '';
    String staffSuffix = isStaff ? ' (Comissão)' : ''; 
    String displayText = '$numberPrefix$name$staffSuffix';

    EdgeInsets itemPadding = alignment == CrossAxisAlignment.start
        ? const EdgeInsets.only(left: 8.0, right: 4.0, bottom: 2.0)
        : const EdgeInsets.only(left: 4.0, right: 8.0, bottom: 2.0);

    List<Widget> cardIndicators = [];
    if (yellowCount > 0) {
      cardIndicators.add(Icon(Icons.style, size: 16, color: Colors.yellow[700]));
      if (yellowCount > 1) {
        cardIndicators.add(const SizedBox(width: 2));
        cardIndicators.add(Text('($yellowCount)', style: const TextStyle(fontSize: 12, color: Colors.black54)));
      }
    }
    if (redCount > 0) {
      if (cardIndicators.isNotEmpty) cardIndicators.add(const SizedBox(width: 5));
      cardIndicators.add(Icon(Icons.style, size: 16, color: Colors.red[700]));
    }

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (ctx) => PlayerProfileScreen(playerId: playerId),
          ),
        );
      },
      child: Align(
      alignment: alignment == CrossAxisAlignment.start
          ? Alignment.centerLeft
          : Alignment.centerRight,
      child: Padding(
        padding: itemPadding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (alignment == CrossAxisAlignment.end) ...[
              Flexible(
                child: Text(
                  displayText,
                  style: TextStyle(fontSize: 14, fontStyle: isStaff ? FontStyle.italic : FontStyle.normal),
                  textAlign: TextAlign.end,
                ),
              ),
              const SizedBox(width: 6),
              Row(mainAxisSize: MainAxisSize.min, children: cardIndicators), 
            ] else ...[
              Row(mainAxisSize: MainAxisSize.min, children: cardIndicators),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  displayText,
                  style: TextStyle(fontSize: 14, fontStyle: isStaff ? FontStyle.italic : FontStyle.normal),
                  textAlign: TextAlign.start,
                ),
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.match.data() as Map<String, dynamic>;
    final status = data['status'] ?? 'pending';
    final scoreHome = data['score_home']?.toString() ?? '-';
    final scoreAway = data['score_away']?.toString() ?? '-';

    final homeTeamName = data['team_home_name'] ?? 'Time Casa';
    final awayTeamName = data['team_away_name'] ?? 'Time Visitante';
    final homeShield = data['team_home_shield'] ?? '';
    final awayShield = data['team_away_shield'] ?? '';
    String formattedDate = 'Data Indisponível';
    if (data['datetime'] != null && data['datetime'] is Timestamp) {
      formattedDate = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format((data['datetime'] as Timestamp).toDate());
    }
    final String location = data['location'] ?? 'Local a definir';
    final String? sumulaUrl = data['sumula_url'] as String?;

    return DefaultTabController(
      length: 2, 
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '$homeTeamName $scoreHome x $scoreAway $awayTeamName',
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Compartilhar Card do Jogo',
              onPressed: _shareMatchCard,
            ),
          ],
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
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (homeShield.isNotEmpty)
                        SizedBox(
                          width: 80, height: 80,
                          child: CachedNetworkImage(imageUrl: homeShield, fit: BoxFit.contain),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Text(
                          '$scoreHome x $scoreAway',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (awayShield.isNotEmpty)
                        SizedBox(
                          width: 80, height: 80,
                          child: CachedNetworkImage(imageUrl: awayShield, fit: BoxFit.contain),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$formattedDate - $location',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
                    textAlign: TextAlign.center,
                  ),

                  if (status == 'finished' && sumulaUrl != null && sumulaUrl.isNotEmpty) 
                    Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: TextButton.icon(
                        icon: const Icon(Icons.description_outlined, size: 20),
                        label: const Text('Súmula da Partida (PDF)'),
                        style: TextButton.styleFrom(foregroundColor: Theme.of(context).primaryColor),
                        onPressed: () => _launchURL(sumulaUrl),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildStatsTab(status),
                  _buildMediaTab(),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: const SponsorBannerRotator(),
      ),
    );
  }
}