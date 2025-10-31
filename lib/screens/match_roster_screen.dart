// lib/screens/match_roster_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart'; // Para formatar data
import '../services/admin_service.dart'; // Para acessar regras de cartões
import '../widgets/sponsor_banner_rotator.dart'; // Para o rodapé
import 'package:firebase_analytics/firebase_analytics.dart';

class MatchRosterScreen extends StatefulWidget {
  final DocumentSnapshot match;
  const MatchRosterScreen({super.key, required this.match});

  @override
  State<MatchRosterScreen> createState() => _MatchRosterScreenState();
}

class _MatchRosterScreenState extends State<MatchRosterScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<DocumentSnapshot> _homePlayers = [];
  List<DocumentSnapshot> _awayPlayers = [];
  bool _isLoading = true;

  // Variáveis para os dados da partida
  late String homeTeamId;
  late String awayTeamId;
  late String homeTeamName;
  late String awayTeamName;
  late String homeShieldUrl;
  late String awayShieldUrl;

  @override
  void initState() {
    super.initState();
    // Extrai os dados da partida
    final data = widget.match.data() as Map<String, dynamic>? ?? {};
    homeTeamId = data['team_home_id'] ?? '';
    awayTeamId = data['team_away_id'] ?? '';
    homeTeamName = data['team_home_name'] ?? 'Time Casa';
    awayTeamName = data['team_away_name'] ?? 'Time Fora';
    homeShieldUrl = data['team_home_shield'] ?? '';
    awayShieldUrl = data['team_away_shield'] ?? '';
    
    _fetchRosters();

    // --- 2. ADICIONE A CHAMADA DO ANALYTICS ---
    try {
      // Usa as variáveis que você já tem no initState
      final data = widget.match.data() as Map<String, dynamic>? ?? {};
      final String homeName = data['team_home_name'] ?? 'Casa';
      final String awayName = data['team_away_name'] ?? 'Fora';
      FirebaseAnalytics.instance.logScreenView(
        screenName: '/match/roster/$homeName-vs-$awayName',
      );
    } catch (e) {
      debugPrint("Erro ao logar screen_view (MatchRosterScreen): $e");
    }
    // --- FIM ---
  }

  Future<void> _fetchRosters() async {
    if (homeTeamId.isEmpty || awayTeamId.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _isLoading = false);
      });
      return;
    }
    
    try {
      // 1. Busca Jogadores da Casa
      final homeQuery = await _firestore
          .collection('players')
          .where('team_id', isEqualTo: homeTeamId)
          .where('isActive', isEqualTo: true)
          .where('is_staff', isEqualTo: false)
          .orderBy('jersey_number')
          .orderBy('name')
          .get();
      _homePlayers = homeQuery.docs;

      // 2. Busca Jogadores Visitantes
      final awayQuery = await _firestore
          .collection('players')
          .where('team_id', isEqualTo: awayTeamId)
          .where('isActive', isEqualTo: true)
          .where('is_staff', isEqualTo: false)
          .orderBy('jersey_number')
          .orderBy('name')
          .get();
      _awayPlayers = awayQuery.docs;

    } catch (e) {
      debugPrint("Erro ao buscar escalações (MatchRosterScreen): $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao buscar jogadores. O Firestore pode estar criando um índice. Tente novamente em alguns minutos. Erro: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Widget auxiliar para o ícone de status (Pendurado/Suspenso)
  Widget _buildPlayerStatusIcon({required bool isSuspended, required bool isPending}) {
     if (isSuspended) {
       return const Tooltip(
         message: 'Suspenso',
         child: Icon(Icons.style, color: Colors.red, size: 20),
       );
     }
     if (isPending) {
        return Tooltip(
          message: 'Pendurado (${AdminService.pendingYellowCards} CA)',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.style, color: Colors.yellow[700], size: 12),
              const SizedBox(width: 1),
              Icon(Icons.style, color: Colors.yellow[700], size: 12),
            ],
          ),
        );
     }
     return const SizedBox(width: 24); // Placeholder para alinhar
  }

  // --- FUNÇÃO _buildPlayerList ATUALIZADA ---
  Widget _buildPlayerList(String teamName, String shieldUrl, List<DocumentSnapshot> players) {
    return Column(
      children: [
        // Cabeçalho da Equipe
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (shieldUrl.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: shieldUrl,
                  width: 60, height: 60, fit: BoxFit.contain,
                  placeholder: (c,u) => const Icon(Icons.shield, size: 60),
                  errorWidget: (c,u,e) => const Icon(Icons.shield, size: 60),
                ),
              const SizedBox(width: 10),
              Flexible( 
                child: Text(
                  teamName, 
                  style: Theme.of(context).textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        // Lista de Jogadores
        if (players.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('Nenhum jogador cadastrado.', style: TextStyle(color: Colors.grey)),
          ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12.0),
          elevation: 1,
          child: ListView.builder(
            itemCount: players.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero, // Remove padding do ListView
            itemBuilder: (context, index) {
              final player = players[index];
              final data = player.data() as Map<String, dynamic>;
              final int? number = data['jersey_number'];
              final String name = data['name'] ?? '...';
              final bool isSuspended = data['is_suspended'] ?? false;
              final int currentYellows = data['yellow_cards'] ?? 0;
              final bool isPending = (currentYellows == AdminService.pendingYellowCards) && !isSuspended;

              return ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                // --- MUDANÇA AQUI: Padding vertical zerado ---
                contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 0.0), 
                // --- FIM DA MUDANÇA ---
                leading: SizedBox(
                  width: 30,
                  child: Text(
                    number?.toString() ?? '-',
                    style: TextStyle(
                      fontWeight: FontWeight.bold, 
                      fontSize: 16,
                      color: isSuspended ? Colors.grey[400] : Colors.black87,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                title: Text(
                  name,
                  style: TextStyle(
                    fontSize: 14,
                    decoration: isSuspended ? TextDecoration.lineThrough : TextDecoration.none,
                    color: isSuspended ? Colors.grey[600] : Colors.black,
                  ),
                ),
                trailing: _buildPlayerStatusIcon(isSuspended: isSuspended, isPending: isPending),
              );
            },
          ),
        ),
      ],
    );
  }
  // --- FIM DA FUNÇÃO ---

  // Widget Cabeçalho da Partida (como antes)
  Widget _buildMatchDetails() {
    final data = widget.match.data() as Map<String, dynamic>? ?? {};
    final String location = data['location'] ?? 'Local a definir';
    
    String formattedDate = 'Data a definir';
    String formattedTime = 'Horário a definir';
    if (data['datetime'] != null && data['datetime'] is Timestamp) {
      final DateTime date = (data['datetime'] as Timestamp).toDate();
      formattedDate = DateFormat('dd/MM/yyyy (EEE)', 'pt_BR').format(date);
      formattedTime = DateFormat('HH:mm', 'pt_BR').format(date);
    }
    
    return Card(
      elevation: 0,
      color: Colors.grey[100],
      margin: const EdgeInsets.all(0),
      shape: const RoundedRectangleBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.calendar_today_outlined, size: 16, color: Colors.black54),
                const SizedBox(width: 8),
                Text(formattedDate, style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(width: 16),
                const Icon(Icons.access_time_outlined, size: 16, color: Colors.black54),
                const SizedBox(width: 8),
                Text(formattedTime, style: const TextStyle(fontWeight: FontWeight.w500)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_on_outlined, size: 16, color: Colors.black54),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    location, 
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$homeTeamName x $awayTeamName', overflow: TextOverflow.ellipsis),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // 1. Cabeçalho (Data, Hora, Local)
                  _buildMatchDetails(),
                  
                  // 2. Lista Time da Casa
                  _buildPlayerList(homeTeamName, homeShieldUrl, _homePlayers),

                  // 3. Divisor
                  const Divider(height: 24, thickness: 1, indent: 16, endIndent: 16),

                  // 4. Lista Time Visitante
                  _buildPlayerList(awayTeamName, awayShieldUrl, _awayPlayers),

                  // 5. Espaço para o banner
                  const SizedBox(height: 16), 
                ],
              ),
            ),
      bottomNavigationBar: const SponsorBannerRotator(),
    );
  }
}