import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../services/auth_service.dart';
import '../services/championship_service.dart';
import '../services/team_service.dart'; 
import '../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import '../models/player_model.dart'; 

import '../widgets/player_display_card.dart';
import '../widgets/main_bottom_nav_bar.dart';
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

class _MatchRosterScreenState extends State<MatchRosterScreen> with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance; 

  late TabController _tabController;
  bool _isLoading = true;
  
  List<Player> _team1Players = [];
  List<Player> _team2Players = [];
  
  Player? _team1TitularGoalkeeper;
  Player? _team1Fixo;
  Player? _team1Ala1;
  Player? _team1Ala2;
  Player? _team1Pivo;
  List<Player> _team1Reserves = [];
  
  Player? _team2TitularGoalkeeper;
  Player? _team2Fixo;
  Player? _team2Ala1;
  Player? _team2Ala2;
  Player? _team2Pivo;
  List<Player> _team2Reserves = [];

  Color? _team1Color;
  Color? _team2Color;

  Color? _parseHexColor(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) return null;
    String hex = hexColor.replaceAll('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    // 🚨 Analytics: Rastreia a visualização da prancheta tática do jogo
    AnalyticsService.logCustomScreenView(
      'Match_Roster_Screen',
      parameters: {'match_id': widget.matchId}
    );

    _tabController = TabController(length: 2, vsync: this);
    
    // 🚨 Analytics: Rastreia qual dos dois times o usuário está focando
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        AnalyticsService.logCustomScreenView(
          'Match_Roster_Tab',
          parameters: {
            'match_id': widget.matchId,
            'team_viewed': _tabController.index == 0 ? widget.team1Name : widget.team2Name
          }
        );
      }
    });

    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final service = Provider.of<ChampionshipService>(context, listen: false);
    final teamService = Provider.of<TeamService>(context, listen: false);
    final seasonId = service.currentSeasonId;

    try {
      // --- CORREÇÃO DE PERFORMANCE (Lazy Loading) ---
      // Garante que os jogadores dos dois times estejam carregados
      // fetchRoster é inteligente e só baixa se não estiver em cache válido
      await Future.wait([
        service.fetchRoster(widget.team1Id),
        service.fetchRoster(widget.team2Id),
      ]);

      // Agora pega do cache seguro
      _team1Players = service.getCachedRoster(widget.team1Id).where((p) => !p.isStaff).toList();
      _team2Players = service.getCachedRoster(widget.team2Id).where((p) => !p.isStaff).toList();

      final t1Doc = await teamService.getTeam(widget.team1Id, seasonId);
      final t2Doc = await teamService.getTeam(widget.team2Id, seasonId);

      final starters1 = t1Doc?.defaultStarters ?? [];
      final starters2 = t2Doc?.defaultStarters ?? [];

      _team1Color = _parseHexColor(t1Doc?.primaryColor);
      _team2Color = _parseHexColor(t2Doc?.primaryColor);

      _calculateLineups(_team1Players, starters1, true);
      _calculateLineups(_team2Players, starters2, false);

    } catch (e) {
      debugPrint("Erro ao carregar elencos: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _calculateLineups(List<Player> allPlayers, List<String> savedStarterIds, bool isTeam1) {
    List<Player> pool = List.from(allPlayers);
    List<Player> starters = pool.where((p) => savedStarterIds.contains(p.id)).toList();
    List<Player> reserves = pool.where((p) => !savedStarterIds.contains(p.id)).toList();

    Player? gk, fixo, ala1, ala2, pivo;

    gk = starters.firstWhere((p) => p.isGoalkeeper, orElse: () => 
         reserves.firstWhere((p) => p.isGoalkeeper, orElse: () => 
         pool.firstWhere((p) => p.isGoalkeeper, orElse: () => pool.first)));
    
    if (starters.contains(gk)) starters.remove(gk);
    if (reserves.contains(gk)) reserves.remove(gk);

    Player? pickNext(String? preferredPos) {
      Player? p;
      try { p = starters.firstWhere((x) => x.position == preferredPos); } catch (_) {}
      if (p == null && starters.isNotEmpty) p = starters.first;
      if (p == null) {
         try { p = reserves.firstWhere((x) => x.position == preferredPos); } catch (_) {}
         if (p == null && reserves.isNotEmpty) p = reserves.first;
      }
      if (p != null) {
        if (starters.contains(p)) starters.remove(p);
        if (reserves.contains(p)) reserves.remove(p);
      }
      return p;
    }

    fixo = pickNext('Fixo');
    ala1 = pickNext('Ala');
    ala2 = pickNext('Ala');
    pivo = pickNext('Pivô');

    reserves.addAll(starters); 
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

    final teamId = isTeam1 ? widget.team1Id : widget.team2Id;
    final List<Player?> currentStarters = isTeam1 
        ? [_team1TitularGoalkeeper, _team1Fixo, _team1Ala1, _team1Ala2, _team1Pivo]
        : [_team2TitularGoalkeeper, _team2Fixo, _team2Ala1, _team2Ala2, _team2Pivo];
    
    final List<String> ids = currentStarters.where((p) => p != null).map((p) => p!.id).toList();
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    
    try {
      final ref = _firestore
          .collection('championships')
          .doc(seasonId)
          .collection('teams_participation')
          .doc(teamId);
      await ref.update({'default_starters': ids});
    } catch (e) {
      debugPrint("Erro ao salvar: $e");
    }
  }

  void _showSubstituteDialog(bool isTeam1, Player currentPlayer, String posKey) {
    final reserves = isTeam1 ? _team1Reserves : _team2Reserves;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text('Substituir ${currentPlayer.name}'),
            subtitle: const Text("Escolha quem entra em campo"),
            trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: reserves.length,
              itemBuilder: (ctx, idx) {
                final p = reserves[idx];
                return ListTile(
                  title: Text(p.name),
                  subtitle: Text('Camisa ${p.jerseyNumber ?? "-"}'),
                  trailing: const Icon(Icons.swap_horiz, color: Colors.green),
                  onTap: () {
                    Navigator.pop(ctx);
                    _swapPlayer(isTeam1, currentPlayer, p, posKey);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final seasonName = Provider.of<ChampionshipService>(context).currentSeasonName;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Escalação', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(seasonName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w300)),
          ],
        ),
        elevation: 0,
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildMatchInfoCard(),
                Container(
                  color: Theme.of(context).primaryColor.withOpacity(0.05),
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: Theme.of(context).primaryColor,
                    indicatorWeight: 3,
                    labelColor: Theme.of(context).primaryColor,
                    unselectedLabelColor: Colors.grey,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                    tabs: [
                      Tab(text: widget.team1Name.toUpperCase()),
                      Tab(text: widget.team2Name.toUpperCase()),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTeamTacticalView(true),
                      _buildTeamTacticalView(false),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: const MainBottomNavBar(currentRoute: '/match-roster'),
    );
  }

  Widget _buildMatchInfoCard() {
    String dateStr = widget.datetime != null 
        ? DateFormat('dd/MM • HH:mm').format(widget.datetime!.toDate()) 
        : 'Data a definir';
        
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildTeamLogo(widget.team1ShieldUrl, widget.team1Name),
          Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300)
                ),
                child: const Text("VS", style: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(height: 6),
              Text(
                dateStr, 
                style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)
              ),
              if (widget.location != null)
                Text(
                  widget.location!,
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                )
            ],
          ),
          _buildTeamLogo(widget.team2ShieldUrl, widget.team2Name),
        ],
      ),
    );
  }

  Widget _buildTeamLogo(String url, String name) {
    return Column(
      children: [
        SizedBox(
          width: 50,
          height: 50,
          child: url.isNotEmpty 
              ? CachedNetworkImage(imageUrl: url, fit: BoxFit.contain)
              : const Icon(Icons.shield, color: Colors.grey, size: 40),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 80,
          child: Text(
            name, 
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)
          ),
        ),
      ],
    );
  }

  Widget _buildTeamTacticalView(bool isTeam1) {
    final gk = isTeam1 ? _team1TitularGoalkeeper : _team2TitularGoalkeeper;
    final f = isTeam1 ? _team1Fixo : _team2Fixo;
    final a1 = isTeam1 ? _team1Ala1 : _team2Ala1;
    final a2 = isTeam1 ? _team1Ala2 : _team2Ala2;
    final p = isTeam1 ? _team1Pivo : _team2Pivo;
    
    final reserves = isTeam1 ? _team1Reserves : _team2Reserves;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: [
          Container(
            height: 480, 
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green[800], 
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: const Offset(0, 4))],
              image: const DecorationImage(
                image: AssetImage('assets/futsal_court.png'),
                fit: BoxFit.cover,
                opacity: 0.9,
              ),
            ),
            child: Stack(
              children: [
                if (p != null) _buildPositionedPlayer(p, isTeam1, "Pivo", 0.05, 0.5),
                if (a1 != null) _buildPositionedPlayer(a1, isTeam1, "Ala", 0.4, 0.15),
                if (a2 != null) _buildPositionedPlayer(a2, isTeam1, "Ala", 0.4, 0.85),
                if (f != null) _buildPositionedPlayer(f, isTeam1, "Fixo", 0.65, 0.5),
                if (gk != null) _buildPositionedPlayer(gk, isTeam1, "GK", 0.85, 0.5),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Icon(Icons.people_outline, color: Colors.grey[700]),
                const SizedBox(width: 8),
                Text("Banco de Reservas", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                const Spacer(),
                Text("${reserves.length} jogadores", style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          
          if (reserves.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Text("Sem reservas cadastrados."))
          else
            SizedBox(
              height: 110,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: reserves.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (ctx, idx) {
                  final r = reserves[idx];
                  return _buildReserveCard(r, isTeam1);
                },
              ),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildPositionedPlayer(Player p, bool isTeam1, String posKey, double topPct, double leftPct) {
    return Align(
      alignment: FractionalOffset(leftPct, topPct),
      child: GestureDetector(
        onTap: () {
          final auth = Provider.of<AuthService>(context, listen: false);
          if (auth.isAuthenticated) {
            _showSubstituteDialog(isTeam1, p, posKey);
          } else {
            Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerProfileScreen(playerId: p.id)));
          }
        },
        child: FractionallySizedBox(
          widthFactor: 0.25, 
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PlayerDisplayCard(
                playerName: "", 
                jerseyNumber: p.jerseyNumber ?? 0,
                yellowCards: p.yellowCards,
                redCards: p.redCards,
                isSuspended: p.isSuspended,
                compactMode: true, 
                teamShieldUrl: null, 
                teamColor: isTeam1 ? _team1Color : _team2Color,
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                ),
                child: Text(
                  p.name.split(' ').first, 
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 4, color: Colors.black)]),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReserveCard(Player p, bool isTeam1) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerProfileScreen(playerId: p.id))),
      child: Container(
        width: 70,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PlayerDisplayCard(
              playerName: p.name,
              jerseyNumber: p.jerseyNumber ?? 0,
              yellowCards: p.yellowCards,
              redCards: p.redCards,
              isSuspended: p.isSuspended,
              compactMode: true,
              teamColor: isTeam1 ? _team1Color : _team2Color,
            ),
          ],
        ),
      ),
    );
  }
}