import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../services/auth_service.dart';
import '../../services/championship_service.dart';
import '../../services/player_service.dart';
import '../../models/player_model.dart';
import '../../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../../widgets/sponsor_banner_rotator.dart';
import '../../utils/custom_cache_manager.dart';

import '../admin/edit_player_screen.dart';

class PlayerProfileScreen extends StatefulWidget {
  final String playerId;
  final String? heroTag;

  const PlayerProfileScreen({super.key, required this.playerId, this.heroTag});

  @override
  State<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends State<PlayerProfileScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  late Future<Player?> _playerFuture;
  late Future<List<Player>> _historicalStatsFuture;

  @override
  void initState() {
    super.initState();
    // 🚨 REGISTRA VISUALIZAÇÃO DESTE ATLETA ESPECÍFICO
    AnalyticsService.logViewItem(
      contentType: 'player_profile',
      itemId: widget.playerId,
      itemName: 'Visualização de Perfil de Atleta',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadData();
  }

  void _loadData() {
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    final playerService = Provider.of<PlayerService>(context, listen: false);
    
    _playerFuture = playerService.getPlayer(widget.playerId, seasonId);
    _historicalStatsFuture = _fetchHistoricalStats(seasonId);
  }

  String _calculateAge(DateTime? dob) {
    if (dob == null) return '-';
    final DateTime today = DateTime.now();
    int age = today.year - dob.year;
    if (today.month < dob.month || (today.month == dob.month && today.day < dob.day)) {
      age--;
    }
    return age.toString();
  }

  Future<List<Player>> _fetchHistoricalStats(String currentSeasonId) async {
    List<Player> historyList = [];
    try {
      final seasonsSnapshot = await _firestore.collection('championships').orderBy('year', descending: true).get();
      for (var seasonDoc in seasonsSnapshot.docs) {
        if (seasonDoc.id == currentSeasonId) continue;
        final playerStatsDoc = await seasonDoc.reference.collection('player_stats').doc(widget.playerId).get();
        if (playerStatsDoc.exists) {
          historyList.add(Player.fromFirestore(playerStatsDoc)); 
        }
      }
    } catch (_) {}
    return historyList;
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final championshipService = Provider.of<ChampionshipService>(context);
    final currentSeasonName = championshipService.currentSeasonName;
    final primaryColor = Theme.of(context).primaryColor;

    return FutureBuilder<Player?>(
      future: _playerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(appBar: AppBar(flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.brazilGradient))), body: const Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          return Scaffold(appBar: AppBar(title: const Text("Perfil"), flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.brazilGradient))), body: const Center(child: Text('Jogador não encontrado.')));
        }

        final Player player = snapshot.data!;
        
        return Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 280.0, 
                floating: false,
                pinned: true,
                backgroundColor: primaryColor,
                actions: [
                  if (authService.isAuthenticated)
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Editar Jogador',
                      onPressed: () async {
                        // 🚨 Analytics: Ação de Editar Jogador pelo Administrador
                        AnalyticsService.logCustomScreenView(
                          'Admin_Edit_Player_Action', 
                          parameters: {'player_id': player.id}
                        );

                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (ctx) => EditPlayerScreen(
                              teamId: player.teamId,
                              teamName: player.teamName,
                              player: player, 
                            ),
                          ),
                        );
                        _loadData(); 
                        setState(() {});
                      },
                    ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  centerTitle: false, 
                  titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
                  title: Text(
                    player.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16.0,
                      shadows: [Shadow(color: Colors.black45, blurRadius: 2)],
                    ),
                  ),
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          gradient: AppTheme.brazilGradient,
                        ),
                      ),
                      Center(
                        child: Hero(
                          tag: widget.heroTag ?? 'player_photo_${player.id}',
                          child: CircleAvatar(
                            radius: 90,
                            backgroundColor: Colors.white24,
                            child: CircleAvatar(
                              radius: 86,
                              backgroundColor: Colors.grey.shade300,
                              backgroundImage: player.photoUrl.isNotEmpty
                                  ? CachedNetworkImageProvider(
                                      player.photoUrl, 
                                      cacheManager: PlayerCacheManager.instance,
                                      maxWidth: 400, 
                                      maxHeight: 400,
                                    )
                                  : null,
                              child: player.photoUrl.isEmpty
                                  ? Icon(player.isStaff ? Icons.assignment_ind_outlined : Icons.person, size: 80, color: Colors.grey[700])
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      if (player.teamShieldUrl.isNotEmpty)
                        Positioned(
                          bottom: 60,
                          right: MediaQuery.of(context).size.width / 2 - 100, 
                          child: CircleAvatar(
                            radius: 22,
                            backgroundColor: Colors.white,
                            child: Padding(
                              padding: const EdgeInsets.all(2.0),
                              child: CachedNetworkImage(
                                imageUrl: player.teamShieldUrl, 
                                fit: BoxFit.contain,
                                memCacheHeight: 150,
                                memCacheWidth: 150,
                              ),
                            ),
                          ),
                        ),
                      
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        child: Container(
                          height: 60,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Colors.black54, Colors.transparent],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 16),
                  
                  Center(
                    child: Column(
                      children: [
                        Text(
                          player.isStaff ? (player.staffRole ?? 'Comissão Técnica') : (player.position ?? 'Atleta'),
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.grey[800], fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          player.teamName,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: primaryColor),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 30, thickness: 1, indent: 20, endIndent: 20),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Informações Pessoais', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Card(
                          elevation: 0,
                          color: Colors.grey[50],
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                _buildInfoRow(Icons.cake, 'Idade', _calculateAge(player.dateOfBirth)),
                                if (!player.isStaff) ...[
                                  const Divider(),
                                  _buildInfoRow(Icons.confirmation_number, 'Camisa', player.jerseyNumber?.toString() ?? '-'),
                                  const Divider(),
                                  _buildInfoRow(Icons.height, 'Altura', player.heightCm != null ? '${player.heightCm} cm' : '-'),
                                  const Divider(),
                                  _buildInfoRow(Icons.monitor_weight, 'Peso', player.weightKg != null ? '${player.weightKg} kg' : '-'),
                                  const Divider(),
                                  _buildInfoRow(Icons.sports_football, 'Pé Preferido', player.preferredFoot ?? '-'),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Desempenho', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        _buildSeasonStatCard(context, player, currentSeasonName, isCurrent: true),
                        FutureBuilder<List<Player>>(
                          future: _historicalStatsFuture,
                          builder: (context, histSnap) {
                            if (!histSnap.hasData) return const SizedBox.shrink();
                            return Column(
                              children: histSnap.data!.map((histPlayer) {
                                return _buildSeasonStatCard(context, histPlayer, "Temporada Anterior", isCurrent: false);
                              }).toList(),
                            );
                          }
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  const SponsorBannerRotator(),
                  const SizedBox(height: 40),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 15)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildSeasonStatCard(BuildContext context, Player p, String seasonName, {bool isCurrent = false}) {
    final primaryColor = Theme.of(context).primaryColor;
    return Card(
      elevation: isCurrent ? 3 : 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: isCurrent ? Colors.white : Colors.grey[100],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isCurrent ? BorderSide(color: primaryColor.withOpacity(0.5), width: 1.5) : BorderSide.none
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                if (p.teamShieldUrl.isNotEmpty) 
                  CachedNetworkImage(
                    imageUrl: p.teamShieldUrl, 
                    width: 28, 
                    height: 28, 
                    fit: BoxFit.contain,
                    memCacheHeight: 100,
                    memCacheWidth: 100,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(seasonName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isCurrent ? Colors.black : Colors.grey[700])),
                ),
                if (isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(10)),
                    child: const Text("ATUAL", style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  )
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                if (!p.isStaff) ...[
                  if (p.isGoalkeeper) 
                    _buildMiniStat('GS', p.goalsConceded, Icons.pan_tool_outlined, Colors.blueGrey)
                  else 
                    _buildMiniStat('Gols', p.goals, Icons.sports_soccer, Colors.black),
                  
                  _buildMiniStat('Ass', p.assists, Icons.assistant, Colors.black),
                ],
                _buildMiniStat('CA', p.totalYellowCards, Icons.style, Colors.amber[700]!),
                _buildMiniStat('CV', p.totalRedCards, Icons.style, Colors.red),
                if (!p.isStaff)
                  _buildMiniStat('Craque', p.motmAwards, Icons.star, Colors.amber),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(String label, int value, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(height: 6),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)),
      ],
    );
  }
}