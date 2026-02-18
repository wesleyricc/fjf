import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart'; 

// Services
import '../services/championship_service.dart';

// Widgets
import '../widgets/sponsor_banner_rotator.dart';
import '../widgets/match_result_card.dart';
import '../widgets/match_stats_tab.dart';
import '../widgets/match_media_tab.dart';

class MatchStatsScreen extends StatefulWidget {
  final DocumentSnapshot match;
  const MatchStatsScreen({super.key, required this.match});

  @override
  State<MatchStatsScreen> createState() => _MatchStatsScreenState();
}

class _MatchStatsScreenState extends State<MatchStatsScreen> with SingleTickerProviderStateMixin {
  final ScreenshotController _screenshotController = ScreenshotController();
  late TabController _tabController;

  Map<String, Map<String, dynamic>> _playerDataCache = {};
  bool _isLoadingPlayerData = true;
  String? _errorMessage;
  
  Map<String, int> _goals = {};
  Map<String, int> _assists = {};
  Map<String, int> _yellows = {};
  Map<String, int> _reds = {};
  String? _manOfTheMatchId;
  
  List<Map<String, dynamic>> _mediaLinks = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    // Usamos addPostFrameCallback para garantir acesso seguro ao Provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDataSafe();
    });
    
    try {
      final data = widget.match.data() as Map<String, dynamic>? ?? {};
      FirebaseAnalytics.instance.logScreenView(
        screenName: '/match/stats/${data['team_home_name']}-vs-${data['team_away_name']}',
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // --- LÓGICA DE CARREGAMENTO SEGURA ---
  Future<void> _loadDataSafe() async {
    try {
      // 1. Extração segura dos dados do Snapshot
      final data = widget.match.data();
      if (data == null || data is! Map<String, dynamic>) {
        throw Exception("Dados da partida inválidos ou corrompidos.");
      }

      // 2. Extrai Links de Mídia
      if (data['stats_applied']?['media_links'] != null) {
        final links = data['stats_applied']['media_links'] as List<dynamic>;
        _mediaLinks = List<Map<String, dynamic>>.from(links.map((i) => Map<String, dynamic>.from(i)));
      }

      // 3. Extrai Estatísticas
      final Map<String, dynamic> playerStats = data['stats_applied']?['player_stats'] ?? {};
      _manOfTheMatchId = data['stats_applied']?['man_of_the_match'];

      _goals = _safeCastStatMap(playerStats['goals']);
      _assists = _safeCastStatMap(playerStats['assists']);
      _yellows = _safeCastStatMap(playerStats['yellows']);
      _reds = _safeCastStatMap(playerStats['reds']);

      // 4. Identifica IDs necessários
      final Set<String> playerIds = {
        ..._goals.keys, ..._assists.keys, ..._yellows.keys, ..._reds.keys,
        if (_manOfTheMatchId != null) _manOfTheMatchId!
      };
      playerIds.removeWhere((id) => id.isEmpty);

      // 5. Garante que os jogadores estejam carregados no Service
      if (playerIds.isNotEmpty) {
        await _ensurePlayersLoaded(data['team_home_id'], data['team_away_id']);
        _populatePlayerCache(playerIds);
      } else {
        if (mounted) setState(() => _isLoadingPlayerData = false);
      }

    } catch (e) {
      debugPrint("Erro ao carregar estatísticas da partida: $e");
      if (mounted) {
        setState(() {
          _isLoadingPlayerData = false;
          _errorMessage = "Não foi possível carregar os detalhes desta partida.";
        });
      }
    }
  }

  Map<String, int> _safeCastStatMap(dynamic map) {
    if (map == null || map is! Map) return {};
    try {
      return Map<String, int>.from(map.map((k, v) => MapEntry(k.toString(), (v as num).toInt())));
    } catch (_) {
      return {};
    }
  }

  Future<void> _ensurePlayersLoaded(String? homeId, String? awayId) async {
    final service = Provider.of<ChampionshipService>(context, listen: false);
    
    final futures = <Future>[];
    
    // Verifica se precisa carregar Home
    if (homeId != null && service.getCachedRoster(homeId).isEmpty) {
      futures.add(service.fetchRoster(homeId));
    }
    // Verifica se precisa carregar Away
    if (awayId != null && service.getCachedRoster(awayId).isEmpty) {
      futures.add(service.fetchRoster(awayId));
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
  }

  void _populatePlayerCache(Set<String> playerIds) {
    final service = Provider.of<ChampionshipService>(context, listen: false);
    final allPlayers = service.allPlayers; // Pega do cache atualizado
    
    Map<String, Map<String, dynamic>> tempCache = {};

    for (var id in playerIds) {
      try {
        final player = allPlayers.firstWhere((p) => p.id == id);
        tempCache[id] = {
          'name': player.name,
          'jersey_number': player.jerseyNumber,
          'team_id': player.teamId,
          'photo_url': player.photoUrl,
          'is_staff': player.isStaff,
        };
      } catch (e) {
        // Jogador não encontrado no cache da temporada atual
        // Isso acontece se a partida referenciar um jogador que foi deletado ou é de outra temporada (erro de dados)
        tempCache[id] = {'name': 'Desconhecido', 'team_id': ''};
      }
    }

    if (mounted) {
      setState(() {
        _playerDataCache = tempCache;
        _isLoadingPlayerData = false;
      });
    }
  }

  // --- LÓGICA DE COMPARTILHAMENTO ---
  Future<void> _shareMatchCard() async {
    final data = widget.match.data() as Map<String, dynamic>;
    
    List<String> homeScorersList = [];
    List<String> awayScorersList = [];
    
    if (!_isLoadingPlayerData) {
      _goals.forEach((pid, count) {
        if (count > 0 && _playerDataCache.containsKey(pid)) {
          final pData = _playerDataCache[pid]!;
          final parts = (pData['name'] as String).trim().split(' ');
          String shortName = parts.length > 1 ? "${parts[0]} ${parts.last}" : parts[0];
          String entry = count > 1 ? "$shortName ($count)" : shortName;
          
          if (pData['team_id'] == data['team_home_id']) homeScorersList.add(entry);
          else if (pData['team_id'] == data['team_away_id']) awayScorersList.add(entry);
        }
      });
    }

    String label = 'JOGO';
    final phase = data['phase'];
    final round = data['round'];
    if (phase == 'first') label = '${round}ª RODADA';
    else if (phase == 'quarter_final') label = 'PLAYOFFS';
    else if (phase == 'semifinal') label = 'SEMIFINAL';
    else if (phase == 'third_place') label = '3º LUGAR';
    else if (phase == 'final') label = 'FINAL';

    if (!mounted) return;
    showDialog(
      context: context, 
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Screenshot(
              controller: _screenshotController,
              child: MatchResultCard(
                homeName: data['team_home_name'] ?? 'Casa',
                awayName: data['team_away_name'] ?? 'Fora',
                homeShield: data['team_home_shield'] ?? '',
                awayShield: data['team_away_shield'] ?? '',
                scoreHome: (data['score_home'] ?? '-').toString(),
                scoreAway: (data['score_away'] ?? '-').toString(),
                date: data['datetime'] != null ? DateFormat('dd/MM/yyyy HH:mm').format((data['datetime'] as Timestamp).toDate()) : '',
                location: data['location'] ?? '',
                matchLabel: label,
                homeScorers: homeScorersList,
                awayScorers: awayScorersList,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.share),
              label: const Text("Compartilhar"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
              onPressed: () async {
                final bytes = await _screenshotController.capture(pixelRatio: 3.0);
                if (bytes != null && mounted) {
                  Navigator.pop(ctx);
                  await Share.shareXFiles([XFile.fromData(bytes, mimeType: 'image/png', name: 'match_result.png')], text: 'Confira o resultado! #FJF2025');
                }
              },
            )
          ],
        ),
      )
    );
  }

  Future<void> _launchURL(String? urlString) async {
    if (urlString == null || urlString.isEmpty) return;
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Erro ao abrir link.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Detalhes da Partida")),
        body: Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red))),
      );
    }

    final data = widget.match.data() as Map<String, dynamic>;
    final sumulaUrl = data['sumula_url'] as String?;
    final dateStr = data['datetime'] != null ? DateFormat('dd/MM/yyyy HH:mm', 'pt_BR').format((data['datetime'] as Timestamp).toDate()) : 'Data a definir';

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text("${data['team_home_name']} x ${data['team_away_name']}"),
          actions: [
            IconButton(icon: const Icon(Icons.share), onPressed: _shareMatchCard),
          ],
          bottom: TabBar(
            controller: _tabController,
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
                      _buildBigShield(data['team_home_shield']),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: Text(
                          "${data['score_home'] ?? '-'} x ${data['score_away'] ?? '-'}",
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      _buildBigShield(data['team_away_shield']),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text("$dateStr - ${data['location'] ?? ''}", style: Theme.of(context).textTheme.bodySmall),
                  if (sumulaUrl != null)
                    TextButton.icon(
                      icon: const Icon(Icons.description, size: 16),
                      label: const Text("Ver Súmula (PDF)"),
                      onPressed: () => _launchURL(sumulaUrl),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  MatchStatsTab(
                    matchData: data,
                    playerDataCache: _playerDataCache, 
                    goals: _goals,
                    assists: _assists,
                    yellows: _yellows,
                    reds: _reds,
                    manOfTheMatchId: _manOfTheMatchId,
                    isLoading: _isLoadingPlayerData,
                  ),
                  MatchMediaTab(mediaLinks: _mediaLinks),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: const SponsorBannerRotator(),
      ),
    );
  }

  Widget _buildBigShield(String? url) {
    if (url == null || url.isEmpty) return const Icon(Icons.shield, size: 60, color: Colors.grey);
    return SizedBox(
      width: 60, height: 60,
      child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
    );
  }
}