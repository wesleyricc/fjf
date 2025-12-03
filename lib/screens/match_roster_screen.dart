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

// Widgets
import '../widgets/player_display_card.dart';
import '../widgets/sponsor_banner_rotator.dart';
import 'player_profile_screen.dart';

class MatchRosterScreen extends StatefulWidget {
  final String matchId;
  final String team1Id;
  final String team2Id;
  final String team1Name;
  final String team2Name;
  final String team1ShieldUrl;
  final String team2ShieldUrl;
  final Timestamp? datetime;
  final String? location;

  const MatchRosterScreen({
    super.key,
    required this.matchId,
    required this.team1Id,
    required this.team2Id,
    required this.team1Name,
    required this.team2Name,
    required this.team1ShieldUrl,
    required this.team2ShieldUrl,
    required this.datetime,
    required this.location,
  });

  @override
  State<MatchRosterScreen> createState() => _MatchRosterScreenState();
}

class _MatchRosterScreenState extends State<MatchRosterScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance; // Para update direto se necessário

  bool _isLoading = true;
  
  // Listas Completas
  List<Player> _team1Players = [];
  List<Player> _team2Players = [];
  
  // Titulares Time 1
  Player? _team1TitularGoalkeeper;
  Player? _team1Fixo;
  Player? _team1Ala1;
  Player? _team1Ala2;
  Player? _team1Pivo;
  List<Player> _team1Reserves = [];
  
  // Titulares Time 2
  Player? _team2TitularGoalkeeper;
  Player? _team2Fixo;
  Player? _team2Ala1;
  Player? _team2Ala2;
  Player? _team2Pivo;
  List<Player> _team2Reserves = [];

  Color? _team1Color;
  Color? _team2Color;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    try {
      // 1. Busca Jogadores (Usando Streams convertidas para Future ou Fetch direto)
      // Como a Stream retorna lista atualizada, vamos pegar o primeiro evento
      final t1 = await _firestoreService.streamPlayers(seasonId, teamId: widget.team1Id).first;
      final t2 = await _firestoreService.streamPlayers(seasonId, teamId: widget.team2Id).first;

      // Filtra apenas jogadores (sem staff) para a quadra
      _team1Players = t1.where((p) => !p.isStaff).toList();
      _team2Players = t2.where((p) => !p.isStaff).toList();

      // 2. Busca Cores e Titulares Salvos dos Times
      final t1Doc = await _firestoreService.getTeam(widget.team1Id, seasonId);
      final t2Doc = await _firestoreService.getTeam(widget.team2Id, seasonId);

      // (Nota: Team model não tem cor ainda, assumindo que está no documento ou precisamos adicionar ao model. 
      // Por enquanto, faremos um fetch manual rápido para a cor se não estiver no model, ou assumiremos null)
      // Como o Team Model não tem 'color', vamos pular a cor ou adicionar depois.
      // Assumindo que a cor é visual apenas:
      
      final starters1 = t1Doc?.defaultStarters ?? [];
      final starters2 = t2Doc?.defaultStarters ?? [];

      _calculateLineups(_team1Players, starters1, true);
      _calculateLineups(_team2Players, starters2, false);

    } catch (e) {
      debugPrint("Erro ao carregar elencos: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _calculateLineups(List<Player> allPlayers, List<String> savedStarterIds, bool isTeam1) {
    // Separa quem está salvo como titular
    List<Player> starters = allPlayers.where((p) => savedStarterIds.contains(p.id)).toList();
    List<Player> reserves = allPlayers.where((p) => !savedStarterIds.contains(p.id)).toList();

    Player? gk, fixo, ala1, ala2, pivo;

    // Lógica de Atribuição Inteligente
    // 1. Goleiro
    gk = starters.firstWhere((p) => p.isGoalkeeper, orElse: () => 
         reserves.firstWhere((p) => p.isGoalkeeper, orElse: () => 
         allPlayers.firstWhere((p) => p.isGoalkeeper, orElse: () => allPlayers.first))); // Fallback seguro
    
    // Remove o escolhido das listas para não duplicar
    starters.remove(gk);
    reserves.remove(gk); // Caso tenha vindo da reserva no fallback

    // Função auxiliar para pegar próximo disponível (prioriza starters salvos)
    Player? pickNext(String? preferredPos) {
      Player? p;
      // Tenta achar titular com a posição
      try { p = starters.firstWhere((x) => x.position == preferredPos); } catch (_) {}
      
      // Se não, pega qualquer titular sobrando
      if (p == null && starters.isNotEmpty) p = starters.first;
      
      // Se não tem titulares salvos, pega da reserva
      if (p == null) {
         try { p = reserves.firstWhere((x) => x.position == preferredPos); } catch (_) {}
         if (p == null && reserves.isNotEmpty) p = reserves.first;
      }
      
      if (p != null) {
        starters.remove(p);
        reserves.remove(p);
      }
      return p;
    }

    fixo = pickNext('Fixo');
    ala1 = pickNext('Ala');
    ala2 = pickNext('Ala');
    pivo = pickNext('Pivô');

    // Reconstrói a reserva com quem sobrou
    // (Pode ser que algum titular salvo não tenha sido usado se a lógica falhou, devolve pra reserva)
    reserves.addAll(starters); 
    
    // Ordena reserva por número
    reserves.sort((a, b) => (a.jerseyNumber ?? 99).compareTo(b.jerseyNumber ?? 99));

    setState(() {
      if (isTeam1) {
        _team1TitularGoalkeeper = gk; _team1Fixo = fixo; _team1Ala1 = ala1; _team1Ala2 = ala2; _team1Pivo = pivo;
        _team1Reserves = reserves;
      } else {
        _team2TitularGoalkeeper = gk; _team2Fixo = fixo; _team2Ala1 = ala1; _team2Ala2 = ala2; _team2Pivo = pivo;
        _team2Reserves = reserves;
      }
    });
  }

  Future<void> _swapPlayer(bool isTeam1, Player playerOut, Player playerIn, String positionKey) async {
    setState(() {
      if (isTeam1) {
        _team1Reserves.add(playerOut);
        _team1Reserves.remove(playerIn);
        _team1Reserves.sort((a, b) => (a.jerseyNumber ?? 99).compareTo(b.jerseyNumber ?? 99));
        
        if (_team1TitularGoalkeeper == playerOut) _team1TitularGoalkeeper = playerIn;
        else if (_team1Fixo == playerOut) _team1Fixo = playerIn;
        else if (_team1Ala1 == playerOut) _team1Ala1 = playerIn;
        else if (_team1Ala2 == playerOut) _team1Ala2 = playerIn;
        else if (_team1Pivo == playerOut) _team1Pivo = playerIn;
      } else {
        _team2Reserves.add(playerOut);
        _team2Reserves.remove(playerIn);
        _team2Reserves.sort((a, b) => (a.jerseyNumber ?? 99).compareTo(b.jerseyNumber ?? 99));

        if (_team2TitularGoalkeeper == playerOut) _team2TitularGoalkeeper = playerIn;
        else if (_team2Fixo == playerOut) _team2Fixo = playerIn;
        else if (_team2Ala1 == playerOut) _team2Ala1 = playerIn;
        else if (_team2Ala2 == playerOut) _team2Ala2 = playerIn;
        else if (_team2Pivo == playerOut) _team2Pivo = playerIn;
      }
    });

    // Salva no banco (apenas IDs)
    final teamId = isTeam1 ? widget.team1Id : widget.team2Id;
    final List<Player?> currentStarters = isTeam1 
        ? [_team1TitularGoalkeeper, _team1Fixo, _team1Ala1, _team1Ala2, _team1Pivo]
        : [_team2TitularGoalkeeper, _team2Fixo, _team2Ala1, _team2Ala2, _team2Pivo];
    
    final List<String> ids = currentStarters.where((p) => p != null).map((p) => p!.id).toList();
    
    // Atualiza campo 'default_starters'
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    // Aqui usamos acesso direto para update simples, ou adicionamos método no Service
    try {
      final ref = (seasonId == FirestoreService.LEGACY_ID)
          ? _firestore.collection('teams').doc(teamId)
          : _firestore.collection('championships').doc(seasonId).collection('teams_participation').doc(teamId);
      
      await ref.update({'default_starters': ids});
    } catch (e) {
      debugPrint("Erro ao salvar escalação: $e");
    }
  }

  void _showSubstituteDialog(bool isTeam1, Player currentPlayer, String posKey) {
    final reserves = isTeam1 ? _team1Reserves : _team2Reserves;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Substituir ${currentPlayer.name}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: reserves.length,
            itemBuilder: (ctx, idx) {
              final p = reserves[idx];
              return ListTile(
                leading: Icon(p.isGoalkeeper ? Icons.pan_tool : Icons.person),
                title: Text(p.name),
                subtitle: Text("#${p.jerseyNumber ?? '-'}"),
                onTap: () {
                  Navigator.pop(ctx);
                  _swapPlayer(isTeam1, currentPlayer, p, posKey);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escalação')),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildMatchHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildTeamSection(true),
                        const Divider(thickness: 2),
                        _buildTeamSection(false),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: const SponsorBannerRotator(),
    );
  }

  Widget _buildMatchHeader() {
    String dateStr = widget.datetime != null ? DateFormat('dd/MM HH:mm').format(widget.datetime!.toDate()) : '-';
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[200],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(widget.team1Name, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                const Text("VS", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                Text(dateStr, style: const TextStyle(fontSize: 10)),
              ],
            ),
          ),
          Expanded(child: Text(widget.team2Name, textAlign: TextAlign.left, style: const TextStyle(fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildTeamSection(bool isTeam1) {
    final name = isTeam1 ? widget.team1Name : widget.team2Name;
    final shield = isTeam1 ? widget.team1ShieldUrl : widget.team2ShieldUrl;
    
    // Titulares
    final gk = isTeam1 ? _team1TitularGoalkeeper : _team2TitularGoalkeeper;
    final f = isTeam1 ? _team1Fixo : _team2Fixo;
    final a1 = isTeam1 ? _team1Ala1 : _team2Ala1;
    final a2 = isTeam1 ? _team1Ala2 : _team2Ala2;
    final p = isTeam1 ? _team1Pivo : _team2Pivo;
    
    final reserves = isTeam1 ? _team1Reserves : _team2Reserves;

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if(shield.isNotEmpty) CachedNetworkImage(imageUrl: shield, height: 30, width: 30),
              const SizedBox(width: 8),
              Text(name, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 10),
          
          // Quadra Visual (Simplificada em Lista para MVP, ou use o widget de quadra anterior)
          // Aqui vou usar uma lista de Cards para representar as posições, mais limpo e seguro
          Wrap(
            spacing: 8, runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if(gk!=null) _buildPlayerCard(gk, "Goleiro", isTeam1, "GK"),
              if(f!=null) _buildPlayerCard(f, "Fixo", isTeam1, "Fixo"),
              if(a1!=null) _buildPlayerCard(a1, "Ala", isTeam1, "Ala1"),
              if(a2!=null) _buildPlayerCard(a2, "Ala", isTeam1, "Ala2"),
              if(p!=null) _buildPlayerCard(p, "Pivô", isTeam1, "Pivo"),
            ],
          ),
          
          const SizedBox(height: 16),
          const Text("Reservas", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: reserves.map((r) => _buildReservaCard(r)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerCard(Player p, String posLabel, bool isTeam1, String posKey) {
    final isAuthenticated = Provider.of<AuthService>(context).isAuthenticated;
    
    return GestureDetector(
      onTap: isAuthenticated 
          ? () => _showSubstituteDialog(isTeam1, p, posKey)
          : () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerProfileScreen(playerId: p.id))),
      child: Column(
        children: [
          // Reutilizando o PlayerDisplayCard existente (precisa ser atualizado para aceitar Player model no futuro, mas aqui passamos params)
          PlayerDisplayCard(
            playerName: p.name,
            jerseyNumber: p.jerseyNumber ?? 0,
            yellowCards: p.yellowCards,
            redCards: p.redCards,
            isSuspended: p.isSuspended,
            teamShieldUrl: p.teamShieldUrl,
          ),
          Text(posLabel, style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
        ],
      ),
    );
  }

  Widget _buildReservaCard(Player p) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerProfileScreen(playerId: p.id))),
      child: PlayerDisplayCard(
        playerName: p.name,
        jerseyNumber: p.jerseyNumber ?? 0,
        yellowCards: p.yellowCards,
        redCards: p.redCards,
        isSuspended: p.isSuspended,
        compactMode: true,
      ),
    );
  }
}