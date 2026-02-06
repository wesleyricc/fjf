import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

// Widgets Refatorados
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
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScreenshotController _screenshotController = ScreenshotController();
  late TabController _tabController;

  // Cache Local de Jogadores (Necessário para montar os nomes nas estatísticas)
  Map<String, Map<String, dynamic>> _playerDataCache = {};
  bool _isLoadingPlayerData = true;
  
  // Stats parseados do documento
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
    _extractStatsAndFetchPlayers();
    
    // Log Analytics
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

  // --- LÓGICA DE DADOS ---
  Future<void> _extractStatsAndFetchPlayers() async {
    final data = widget.match.data() as Map<String, dynamic>;
    
    // 1. Extrai links de mídia
    if (data['stats_applied']?['media_links'] != null) {
      final links = data['stats_applied']['media_links'] as List<dynamic>;
      _mediaLinks = List<Map<String, dynamic>>.from(links.map((i) => Map<String, dynamic>.from(i)));
    }

    // 2. Extrai estatísticas numéricas
    Map<String, dynamic> playerStats = data['stats_applied']?['player_stats'] ?? {};
    _manOfTheMatchId = data['stats_applied']?['man_of_the_match'];

    _goals = Map<String, int>.from(playerStats['goals'] ?? {});
    _assists = Map<String, int>.from(playerStats['assists'] ?? {});
    _yellows = Map<String, int>.from(playerStats['yellows'] ?? {});
    _reds = Map<String, int>.from(playerStats['reds'] ?? {});

    // 3. Coleta IDs para buscar nomes/fotos
    Set<String> playerIds = {
      ..._goals.keys, ..._assists.keys, ..._yellows.keys, ..._reds.keys,
      if (_manOfTheMatchId != null) _manOfTheMatchId!
    };
    playerIds.removeWhere((id) => id.isEmpty);

    await _fetchPlayerData(playerIds);
  }

  Future<void> _fetchPlayerData(Set<String> playerIds) async {
    if (playerIds.isEmpty) {
      if (mounted) setState(() => _isLoadingPlayerData = false);
      return;
    }

    try {
      // Busca em lote (max 10 por vez no 'whereIn')
      List<String> idList = playerIds.toList();
      Map<String, Map<String, dynamic>> fetchedData = {};

      for (int i = 0; i < idList.length; i += 10) {
        int end = (i + 10 < idList.length) ? i + 10 : idList.length;
        // Importante: Jogadores são globais (coleção raiz) por enquanto
        final snapshot = await _firestore.collection('players')
            .where(FieldPath.documentId, whereIn: idList.sublist(i, end))
            .get();

        for (var doc in snapshot.docs) {
          fetchedData[doc.id] = doc.data();
        }
      }
      
      if (mounted) {
        setState(() {
          _playerDataCache = fetchedData;
          _isLoadingPlayerData = false;
        });
      }
    } catch (e) {
      debugPrint("Erro ao buscar jogadores: $e");
      if (mounted) setState(() => _isLoadingPlayerData = false);
    }
  }

  // --- LÓGICA DE COMPARTILHAMENTO ---
  Future<void> _shareMatchCard() async {
    final data = widget.match.data() as Map<String, dynamic>;
    
    // Prepara listas de goleadores para o card
    List<String> homeScorersList = [];
    List<String> awayScorersList = [];
    
    if (!_isLoadingPlayerData) {
      _goals.forEach((pid, count) {
        if (count > 0 && _playerDataCache.containsKey(pid)) {
          final pData = _playerDataCache[pid]!;
          // Formata nome
          final parts = (pData['name'] as String).trim().split(' ');
          String shortName = parts.length > 1 ? "${parts[0]} ${parts.last}" : parts[0];
          String entry = count > 1 ? "$shortName ($count)" : shortName;
          
          if (pData['team_id'] == data['team_home_id']) homeScorersList.add(entry);
          else if (pData['team_id'] == data['team_away_id']) awayScorersList.add(entry);
        }
      });
    }

    // Label da fase
    String label = 'JOGO';
    final phase = data['phase'];
    final round = data['round'];
    if (phase == 'first') label = '${round}ª RODADA';
    else if (phase == 'semifinal') label = 'SEMIFINAL';
    else if (phase == 'final') label = 'FINAL';

    // Mostra o Dialogo Invisível para captura
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
            // Placar Fixo no Topo
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
            
            // Conteúdo das Abas
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