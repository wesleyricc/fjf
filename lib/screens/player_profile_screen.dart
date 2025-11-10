// lib/screens/player_profile_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/sponsor_banner_rotator.dart';
// 'Services' não é mais necessário aqui

class PlayerProfileScreen extends StatefulWidget {
  final DocumentSnapshot playerDoc;

  const PlayerProfileScreen({super.key, required this.playerDoc});

  @override
  State<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends State<PlayerProfileScreen> {
  
  late Future<List<QueryDocumentSnapshot>> _historicalStatsFuture;
  late Map<String, dynamic> _playerData;

  @override
  void initState() {
    super.initState();
    _playerData = widget.playerDoc.data() as Map<String, dynamic>;
    _historicalStatsFuture = _fetchHistoricalStats();
  }

  // --- NOVA FUNÇÃO: _calculateAge ---
  String _calculateAge(Timestamp? dobTimestamp) {
    if (dobTimestamp == null) {
      return '-'; // Retorna '-' se a data de nascimento não estiver definida
    }
    
    final DateTime dob = dobTimestamp.toDate();
    final DateTime today = DateTime.now();
    
    int age = today.year - dob.year;
    
    // Verifica se o aniversário deste ano já passou
    // Se o mês for anterior, ou
    // Se o mês for o mesmo E o dia for anterior
    if (today.month < dob.month || (today.month == dob.month && today.day < dob.day)) {
      age--; // Ainda não fez aniversário este ano
    }
    
    return age.toString();
  }
  // --- FIM DA NOVA FUNÇÃO ---

  Future<List<QueryDocumentSnapshot>> _fetchHistoricalStats() async {
    /* try {
      final historySnapshot = await _firestore
          .collectionGroup('player_stats')
          .where('global_player_ref', isEqualTo: widget.playerDoc.reference)
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
    final String name = _playerData['name'] ?? 'Nome do Jogador';
    final String? photoUrl = _playerData['photo_url'];
    final String position = _playerData['is_goalkeeper'] == true ? 'Goleiro' : (_playerData['position'] ?? '-');
    
    // --- MUDANÇA: LÊ O TIMESTAMP E CALCULA A IDADE ---
    final Timestamp? dobTimestamp = _playerData['date_of_birth'] as Timestamp?;
    final String displayAge = _calculateAge(dobTimestamp); // Calcula a idade
    // --- FIM DA MUDANÇA ---
    
    final String height = (_playerData['height_cm'] ?? '-').toString();
    final String weight = (_playerData['weight_kg'] ?? '-').toString();
    final String preferredFoot = _playerData['preferred_foot'] ?? '-';

    // Estatísticas da temporada atual
    final int goals = _playerData['goals'] ?? 0;
    final int assists = _playerData['assists'] ?? 0;
    final int yellowCards = _playerData['total_yellow_cards'] ?? 0;
    final int redCards = _playerData['total_red_cards'] ?? 0;
    final int motmAwards = _playerData['man_of_the_match_awards'] ?? 0;
    final int goalsConceded = _playerData['goals_conceded'] ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // --- Seção Header (Foto e Nome) ---
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey[300],
                    backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                        ? CachedNetworkImageProvider(photoUrl)
                        : null,
                    child: (photoUrl == null || photoUrl.isEmpty)
                        ? const Icon(Icons.person, size: 60, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    name,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    position,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
            
            // --- Seção Informações Pessoais ---
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Informações Pessoais', style: Theme.of(context).textTheme.titleMedium),
                  const Divider(),
                  _buildInfoRow('Idade', displayAge), // <-- USA A IDADE CALCULADA
                  _buildInfoRow('Altura', height.isNotEmpty ? '$height cm' : '-'),
                  _buildInfoRow('Peso', weight.isNotEmpty ? '$weight kg' : '-'),
                  _buildInfoRow('Pé Preferido', preferredFoot),
                ],
              ),
            ),

            // --- Seção Estatísticas (Temporada Atual) ---
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
            
            // --- Seção Histórico (PARA O FUTURO) ---
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Histórico de Temporadas (Últimas 3)', style: Theme.of(context).textTheme.titleMedium),
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

                      final historyDocs = snapshot.data!;
                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: historyDocs.length,
                        itemBuilder: (context, index) {
                          final docData = historyDocs[index].data() as Map<String, dynamic>;
                          final season = docData['season'] ?? '????';
                          final teamName = docData['team_name_season'] ?? 'Time';
                          final goals = docData['goals'] ?? 0;
                          
                          return ListTile(
                            title: Text('Temporada $season ($teamName)'),
                            subtitle: Text('Gols: $goals'),
                          );
                        },
                      );
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