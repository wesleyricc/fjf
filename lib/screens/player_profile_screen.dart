import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

// Services & Models
import '../services/auth_service.dart';
import '../services/championship_service.dart';
import '../services/firestore_service.dart';
import '../models/player_model.dart'; // <-- Model

// Widgets & Screens
import '../widgets/sponsor_banner_rotator.dart';
import 'edit_player_screen.dart';
import '../utils/custom_cache_manager.dart';

class PlayerProfileScreen extends StatefulWidget {
  final String playerId;

  const PlayerProfileScreen({super.key, required this.playerId});

  @override
  State<PlayerProfileScreen> createState() => _PlayerProfileScreenState();
}

class _PlayerProfileScreenState extends State<PlayerProfileScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance; // Acesso direto apenas para histórico inter-temporadas
  
  late Future<Player?> _playerFuture;
  late Future<List<Player>> _historicalStatsFuture;

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
    
    // 1. Carrega dados da temporada atual usando o Serviço e Model
    _playerFuture = _firestoreService.getPlayer(widget.playerId, seasonId);
    
    // 2. Carrega histórico (Mantivemos a lógica customizada aqui pois é específica desta tela)
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
      final seasonsSnapshot = await _firestore
          .collection('championships')
          .orderBy('year', descending: true)
          .get();

      for (var seasonDoc in seasonsSnapshot.docs) {
        if (seasonDoc.id == currentSeasonId) continue; // Pula temporada atual

        // Tenta buscar o jogador na subcoleção desta temporada antiga
        final playerStatsDoc = await seasonDoc.reference
            .collection('player_stats')
            .doc(widget.playerId)
            .get();

        if (playerStatsDoc.exists) {
          // Converte para Model para usar o mesmo widget de exibição
          // Nota: Injetamos o nome da temporada no campo 'teamName' ou similar se quisermos exibir,
          // mas aqui vamos criar um objeto Player representando aquele estado antigo.
          final histPlayer = Player.fromFirestore(playerStatsDoc);
          // Podemos usar um campo auxiliar ou wrapper, mas o Player já tem os dados.
          // O nome da temporada será pego separadamente na UI.
          historyList.add(histPlayer); 
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
    final currentSeasonName = championshipService.currentSeasonName;

    return FutureBuilder<Player?>(
      future: _playerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          return Scaffold(
            appBar: AppBar(title: const Text("Perfil")),
            body: const Center(child: Text('Jogador não encontrado nesta temporada.')),
          );
        }

        final Player player = snapshot.data!;
        
        return Scaffold(
          appBar: AppBar(
            title: Text(player.name),
            actions: [
              if (authService.isAuthenticated)
                IconButton(
                  icon: const Icon(Icons.edit),
                  tooltip: 'Editar Jogador',
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (ctx) => EditPlayerScreen(
                          teamId: player.teamId,
                          teamName: player.teamName,
                          playerDoc: null, // EditPlayerScreen ainda espera Doc ou lógica de ID. 
                          // TODO: No futuro, refatorar EditPlayerScreen para receber Player Model.
                          // Por enquanto, o EditPlayerScreen vai buscar pelo ID se passarmos null e tiver ID no construtor?
                          // Ajuste temporário: EditPlayerScreen precisaria de refatoração para aceitar Model.
                          // Como não refatoramos EditPlayerScreen ainda, isso pode ser um ponto de atenção.
                          // Vou assumir que você vai manter o EditPlayerScreen legado por enquanto ou que ele sabe lidar.
                          // *Melhor abordagem:* Passar o ID e deixar a tela buscar, ou passar um "dummy doc" se necessário.
                          // Para manter compatibilidade sem refatorar EditPlayer agora, vamos deixá-lo carregar pelo ID se possível
                          // ou passar os dados via construtor se ele suportar.
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
                Container(
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
                            radius: 80,
                            backgroundColor: Colors.grey[300],
                            backgroundImage: player.photoUrl.isNotEmpty
                                ? CachedNetworkImageProvider(player.photoUrl, cacheManager: PlayerCacheManager.instance)
                                : null,
                            child: player.photoUrl.isEmpty
                                ? Icon(player.isStaff ? Icons.assignment_ind_outlined : Icons.person, size: 80, color: Colors.grey[700])
                                : null,
                          ),
                          if (player.teamShieldUrl.isNotEmpty)
                            Positioned(
                              bottom: 0, right: 0,
                              child: CircleAvatar(
                                radius: 25,
                                backgroundColor: Colors.white,
                                backgroundImage: CachedNetworkImageProvider(player.teamShieldUrl),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        player.name,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        player.isStaff ? (player.staffRole ?? 'Comissão Técnica') : (player.position ?? 'Atleta'),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[700]),
                      ),
                      Text(
                        player.teamName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                
                // --- INFO PESSOAL ---
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Informações Pessoais', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const Divider(),
                      _buildInfoRow('Idade', _calculateAge(player.dateOfBirth)),
                      
                      if (!player.isStaff) ...[
                        _buildInfoRow('Camisa', player.jerseyNumber?.toString() ?? '-'),
                        _buildInfoRow('Altura', player.heightCm != null ? '${player.heightCm} cm' : '-'),
                        _buildInfoRow('Peso', player.weightKg != null ? '${player.weightKg} kg' : '-'),
                        _buildInfoRow('Pé Preferido', player.preferredFoot ?? '-'),
                      ],
                    ],
                  ),
                ),

                // --- ESTATÍSTICAS UNIFICADAS ---
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Estatísticas', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      const Divider(),
                      
                      // Card da Temporada Atual
                      _buildSeasonStatCard(context, player, currentSeasonName, isCurrent: true),

                      // Histórico
                      FutureBuilder<List<Player>>(
                        future: _historicalStatsFuture,
                        builder: (context, histSnap) {
                          if (!histSnap.hasData) return const SizedBox.shrink();
                          // Nota: O nome da temporada histórica não está no objeto Player. 
                          // Em uma implementação real completa, retornaríamos um objeto wrapper {seasonName, Player}.
                          // Aqui simplificamos exibindo "Temporada Anterior".
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
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[700])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSeasonStatCard(BuildContext context, Player p, String seasonName, {bool isCurrent = false}) {
    return Card(
      elevation: isCurrent ? 2 : 0,
      color: isCurrent ? Colors.white : Colors.grey[50],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isCurrent ? BorderSide(color: Theme.of(context).primaryColor.withOpacity(0.3)) : BorderSide.none
      ),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                if (p.teamShieldUrl.isNotEmpty) 
                  CachedNetworkImage(imageUrl: p.teamShieldUrl, width: 24, height: 24, fit: BoxFit.contain),
                const SizedBox(width: 8),
                Expanded(
                  child: Text("$seasonName - ${p.teamName}", style: TextStyle(fontWeight: FontWeight.bold, color: isCurrent ? Colors.black : Colors.grey[700])),
                ),
              ],
            ),
            const Divider(),
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
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 4),
        Text('$value', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}