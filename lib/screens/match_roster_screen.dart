// lib/screens/match_roster_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/player_display_card.dart';
import '../services/admin_service.dart';
import '../widgets/sponsor_banner_rotator.dart'; 
import 'package:intl/intl.dart';
import 'player_profile_screen.dart';

// --- CLASSE 'FakeDocumentSnapshot' REMOVIDA ---
// (Não é mais necessária, corrigindo o alerta 'sealed')

class MatchRosterScreen extends StatefulWidget {
  static const routeName = '/match-roster';
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
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Estados dos jogadores
  bool _isLoading = true;
  List<Map<String, dynamic>> _team1Players = [];
  List<Map<String, dynamic>> _team2Players = [];
  
  Map<String, dynamic>? _team1TitularGoalkeeper;
  Map<String, dynamic>? _team1Fixo;
  Map<String, dynamic>? _team1Ala1;
  Map<String, dynamic>? _team1Ala2;
  Map<String, dynamic>? _team1Pivo;
  List<Map<String, dynamic>> _team1Reserves = [];
  
  Map<String, dynamic>? _team2TitularGoalkeeper;
  Map<String, dynamic>? _team2Fixo;
  Map<String, dynamic>? _team2Ala1;
  Map<String, dynamic>? _team2Ala2;
  Map<String, dynamic>? _team2Pivo;
  List<Map<String, dynamic>> _team2Reserves = [];

  Color? _team1Color;
  Color? _team2Color;

  @override
  void initState() {
    super.initState();
    _fetchAndProcessRosters();
  }

  Color? _parseColor(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) {
      return null;
    }
    try {
      final String formattedHex = 'ff${hexColor.replaceAll('#', '')}';
      return Color(int.parse(formattedHex, radix: 16));
    } catch (e) {
      debugPrint("Erro ao converter cor: $hexColor. $e");
      return null;
    }
  }

  // --- NOVA FUNÇÃO PARA SALVAR NO FIRESTORE ---
  Future<void> _saveLineupToFirestore(bool isTeam1) async {
    try {
      List<String> newStartersIds = [];

      // Coleta os jogadores titulares atuais baseados no estado da tela
      if (isTeam1) {
        if (_team1TitularGoalkeeper != null) newStartersIds.add(_team1TitularGoalkeeper!['id']);
        if (_team1Fixo != null) newStartersIds.add(_team1Fixo!['id']);
        if (_team1Ala1 != null) newStartersIds.add(_team1Ala1!['id']);
        if (_team1Ala2 != null) newStartersIds.add(_team1Ala2!['id']);
        if (_team1Pivo != null) newStartersIds.add(_team1Pivo!['id']);
      } else {
        if (_team2TitularGoalkeeper != null) newStartersIds.add(_team2TitularGoalkeeper!['id']);
        if (_team2Fixo != null) newStartersIds.add(_team2Fixo!['id']);
        if (_team2Ala1 != null) newStartersIds.add(_team2Ala1!['id']);
        if (_team2Ala2 != null) newStartersIds.add(_team2Ala2!['id']);
        if (_team2Pivo != null) newStartersIds.add(_team2Pivo!['id']);
      }

      final String teamId = isTeam1 ? widget.team1Id : widget.team2Id;

      // Atualiza o campo 'default_starters' no documento do time
      await _firestore.collection('teams').doc(teamId).update({
        'default_starters': newStartersIds,
      });

      debugPrint("Escalação salva para o time $teamId: $newStartersIds");

    } catch (e) {
      debugPrint("Erro ao salvar escalação: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar substituição: $e')),
        );
      }
    }
  }

  Future<void> _fetchAndProcessRosters() async {
    if (!mounted) return;
    setState(() { _isLoading = true; });
    try {
      final results = await Future.wait([
        _fetchPlayersForTeam(widget.team1Id),
        _fetchPlayersForTeam(widget.team2Id),
      ]);
      
      _team1Players = results[0];
      _team2Players = results[1];
      
      final teamDocs = await Future.wait([
        _firestore.collection('teams').doc(widget.team1Id).get(const GetOptions(source: Source.server)),
        _firestore.collection('teams').doc(widget.team2Id).get(const GetOptions(source: Source.server)),
      ]);

      // --- CORREÇÃO: Cast desnecessário removido ---
      final team1Data = teamDocs[0].data() ?? {};
      final team2Data = teamDocs[1].data() ?? {};
      // --- FIM DA CORREÇÃO ---

      List<String> startersHomeIds = List<String>.from(team1Data['default_starters'] ?? []);
      List<String> startersAwayIds = List<String>.from(team2Data['default_starters'] ?? []);
      
      _team1Color = _parseColor(team1Data['team_color'] as String?);
      _team2Color = _parseColor(team2Data['team_color'] as String?);
      
      debugPrint("Titulares Padrão Time 1 (${startersHomeIds.length}): $startersHomeIds");
      debugPrint("Titulares Padrão Time 2 (${startersAwayIds.length}): $startersAwayIds");

      _calculateLineups(startersHomeIds, startersAwayIds);
      
    } catch (e) {
       debugPrint("Erro ao carregar elencos: $e");
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar elencos: ${e.toString()}')));
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }
  
  Map<String, dynamic>? _findAndRemovePlayer(List<Map<String, dynamic>> players, String? position) {
    try {
      Map<String, dynamic>? foundPlayer;
      if (position != null) {
        final matchingPlayers = players.where((p) => p['position'] == position).toList();
        if (matchingPlayers.isNotEmpty) {
          foundPlayer = matchingPlayers.first;
        }
      }
      
      if (foundPlayer == null && players.isNotEmpty) {
        foundPlayer = players.first;
      }

      if (foundPlayer != null) {
        players.remove(foundPlayer);
      }
      return foundPlayer;

    } catch (e) {
      return null;
    }
  }

  void _calculateLineups(List<String> startersHomeIds, List<String> startersAwayIds) {
    
    void applyFallbackLogic(bool isTeam1) {
      if (isTeam1) {
        final team1Goalkeepers = _team1Players.where((p) => p['is_goalkeeper']).toList();
        final team1LinePlayers = _team1Players.where((p) => !p['is_goalkeeper']).toList();
        _team1TitularGoalkeeper = team1Goalkeepers.isNotEmpty ? team1Goalkeepers.first : null;
        _team1Fixo = team1LinePlayers.isNotEmpty ? team1LinePlayers[0] : null;
        _team1Ala1 = team1LinePlayers.length > 1 ? team1LinePlayers[1] : null;
        _team1Ala2 = team1LinePlayers.length > 2 ? team1LinePlayers[2] : null;
        _team1Pivo = team1LinePlayers.length > 3 ? team1LinePlayers[3] : null;
        _team1Reserves = team1Goalkeepers.skip(1).toList() + team1LinePlayers.skip(4).toList();
      } else {
        final team2Goalkeepers = _team2Players.where((p) => p['is_goalkeeper']).toList();
        final team2LinePlayers = _team2Players.where((p) => !p['is_goalkeeper']).toList();
        _team2TitularGoalkeeper = team2Goalkeepers.isNotEmpty ? team2Goalkeepers.first : null;
        _team2Fixo = team2LinePlayers.isNotEmpty ? team2LinePlayers[0] : null;
        _team2Ala1 = team2LinePlayers.length > 1 ? team2LinePlayers[1] : null;
        _team2Ala2 = team2LinePlayers.length > 2 ? team2LinePlayers[2] : null;
        _team2Pivo = team2LinePlayers.length > 3 ? team2LinePlayers[3] : null;
        _team2Reserves = team2Goalkeepers.skip(1).toList() + team2LinePlayers.skip(4).toList();
      }
    }

    // --- TIME 1 ---
    if (startersHomeIds.length != 5) {
      debugPrint("TIME 1: Usando Fallback (encontrados ${startersHomeIds.length}/5 titulares)");
      applyFallbackLogic(true);
    } else {
      debugPrint("TIME 1: Usando lógica de Posição");
      final starters1 = _team1Players.where((p) => startersHomeIds.contains(p['id'])).toList();
      _team1Reserves = _team1Players.where((p) => !startersHomeIds.contains(p['id'])).toList();
      
      final gk1 = starters1.where((p) => p['is_goalkeeper'] == true);
      _team1TitularGoalkeeper = gk1.isNotEmpty ? gk1.first : null;
      
      List<Map<String, dynamic>> lineStarters1 = starters1.where((p) => p['is_goalkeeper'] == false).toList();
      
      _team1Fixo = _findAndRemovePlayer(lineStarters1, 'Fixo');
      _team1Ala1 = _findAndRemovePlayer(lineStarters1, 'Ala');
      _team1Ala2 = _findAndRemovePlayer(lineStarters1, 'Ala');
      _team1Pivo = _findAndRemovePlayer(lineStarters1, 'Pivô');

      if (_team1Fixo == null) _team1Fixo = _findAndRemovePlayer(lineStarters1, null);
      if (_team1Ala1 == null) _team1Ala1 = _findAndRemovePlayer(lineStarters1, null);
      if (_team1Ala2 == null) _team1Ala2 = _findAndRemovePlayer(lineStarters1, null);
      if (_team1Pivo == null) _team1Pivo = _findAndRemovePlayer(lineStarters1, null);
    }

    // --- TIME 2 ---
    if (startersAwayIds.length != 5) {
      debugPrint("TIME 2: Usando Fallback (encontrados ${startersAwayIds.length}/5 titulares)");
      applyFallbackLogic(false);
    } else {
      debugPrint("TIME 2: Usando lógica de Posição");
      final starters2 = _team2Players.where((p) => startersAwayIds.contains(p['id'])).toList();
      _team2Reserves = _team2Players.where((p) => !startersAwayIds.contains(p['id'])).toList();
      
      final gk2 = starters2.where((p) => p['is_goalkeeper'] == true);
      _team2TitularGoalkeeper = gk2.isNotEmpty ? gk2.first : null;
      
      List<Map<String, dynamic>> lineStarters2 = starters2.where((p) => p['is_goalkeeper'] == false).toList();

      _team2Fixo = _findAndRemovePlayer(lineStarters2, 'Fixo');
      _team2Ala1 = _findAndRemovePlayer(lineStarters2, 'Ala');
      _team2Ala2 = _findAndRemovePlayer(lineStarters2, 'Ala');
      _team2Pivo = _findAndRemovePlayer(lineStarters2, 'Pivô');

      if (_team2Fixo == null) _team2Fixo = _findAndRemovePlayer(lineStarters2, null);
      if (_team2Ala1 == null) _team2Ala1 = _findAndRemovePlayer(lineStarters2, null);
      if (_team2Ala2 == null) _team2Ala2 = _findAndRemovePlayer(lineStarters2, null);
      if (_team2Pivo == null) _team2Pivo = _findAndRemovePlayer(lineStarters2, null);
    }
    
    _team1Reserves.sort((a,b) => (a['jersey_number'] ?? 99).compareTo(b['jersey_number'] ?? 99));
    _team2Reserves.sort((a,b) => (a['jersey_number'] ?? 99).compareTo(b['jersey_number'] ?? 99));
  }

  // --- CORREÇÃO: _showClearSuspensionDialog agora aceita Map e ID ---
  Future<void> _showClearSuspensionDialog(
      BuildContext context, Map<String, dynamic> playerData, String playerId) async {
        
    final playerName = playerData['name'] ?? 'Jogador desconhecido';
    final int currentYellows = playerData['yellow_cards'] ?? 0;
    final int currentReds = playerData['red_cards'] ?? 0;

    bool suspendedByRed = (currentReds > 0 && AdminService.suspensionOnRed);
    bool suspendedByYellow = (currentYellows >= AdminService.suspensionYellowCards);
    
    String reason = "Motivo desconhecido.";
    if (suspendedByRed && suspendedByYellow) {
       reason = "Motivo: Acúmulo de CA e Cartão Vermelho (Suspensão Múltipla).";
    } else if (suspendedByRed) {
       reason = "Motivo: Cartão Vermelho.";
    } else if (suspendedByYellow) {
       reason = "Motivo: Acúmulo de Cartões Amarelos (Limite: ${AdminService.suspensionYellowCards}).";
    }

    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Limpar Suspensão'),
          content: Text(
            'Tem certeza que deseja liberar $playerName?\n\n$reason\n\n'
            'Isso definirá "Suspenso=Falso" e zerará o contador de CV. O contador de CA só será zerado se tiver atingido o limite de ${AdminService.suspensionYellowCards}.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: const Text('Confirmar Liberação'),
              onPressed: () async {
                try {
                  Map<String, dynamic> updateData = {
                    'is_suspended': false,
                    'red_cards': 0,
                  };

                  if (currentYellows >= AdminService.suspensionYellowCards) {
                    updateData['yellow_cards'] = 0;
                    debugPrint("Limpando suspensão: Zerando yellow_cards (era $currentYellows).");
                  } else {
                    debugPrint("Limpando suspensão: Mantendo yellow_cards (era $currentYellows).");
                  }

                  // Atualiza o jogador usando o 'playerId'
                  await _firestore
                      .collection('players')
                      .doc(playerId)
                      .update(updateData);
                  
                  Navigator.of(dialogContext).pop();
                  if (Navigator.of(context).canPop()) { 
                     ScaffoldMessenger.of(context).showSnackBar(
                       SnackBar(content: Text('$playerName liberado da suspensão.')),
                     );
                  }
                } catch (e) {
                  debugPrint("Erro ao liberar jogador: $e");
                   if (Navigator.of(dialogContext).canPop()) {
                     ScaffoldMessenger.of(dialogContext).showSnackBar(
                       SnackBar(content: Text('Erro ao liberar jogador: $e')),
                     );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }
  // --- FIM DA CORREÇÃO ---

  // --- CORREÇÃO: _fetchPlayersForTeam (Cast desnecessário removido) ---
  Future<List<Map<String, dynamic>>> _fetchPlayersForTeam(String teamId) async {
    final playersSnapshot = await _firestore
        .collection('players')
        .where('team_id', isEqualTo: teamId)
        .where('isActive', isEqualTo: true)
        .where('is_staff', isEqualTo: false)
        .orderBy('jersey_number')
        .orderBy('name')
        .get();

    return playersSnapshot.docs.map((doc) {
      final data = doc.data(); 
      return {
        'id': doc.id,
        ...data,
        'yellow_cards': data['yellow_cards'] ?? 0,
        'red_cards': data['red_cards'] ?? 0,
        'is_suspended': data['is_suspended'] ?? false,
        'is_goalkeeper': data['is_goalkeeper'] ?? false,
        'position': data['position'], 
      };
    }).toList();
  }
  // --- FIM DA CORREÇÃO ---

  Future<void> _showPlayerSelectionDialog({
    required bool isTeam1, 
    required bool isGoalkeeper, 
    required Map<String, dynamic> currentPlayerOnCourt,
    required String positionKey,
  }) async {
    
    if (!AdminService.isAdmin) return;

    final availableReserves = isTeam1 ? _team1Reserves : _team2Reserves;
    
    final Map<String, dynamic>? selectedPlayer = await showDialog<Map<String, dynamic>>(
       context: context,
       builder: (ctx) => AlertDialog(
          title: Text("Substituir ${currentPlayerOnCourt['name']}"),
          content: Container(
             width: double.maxFinite,
             child: ListView.builder(
                shrinkWrap: true,
                itemCount: availableReserves.length,
                itemBuilder: (context, index) {
                   final reserve = availableReserves[index];
                   
                   // --- FILTRO REMOVIDO ---
                   // Agora todos os reservas aparecem, independente se a vaga é para GK ou Linha
                   
                   // Define o subtítulo para ajudar a identificar a posição real do jogador
                   final bool reserveIsGk = reserve['is_goalkeeper'] ?? false;
                   final String posDescription = reserveIsGk 
                       ? 'Goleiro' 
                       : (reserve['position'] ?? 'Linha');

                   return ListTile(
                      leading: Icon(
                        reserveIsGk ? Icons.pan_tool : Icons.person,
                        color: Colors.grey[600],
                      ),
                      title: Text(reserve['name'] ?? '...'),
                      subtitle: Text("#${reserve['jersey_number'] ?? '-'} - $posDescription"),
                      onTap: () => Navigator.of(ctx).pop(reserve),
                   );
                }
             )
          ),
          actions: [ 
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Cancelar")) 
          ],
       )
    );

    if (selectedPlayer != null) {
       setState(() {
          final reservesList = isTeam1 ? _team1Reserves : _team2Reserves;
          reservesList.add(currentPlayerOnCourt);
          reservesList.remove(selectedPlayer);
          
          if (isTeam1) {
            switch (positionKey) {
              case 'GK': _team1TitularGoalkeeper = selectedPlayer; break;
              case 'Fixo': _team1Fixo = selectedPlayer; break;
              case 'Ala1': _team1Ala1 = selectedPlayer; break;
              case 'Ala2': _team1Ala2 = selectedPlayer; break;
              case 'Pivo': _team1Pivo = selectedPlayer; break;
            }
          } else {
            switch (positionKey) {
              case 'GK': _team2TitularGoalkeeper = selectedPlayer; break;
              case 'Fixo': _team2Fixo = selectedPlayer; break;
              case 'Ala1': _team2Ala1 = selectedPlayer; break;
              case 'Ala2': _team2Ala2 = selectedPlayer; break;
              case 'Pivo': _team2Pivo = selectedPlayer; break;
            }
          }
          
          _team1Reserves.sort((a,b) => (a['jersey_number'] ?? 99).compareTo(b['jersey_number'] ?? 99));
          _team2Reserves.sort((a,b) => (a['jersey_number'] ?? 99).compareTo(b['jersey_number'] ?? 99));
       });

       await _saveLineupToFirestore(isTeam1); 
    }
  }

  Widget _buildPlayerOnCourt({
    required Map<String, dynamic> player,
    required bool isTeam1,
    required String positionKey,
    required Color? teamColor,
    required double quadraWidth,
    required double quadraHeight,
    required Alignment alignment,
  }) {
    final double left = (alignment.x + 1.0) / 2.0 * quadraWidth;
    final double top = (alignment.y + 1.0) / 2.0 * quadraHeight;

    final double playerCardWidth = 100.0;
    final double playerCardHeight = 70.0;
    
    final double adjustedLeft = left - (playerCardWidth / 2);
    final double adjustedTop = top - (playerCardHeight / 2);

    Widget playerCard = PlayerDisplayCard(
      playerName: player['name'],
      jerseyNumber: player['jersey_number'] ?? 0,
      yellowCards: player['yellow_cards'] ?? 0,
      redCards: player['red_cards'] ?? 0,
      isSuspended: player['is_suspended'] ?? false,
      compactMode: false,
      teamColor: teamColor,
    );

    return Positioned(
      left: adjustedLeft.clamp(0.0, quadraWidth - playerCardWidth),
      top: adjustedTop.clamp(0.0, quadraHeight - playerCardHeight),
      child: GestureDetector(
        onTap: () {
          // Se for Admin, a ação é SUBSTITUIR
          if (AdminService.isAdmin) {
            _showPlayerSelectionDialog(
              isTeam1: isTeam1,
              isGoalkeeper: positionKey == 'GK',
              currentPlayerOnCourt: player,
              positionKey: positionKey,
            );
          } else {
            // Se for Utilizador, a ação é VER PERFIL
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (ctx) => PlayerProfileScreen(playerId: player['id']),
              ),
            );
          }
        },
        // --- FIM DA ALTERAÇÃO ---
        child: playerCard,
      ),
    );
  }

  Widget _buildCourtBackground(double width, double height) {
    try {
      return Image.asset(
        'assets/futsal_court.png', 
        fit: BoxFit.fill,
        width: width,
        height: height,
        errorBuilder: (context, error, stackTrace) {
           return Container(
              color: Colors.green[800],
              width: width,
              height: height,
              child: const Center(child: Text('Imagem da quadra não encontrada.', style: TextStyle(color: Colors.white, fontSize: 12))),
           );
        },
      );
    } catch (e) {
       return Container(
          color: Colors.green[800],
          width: width,
          height: height,
          child: Center(child: Text('Erro ao carregar imagem: $e', style: TextStyle(color: Colors.white, fontSize: 12))),
       );
    }
  }

  Widget _buildMatchDetailsHeader() {
    final String location = widget.location ?? 'Local a definir';
    String formattedDate = 'Data a definir';
    String formattedTime = 'Horário a definir';
    if (widget.datetime != null) {
      final DateTime date = widget.datetime!.toDate();
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
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${widget.team1Name} vs ${widget.team2Name}'),
          bottom: TabBar(
            labelColor: Theme.of(context).colorScheme.onPrimary,
            unselectedLabelColor: Theme.of(context).colorScheme.onPrimary.withOpacity(0.7),
            indicatorColor: Colors.white,
            tabs: const [
              Tab(text: 'Quadra'),
              Tab(text: 'Detalhes'),
            ],
          ),
        ),
        
        body: Column(
          children: [
            _buildMatchDetailsHeader(),
            Expanded(
              child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    children: [
                      _buildCourtView(
                        context,
                        _team1TitularGoalkeeper, _team1Fixo, _team1Ala1, _team1Ala2, _team1Pivo, _team1Reserves,
                        widget.team1Name, widget.team1ShieldUrl, _team1Color,
                        _team2TitularGoalkeeper, _team2Fixo, _team2Ala1, _team2Ala2, _team2Pivo, _team2Reserves,
                        widget.team2Name, widget.team2ShieldUrl, _team2Color,
                      ),
                      _buildDetailsView(context, _team1Players, _team2Players),
                    ],
                  ),
              ),
          ],
        ),
        
        bottomNavigationBar: const SponsorBannerRotator(),
      ),
    );
  }

  Widget _buildCourtView(
    BuildContext context,
    Map<String, dynamic>? team1Goalkeeper,
    Map<String, dynamic>? team1Fixo,
    Map<String, dynamic>? team1Ala1,
    Map<String, dynamic>? team1Ala2,
    Map<String, dynamic>? team1Pivo,
    List<Map<String, dynamic>> team1Reserves,
    String team1Name,
    String team1ShieldUrl,
    Color? team1Color,
    Map<String, dynamic>? team2Goalkeeper,
    Map<String, dynamic>? team2Fixo,
    Map<String, dynamic>? team2Ala1,
    Map<String, dynamic>? team2Ala2,
    Map<String, dynamic>? team2Pivo,
    List<Map<String, dynamic>> team2Reserves,
    String team2Name,
    String team2ShieldUrl,
    Color? team2Color,
  ) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(
                  children: [
                    if (team1ShieldUrl.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: team1ShieldUrl,
                        width: 40,
                        height: 40,
                        fit: BoxFit.contain,
                        placeholder: (context, url) => const CircularProgressIndicator(strokeWidth: 1),
                        errorWidget: (context, url, error) => const Icon(Icons.shield, size: 40),
                      ),
                    Text(team1Name, style: Theme.of(context).textTheme.bodyLarge),
                  ],
                ),
                Column(
                  children: [
                    if (team2ShieldUrl.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: team2ShieldUrl,
                        width: 40,
                        height: 40,
                        fit: BoxFit.contain,
                        placeholder: (context, url) => const CircularProgressIndicator(strokeWidth: 1),
                        errorWidget: (context, url, error) => const Icon(Icons.shield, size: 40),
                      ),
                    Text(team2Name, style: Theme.of(context).textTheme.bodyLarge),
                  ],
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: AspectRatio(
              aspectRatio: 9 / 16,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final quadraWidth = constraints.maxWidth;
                  final quadraHeight = constraints.maxHeight;

                  final team1GKPos = Alignment(0.0, -0.85);
                  final team1FixoPos = Alignment(0.0, -0.55);
                  final team1Ala1Pos = Alignment(-0.6, -0.4);
                  final team1Ala2Pos = Alignment(0.6, -0.4);
                  final team1PivoPos = Alignment(0.0, -0.2); 

                  final team2GKPos = Alignment(0.0, 0.85);
                  final team2FixoPos = Alignment(0.0, 0.55);
                  final team2Ala1Pos = Alignment(-0.6, 0.4);
                  final team2Ala2Pos = Alignment(0.6, 0.4);
                  final team2PivoPos = Alignment(0.0, 0.2); 

                  List<Widget> playersOnCourt = [];

                  if (team1Goalkeeper != null) {
                    playersOnCourt.add(_buildPlayerOnCourt(
                      player: team1Goalkeeper, isTeam1: true, positionKey: 'GK', 
                      teamColor: const Color.fromARGB(255, 192, 98, 172),
                      quadraWidth: quadraWidth, quadraHeight: quadraHeight, alignment: team1GKPos,
                    ));
                  }
                  if (team1Fixo != null) {
                    playersOnCourt.add(_buildPlayerOnCourt(
                      player: team1Fixo, isTeam1: true, positionKey: 'Fixo', teamColor: team1Color,
                      quadraWidth: quadraWidth, quadraHeight: quadraHeight, alignment: team1FixoPos,
                    ));
                  }
                  if (team1Ala1 != null) {
                    playersOnCourt.add(_buildPlayerOnCourt(
                      player: team1Ala1, isTeam1: true, positionKey: 'Ala1', teamColor: team1Color,
                      quadraWidth: quadraWidth, quadraHeight: quadraHeight, alignment: team1Ala1Pos,
                    ));
                  }
                  if (team1Ala2 != null) {
                    playersOnCourt.add(_buildPlayerOnCourt(
                      player: team1Ala2, isTeam1: true, positionKey: 'Ala2', teamColor: team1Color,
                      quadraWidth: quadraWidth, quadraHeight: quadraHeight, alignment: team1Ala2Pos,
                    ));
                  }
                  if (team1Pivo != null) {
                    playersOnCourt.add(_buildPlayerOnCourt(
                      player: team1Pivo, isTeam1: true, positionKey: 'Pivo', teamColor: team1Color,
                      quadraWidth: quadraWidth, quadraHeight: quadraHeight, alignment: team1PivoPos,
                    ));
                  }
                  
                  if (team2Goalkeeper != null) {
                    playersOnCourt.add(_buildPlayerOnCourt(
                      player: team2Goalkeeper, isTeam1: false, positionKey: 'GK', 
                      teamColor: const Color.fromARGB(255, 192, 98, 172),
                      quadraWidth: quadraWidth, quadraHeight: quadraHeight, alignment: team2GKPos,
                    ));
                  }
                  if (team2Fixo != null) {
                    playersOnCourt.add(_buildPlayerOnCourt(
                      player: team2Fixo, isTeam1: false, positionKey: 'Fixo', teamColor: team2Color,
                      quadraWidth: quadraWidth, quadraHeight: quadraHeight, alignment: team2FixoPos,
                    ));
                  }
                  if (team2Ala1 != null) {
                    playersOnCourt.add(_buildPlayerOnCourt(
                      player: team2Ala1, isTeam1: false, positionKey: 'Ala1', teamColor: team2Color,
                      quadraWidth: quadraWidth, quadraHeight: quadraHeight, alignment: team2Ala1Pos,
                    ));
                  }
                  if (team2Ala2 != null) {
                    playersOnCourt.add(_buildPlayerOnCourt(
                      player: team2Ala2, isTeam1: false, positionKey: 'Ala2', teamColor: team2Color,
                      quadraWidth: quadraWidth, quadraHeight: quadraHeight, alignment: team2Ala2Pos,
                    ));
                  }
                  if (team2Pivo != null) {
                    playersOnCourt.add(_buildPlayerOnCourt(
                      player: team2Pivo, isTeam1: false, positionKey: 'Pivo', teamColor: team2Color,
                      quadraWidth: quadraWidth, quadraHeight: quadraHeight, alignment: team2PivoPos,
                    ));
                  }

                  return Stack(
                    children: [
                      _buildCourtBackground(quadraWidth, quadraHeight),
                      ...playersOnCourt,
                    ],
                  );
                },
              ),
            ),
          ),
          const Divider(),

          _buildReservesSection(
            team1Name,
            team1ShieldUrl,
            team1Reserves,
            team1Color,
            team2Name,
            team2ShieldUrl,
            team2Reserves,
            team2Color,
          ),
        ],
      ),
    );
  }

  Widget _buildReservesSection(
    String team1Name, String team1ShieldUrl, List<Map<String, dynamic>> team1Reserves, Color? team1Color,
    String team2Name, String team2ShieldUrl, List<Map<String, dynamic>> team2Reserves, Color? team2Color,
  ) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Banco de Reservas',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 10),
          _buildTeamReservesList(team1Name, team1ShieldUrl, team1Reserves, team1Color),
          const SizedBox(height: 10),
          _buildTeamReservesList(team2Name, team2ShieldUrl, team2Reserves, team2Color),
        ],
      ),
    );
  }

  Widget _buildTeamReservesList(
    String teamName,
    String teamShieldUrl,
    List<Map<String, dynamic>> reserves,
    Color? teamColor,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (teamShieldUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: teamShieldUrl,
                width: 30, height: 30, fit: BoxFit.contain,
                placeholder: (context, url) => const CircularProgressIndicator(strokeWidth: 2),
                errorWidget: (context, url, error) => const Icon(Icons.shield),
              ),
            const SizedBox(width: 8),
            Text(
              '$teamName (Reservas)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (reserves.isEmpty)
          const Text('Nenhum reserva disponível.')
        else
          Wrap( 
            spacing: 8.0, 
            runSpacing: 8.0,
            children: reserves.map((player) {
              // --- INÍCIO DA ALTERAÇÃO ---
              return InkWell( // <-- Envolvido em InkWell
                onTap: () {
                  // Ação de ver perfil (para todos, admin ou não)
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => PlayerProfileScreen(playerId: player['id']),
                    ),
                  );
                },
                child: PlayerDisplayCard(
                  playerName: player['name'],
                  jerseyNumber: player['jersey_number'] ?? 0,
                  yellowCards: player['yellow_cards'] ?? 0,
                  redCards: player['red_cards'] ?? 0,
                  isSuspended: player['is_suspended'] ?? false,
                  compactMode: false,
                  teamColor: teamColor,
                ),
              );
              // --- FIM DA ALTERAÇÃO ---
            }).toList(),
          ),
      ],
    );
  }

  // --- FUNÇÃO QUE FALTAVA (E CORRIGIDA) ---
  Widget _buildDetailsView(
      BuildContext context,
      List<Map<String, dynamic>> team1Players,
      List<Map<String, dynamic>> team2Players) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTeamSection(
            context,
            widget.team1Name,
            widget.team1ShieldUrl,
            team1Players,
          ),
          const SizedBox(height: 20),
          _buildTeamSection(
            context,
            widget.team2Name,
            widget.team2ShieldUrl,
            team2Players,
          ),
        ],
      ),
    );
  }
  // --- FIM DA FUNÇÃO ---

  // --- _buildTeamSection (CORRIGIDA PARA REMOVER O FAKEDOC) ---
  Widget _buildTeamSection(
      BuildContext context,
      String teamName,
      String teamShieldUrl,
      List<Map<String, dynamic>> players) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (teamShieldUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: teamShieldUrl,
                width: 40, height: 40, fit: BoxFit.contain,
                placeholder: (context, url) => const CircularProgressIndicator(strokeWidth: 2),
                errorWidget: (context, url, error) => const Icon(Icons.shield),
              ),
            const SizedBox(width: 10),
            Text(
              teamName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        ),
        const SizedBox(height: 10),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: players.length,
          itemBuilder: (context, index) {
            final player = players[index]; // player é um Map<String, dynamic>
            final String playerId = player['id'] ?? '';
            final int jerseyNumber = player['jersey_number'] ?? 0;
            final String playerName = player['name'] ?? 'Nome Indisponível';
            
            final int yellowCards = player['yellow_cards'] ?? 0;
            final int redCards = player['red_cards'] ?? 0;
            final bool isSuspended = player['is_suspended'] ?? false;
            
            final bool isGoalkeeper = player['is_goalkeeper'] ?? false;
            final String position = player['position'] ?? 'Não Definida';

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).primaryColor,
                  child: Text(
                    '$jerseyNumber',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(
                  playerName,
                  style: TextStyle(
                    decoration: isSuspended ? TextDecoration.lineThrough : TextDecoration.none,
                    color: isSuspended ? Colors.grey[600] : null,
                  ),
                ),
                subtitle: Text('${isGoalkeeper ? 'Goleiro' : position}'),
                
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSuspended || redCards > 0)
                      Icon(
                        Icons.style, 
                        color: Colors.red[700], 
                        semanticLabel: 'Suspenso', 
                        size: 20
                      )
                    else if (yellowCards >= AdminService.pendingYellowCards)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                          yellowCards,
                          (index) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1.0),
                            child: Icon(
                              Icons.style, 
                              color: Colors.yellow[700], 
                              semanticLabel: 'Pendurado', 
                              size: 20
                            ),
                          ),
                        ),
                      ),
                    
                    if (AdminService.isAdmin && isSuspended)
                      GestureDetector( // Envolve com GestureDetector
                        onTap: () {
                          // Passa o Map 'player' e o 'playerId'
                          _showClearSuspensionDialog(context, player, playerId);
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Icon(
                            Icons.admin_panel_settings_outlined, 
                            color: Theme.of(context).primaryColor, 
                            size: 20,
                            semanticLabel: 'Gerenciar Suspensão',
                          ),
                        ),
                      ),
                  ],
                ),

                onTap: () {
                  // Ação padrão: navegar para o perfil
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => PlayerProfileScreen(playerId: player['id']),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
  // --- FIM DA CORREÇÃO ---
}