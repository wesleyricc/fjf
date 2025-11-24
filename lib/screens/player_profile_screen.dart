import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../services/auth_service.dart';
import 'edit_player_screen.dart';
import '../services/championship_service.dart';
import '../services/firestore_service.dart';

class PlayerProfileScreen extends StatefulWidget {
  final String playerId;

  const PlayerProfileScreen({super.key, required this.playerId});

  @override
  State<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends State<PlayerProfileScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  late Future<DocumentSnapshot> _playerFuture;
  late Future<List<Map<String, dynamic>>> _historicalStatsFuture;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadData();
  }

  void _loadData() {
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    
    // 1. Carrega dados da temporada atual
    if (seasonId == FirestoreService.LEGACY_ID) {
      _playerFuture = _firestore.collection('players').doc(widget.playerId).get();
    } else {
      _playerFuture = _firestore
          .collection('championships')
          .doc(seasonId)
          .collection('player_stats')
          .doc(widget.playerId)
          .get();
    }
    
    // 2. Carrega histórico
    _historicalStatsFuture = _fetchHistoricalStats(seasonId);
  }

  String _calculateAge(Timestamp? dobTimestamp) {
    if (dobTimestamp == null) return '-';
    final DateTime dob = dobTimestamp.toDate();
    final DateTime today = DateTime.now();
    int age = today.year - dob.year;
    if (today.month < dob.month || (today.month == dob.month && today.day < dob.day)) {
      age--;
    }
    return age.toString();
  }

  Future<List<Map<String, dynamic>>> _fetchHistoricalStats(String currentSeasonId) async {
    List<Map<String, dynamic>> historyList = [];

    try {
      final seasonsSnapshot = await _firestore
          .collection('championships')
          .orderBy('year', descending: true)
          .get();

      for (var seasonDoc in seasonsSnapshot.docs) {
        if (seasonDoc.id == currentSeasonId) continue;

        final playerStatsDoc = await seasonDoc.reference
            .collection('player_stats')
            .doc(widget.playerId)
            .get();

        if (playerStatsDoc.exists) {
          final statsData = playerStatsDoc.data()!;
          final seasonData = seasonDoc.data();

          historyList.add({
            'season_year': seasonData['year'],
            'season_name': seasonData['name'],
            ...statsData, 
          });
        }
      }
    } catch (e) {
      debugPrint("Erro ao buscar histórico: $e");
    }

    return historyList;
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final championshipService = Provider.of<ChampionshipService>(context);
    final seasonId = championshipService.currentSeasonId;
    
    // Dados da temporada atual para compor o card
    // final currentSeasonYear = championshipService.currentSeasonYear; // Não usado mais no título
    final currentSeasonName = championshipService.currentSeasonName;

    return FutureBuilder<DocumentSnapshot>(
      future: _playerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text("Perfil")),
            body: const Center(child: Text('Jogador não inscrito nesta temporada.')),
          );
        }

        final DocumentSnapshot playerDoc = snapshot.data!;
        final _playerData = playerDoc.data() as Map<String, dynamic>;
        
        final String name = _playerData['name'] ?? 'Nome do Jogador';
        final String? photoUrl = (_playerData.containsKey('photo_url')) ? _playerData['photo_url'] as String? : null;
        final bool isStaff = _playerData['is_staff'] ?? false;
        final String position = _playerData['is_goalkeeper'] == true ? 'Goleiro' : (_playerData['position'] ?? '-');
        
        final String? teamId = _playerData['team_id']; 
        final String teamName = _playerData['team_name'] ?? '';

        final Timestamp? dobTimestamp = _playerData['date_of_birth'] as Timestamp?;
        final String displayAge = _calculateAge(dobTimestamp);
        
        final String height = (_playerData['height_cm'] ?? '-').toString();
        final String weight = (_playerData['weight_kg'] ?? '-').toString();
        final String preferredFoot = _playerData['preferred_foot'] ?? '-';

        // Estatísticas Atuais
        final int goals = _playerData['goals'] ?? 0;
        final int assists = _playerData['assists'] ?? 0;
        final int yellowCards = _playerData['total_yellow_cards'] ?? 0;
        final int redCards = _playerData['total_red_cards'] ?? 0;
        final int motmAwards = _playerData['man_of_the_match_awards'] ?? 0;
        final int goalsConceded = _playerData['goals_conceded'] ?? 0;

        Stream<DocumentSnapshot>? teamStream;
        if (teamId != null && teamId.isNotEmpty) {
          if (seasonId == FirestoreService.LEGACY_ID) {
            teamStream = _firestore.collection('teams').doc(teamId).snapshots();
          } else {
            teamStream = _firestore
                .collection('championships')
                .doc(seasonId)
                .collection('teams_participation')
                .doc(teamId)
                .snapshots();
          }
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(name),
            actions: [
              if (authService.isAuthenticated)
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Editar Jogador',
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (ctx) => EditPlayerScreen(
                          teamId: teamId ?? '',
                          teamName: teamName,
                          playerDoc: playerDoc,
                        ),
                      ),
                    );
                    _loadData();
                    setState(() {});
                  },
                ),
            ],
          ),
          body: SingleChildScrollView(
            child: Column(
              children: [
                // --- HEADER (FOTO E NOME) ---
                StreamBuilder<DocumentSnapshot>(
                  stream: teamStream, 
                  builder: (context, teamSnapshot) {
                    Map<String, dynamic>? teamData = teamSnapshot.hasData ? teamSnapshot.data!.data() as Map<String, dynamic>? : null;
                    String teamShieldUrl = teamData?['shield_url'] ?? '';

                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24.0),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
                      ),
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 120,
                                backgroundColor: Colors.grey[300],
                                backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                                    ? CachedNetworkImageProvider(photoUrl) as ImageProvider
                                    : null,
                                child: (photoUrl == null || photoUrl.isEmpty)
                                    ? Icon(
                                        isStaff ? Icons.assignment_ind_outlined : Icons.person,
                                        size: 150,
                                        color: Colors.grey[700],
                                      )
                                    : null,
                              ),
                              if (teamShieldUrl.isNotEmpty)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      //shape: BoxShape.circle,
                                      //color: Colors.white, 
                                      //boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)], 
                                      image: DecorationImage(
                                        image: CachedNetworkImageProvider(teamShieldUrl),
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            name,
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            position,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.grey[700]),
                          ),
                          Text(
                            teamName,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    );
                  }
                ),
                
                // --- INFO PESSOAL ---
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Informações Pessoais', style: Theme.of(context).textTheme.titleMedium),
                      const Divider(),
                      _buildInfoRow('Idade', displayAge),
                      _buildInfoRow('Altura', height != '-' ? '$height cm' : '-'),
                      _buildInfoRow('Peso', weight != '-' ? '$weight kg' : '-'),
                      _buildInfoRow('Pé Preferido', preferredFoot),
                    ],
                  ),
                ),

                // --- HISTÓRICO UNIFICADO (ATUAL + PASSADO) ---
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Estatísticas e Histórico', style: Theme.of(context).textTheme.titleMedium),
                      const Divider(),
                      
                      StreamBuilder<DocumentSnapshot>(
                        stream: teamStream,
                        builder: (context, teamSnap) {
                          final currentTeamData = teamSnap.data?.data() as Map<String, dynamic>?;
                          final currentShield = currentTeamData?['shield_url'] ?? '';

                          return FutureBuilder<List<Map<String, dynamic>>>(
                            future: _historicalStatsFuture,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()));
                              }
                              
                              final history = snapshot.data ?? [];
                              
                              // 1. Cria o objeto da Temporada Atual
                              final Map<String, dynamic> currentSeasonData = {
                                'season_name': currentSeasonName + ' (Atual)',
                                'team_name': teamName,
                                'team_shield_url': currentShield,
                                'goals': goals,
                                'assists': assists,
                                'total_yellow_cards': yellowCards,
                                'total_red_cards': redCards,
                                'is_goalkeeper': position == 'Goleiro',
                                'goals_conceded': goalsConceded,
                                'man_of_the_match_awards': motmAwards,
                                'is_current': true, 
                              };

                              // 2. Une a lista (Atual primeiro + Histórico)
                              final List<Map<String, dynamic>> fullList = [currentSeasonData, ...history];

                              return Column(
                                children: fullList.map((data) {
                                  // Removido 'season_year' da visualização
                                  final String sName = data['season_name'] ?? '';
                                  final String tName = data['team_name'] ?? 'Time';
                                  final String tShield = data['team_shield_url'] ?? '';
                                  
                                  final int g = data['goals'] ?? 0;
                                  final int a = data['assists'] ?? 0;
                                  final int y = data['total_yellow_cards'] ?? 0;
                                  final int r = data['total_red_cards'] ?? 0;
                                  final int motm = data['man_of_the_match_awards'] ?? 0; 
                                  final bool isGk = data['is_goalkeeper'] ?? false;
                                  final int gs = data['goals_conceded'] ?? 0;
                                  final bool isCurrent = data['is_current'] ?? false;

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    elevation: isCurrent ? 3 : 1,
                                    shape: isCurrent 
                                        ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Theme.of(context).primaryColor, width: 1.5))
                                        : null,
                                    child: Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: Column(
                                        children: [
                                          Row(
                                            children: [
                                              if (tShield.isNotEmpty)
                                                CachedNetworkImage(imageUrl: tShield, width: 35, height: 35, fit: BoxFit.contain),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    // --- CORREÇÃO AQUI: MOSTRAR APENAS O NOME ---
                                                    Text(sName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isCurrent ? Theme.of(context).primaryColor : Colors.black)),
                                                    Text(tName, style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const Divider(),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                                            children: [
                                              if (isGk) _buildMiniStat('GS', gs, Icons.pan_tool_outlined, Colors.blueGrey)
                                              else _buildMiniStat('Gols', g, Icons.sports_soccer, Colors.black),
                                              
                                              _buildMiniStat('Ass', a, Icons.assistant, Colors.black),
                                              _buildMiniStat('CA', y, Icons.style, Colors.orange),
                                              _buildMiniStat('CV', r, Icons.style, Colors.red),
                                              
                                              _buildMiniStat('Craque', motm, Icons.star, Colors.amber),
                                            ],
                                          )
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          );
                        }
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: const SponsorBannerRotator(),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[700], fontSize: 16)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, int value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 2),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}