// lib/screens/player_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/sponsor_banner_rotator.dart';
import '../services/admin_service.dart';
import 'edit_player_screen.dart';

class PlayerProfileScreen extends StatefulWidget {
  final String playerId;

  const PlayerProfileScreen({super.key, required this.playerId});

  @override
  State<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends State<PlayerProfileScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  late Future<DocumentSnapshot> _playerFuture;
  late Future<List<QueryDocumentSnapshot>> _historicalStatsFuture;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    _playerFuture = _firestore.collection('players').doc(widget.playerId).get();
    _historicalStatsFuture = _fetchHistoricalStats();
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

  Future<List<QueryDocumentSnapshot>> _fetchHistoricalStats() async {
    /* // TODO: Descomentar quando a estrutura multi-temporada estiver ativa
    try {
      final historySnapshot = await _firestore
          .collectionGroup('player_stats')
          .where('global_player_ref', isEqualTo: _firestore.doc('players/${widget.playerId}'))
          .orderBy('season', descending: true)
          .limit(3)
          .get();
          
      return historySnapshot.docs;
    } catch (e) {
      debugPrint("Erro ao buscar histórico do jogador: $e");
      return [];
    }
    */
    return Future.value([]); 
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: _playerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.data!.exists) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Erro ao carregar jogador.')),
          );
        }

        // Dados carregados, constrói a UI
        final DocumentSnapshot playerDoc = snapshot.data!;
        final _playerData = playerDoc.data() as Map<String, dynamic>;
        
        final String name = _playerData['name'] ?? 'Nome do Jogador';
        final String? photoUrl = (_playerData.containsKey('photo_url')) ? _playerData['photo_url'] as String? : null;
        final bool isStaff = _playerData['is_staff'] ?? false;
        final String position = _playerData['is_goalkeeper'] == true ? 'Goleiro' : (_playerData['position'] ?? '-');
        
        // ID do time para buscar o escudo
        final String? teamId = _playerData['team_id']; 
        final String teamName = _playerData['team_name'] ?? '';

        final Timestamp? dobTimestamp = _playerData['date_of_birth'] as Timestamp?;
        final String displayAge = _calculateAge(dobTimestamp);
        
        final String height = (_playerData['height_cm'] ?? '-').toString();
        final String weight = (_playerData['weight_kg'] ?? '-').toString();
        final String preferredFoot = _playerData['preferred_foot'] ?? '-';

        final int goals = _playerData['goals'] ?? 0;
        final int assists = _playerData['assists'] ?? 0;
        final int yellowCards = _playerData['total_yellow_cards'] ?? 0;
        final int redCards = _playerData['total_red_cards'] ?? 0;
        final int motmAwards = _playerData['man_of_the_match_awards'] ?? 0;
        final int goalsConceded = _playerData['goals_conceded'] ?? 0;

        return Scaffold(
          appBar: AppBar(
            title: Text(name),
            // --- BOTÃO DE EDIÇÃO (SÓ PARA ADMIN) ---
            actions: [
              if (AdminService.isAdmin)
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Editar Jogador',
                  onPressed: () async {
                    // Navega para a tela de edição
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (ctx) => EditPlayerScreen(
                          teamId: teamId ?? '', // Garante string vazia se nulo
                          teamName: teamName,
                          playerDoc: playerDoc, // Passa o documento atual
                        ),
                      ),
                    );
                    // Ao voltar, recarrega os dados para mostrar as alterações
                    setState(() {
                      _loadData();
                    });
                  },
                ),
            ],
            // --- FIM DA ALTERAÇÃO ---
          ),
          body: SingleChildScrollView(
            child: Column(
              children: [
                // Seção Header com StreamBuilder para o Time
                StreamBuilder<DocumentSnapshot>(
                  stream: teamId != null 
                      ? _firestore.collection('teams').doc(teamId).snapshots()
                      : null,
                  builder: (context, teamSnapshot) {
                    // Pega a URL do escudo (se houver)
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
                          // --- STACK: FOTO + ESCUDO ---
                          Stack(
                            children: [
                              // Foto Principal do Jogador
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
                              
                              // Escudo do Time (Sobreposto no canto inferior direito)
                              if (teamShieldUrl.isNotEmpty)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.transparent,
                                      //border: Border.all(color: Theme.of(context).primaryColor, width: 2),
                                      image: DecorationImage(
                                        image: CachedNetworkImageProvider(teamShieldUrl),
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          // --- FIM STACK ---
                          
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
                        ],
                      ),
                    );
                  }
                ),
                
                // Seção Informações Pessoais
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

                // Seção Estatísticas (Temporada Atual)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Estatísticas (Temporada Atual)', style: Theme.of(context).textTheme.titleMedium),
                      const Divider(),
                      if (position == 'Goleiro')
                        _buildInfoRow('Gols Sofridos', goalsConceded.toString())
                      else
                        _buildInfoRow('Gols', goals.toString()),
                      _buildInfoRow('Assistências', assists.toString()),
                      _buildInfoRow('Cartões Amarelos', yellowCards.toString()),
                      _buildInfoRow('Cartões Vermelhos', redCards.toString()),
                      _buildInfoRow('Craque do Jogo', motmAwards.toString()),
                    ],
                  ),
                ),
                
                // Seção Histórico (PARA O FUTURO)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Histórico de Temporadas', style: Theme.of(context).textTheme.titleMedium),
                      const Divider(),
                      FutureBuilder<List<QueryDocumentSnapshot>>(
                        future: _historicalStatsFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (snapshot.hasError) {
                            return const Center(child: Text('Erro ao carregar histórico.'));
                          }
                          if (!snapshot.hasData || snapshot.data!.isEmpty) {
                            return const Center(
                              child: Text(
                                'Histórico de temporadas anteriores indisponível.\n(Funcionalidade em preparação para 2026)',
                                textAlign: TextAlign.center,
                              ),
                            );
                          }
                          
                          // Lógica de exibição (quando os dados existirem)
                          return const Center(child: Text('Histórico aparecerá aqui.'));
                        },
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
}