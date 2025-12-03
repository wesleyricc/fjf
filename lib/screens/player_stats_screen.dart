// lib/screens/player_stats_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'team_detail_screen.dart';
import '../services/admin_service.dart';
import 'player_profile_screen.dart';

class PlayerStatsScreen extends StatefulWidget {
  const PlayerStatsScreen({super.key});

  @override
  State<PlayerStatsScreen> createState() => _PlayerStatsScreenState();
}

class _PlayerStatsScreenState extends State<PlayerStatsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- HELPER: Navegação ---
  Future<void> _navigateToTeam(BuildContext context, String? teamId) async {
    if (teamId == null || teamId.isEmpty) return;
    try {
      final teamDoc = await _firestore.collection('teams').doc(teamId).get();
      if (teamDoc.exists && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (ctx) => TeamDetailScreen(teamDoc: teamDoc)),
        );
      }
    } catch (e) {
      debugPrint("Erro team nav: $e");
    }
  }

  // --- HELPER: Navegação para Perfil ---
  void _navigateToProfile(BuildContext context, String playerId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (ctx) => PlayerProfileScreen(playerId: playerId)),
    );
  }

  // --- HELPER: Avatar Otimizado ---
  Widget _buildOptimizedAvatar(String? photoUrl, bool isStaff) {
    final double radius = 20.0;
    final double diameter = radius * 2;

    if (photoUrl == null || photoUrl.isEmpty || !photoUrl.startsWith('http')) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.grey[300],
        child: Icon(
          isStaff ? Icons.assignment_ind_outlined : Icons.person,
          color: Colors.grey[700],
          size: 24,
        ),
      );
    }

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: photoUrl,
        memCacheWidth: 150, // Otimização de RAM
        width: diameter,
        height: diameter,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          width: diameter,
          height: diameter,
          color: Colors.grey[200],
          child: const Center(
             child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2))
          ),
        ),
        errorWidget: (context, url, error) {
          // debugPrint("Erro Avatar: $error na URL: $url");
          return Container(
            width: diameter,
            height: diameter,
            color: Colors.grey[300],
            child: Icon(Icons.person, size: 24, color: Colors.grey[600]),
          );
        },
      ),
    );
  }

  // --- HELPER: Diálogo de Ajuda ---
  Future<void> _showPlayerStatsHelp(BuildContext context) async {
     return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
    return AlertDialog(
          title: const Text('Ajuda: Estatísticas de Jogadores'),
          content: SingleChildScrollView(
            child: RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 15), 
                children: <TextSpan>[
                  const TextSpan(text: 'Esta tela mostra os rankings e o status disciplinar dos jogadores.\n\n'),
                  
                  const TextSpan(text: 'Artilheiros:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Ranking de jogadores com mais gols.\n\n'),
                  
                  const TextSpan(text: 'Assistências:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Ranking de jogadores com mais assistências.\n\n'),
                  
                  const TextSpan(text: 'Goleiro MV:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Goleiro Menos Vazado. Os gols sofridos sempre totalizam para o goleiro principal do time.\n\n'),
                  
                  const TextSpan(text: 'Craque do Jogo:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Ranking de jogadores que mais ganharam o prêmio.\n\n'),
                  
                  const TextSpan(text: 'Pendurados:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: 'Apresenta os jogadores com ${AdminService.pendingYellowCards} cartões amarelos.\n\n'), 
                  
                  const TextSpan(text: 'Suspensos:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: 'Apresenta os jogadores que estão suspensos por CV ou ${AdminService.suspensionYellowCards} CAs.\n\n'),
                  
                  const TextSpan(text: 'Total Amarelos:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Soma-se o total de cartões amarelos registrados em súmula para o atleta. Exclusivo para avaliação disciplinar do atleta.\n\n'),
                  
                  const TextSpan(text: 'Total Vermelhos:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Soma-se o total de cartões vermelhos registrados em súmula para o atleta. Exclusivo para avaliação disciplinar do atleta.\n\n'),

                  const TextSpan(text: 'Total Cartões:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Soma-se o total de cartões registrados em súmula para o atleta, CA e CV compõem o total. Exclusivo para avaliação disciplinar do atleta.\n\n'),

                  const TextSpan(text: 'Regra Geral de Suspensão:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: '- Um atleta é suspenso quando toma 1 CV ou ${AdminService.suspensionYellowCards} CA em jogos diferentes (2 CA no mesmo joga contabiliza-se apenas um para regra de Suspensão);\n'),
                  const TextSpan(text: '- Se um atleta vem para o jogo com 1 CA acumulado e levar 2CA e 1CV no jogo, ele irá cumprimir suspensão pelo CV, e seus CA seguem acumulados;\n'),
                  TextSpan(text: '- Se um atleta vem para o jogo pendurado (${AdminService.pendingYellowCards} CA) e levar 2CA e 1CV no jogo, ele irá cumprimir suspensão dobrada, pelo CV e pelos CA acumulados.\n\n'),
                  
                  const TextSpan(text: 'Regra Geral de Zeramento de Cartões:\n', style: TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: 'Um atleta tem seus CA zerados apenas quando cumpre suspensão por levar 3CA.\n'),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Fechar'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
        },
    );
  }

  // --- LÓGICA: Diálogo para limpar suspensão ---
  Future<void> _showClearSuspensionDialog(BuildContext context, DocumentSnapshot player) async {
    final playerName = player['name'] ?? 'Jogador desconhecido';
    final data = player.data() as Map<String, dynamic>? ?? {};
    final int currentYellows = data['yellow_cards'] ?? 0;
    final int currentReds = data['red_cards'] ?? 0;

    bool suspendedByRed = (currentReds > 0 && AdminService.suspensionOnRed);
    bool suspendedByYellow = (currentYellows >= AdminService.suspensionYellowCards);
    
    if (!suspendedByRed && data['is_suspended'] == true) {
       suspendedByYellow = true;
    }
    
    String reason = "Motivo desconhecido.";
    if (suspendedByRed && suspendedByYellow) {
       reason = "Motivo: Acúmulo de CA e Cartão Vermelho (Suspensão Múltipla).";
    } else if (suspendedByRed) {
       reason = "Motivo: Cartão Vermelho.";
    } else if (suspendedByYellow) {
       reason = "Motivo: Acúmulo de Cartões Amarelos.";
    }

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Limpar Suspensão'),
          content: Text(
            'Tem certeza que deseja liberar $playerName?\n\n$reason\n\n'
            'Isso definirá "Suspenso=Falso" e zerará os cartões da suspensão atual.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: const Text('Confirmar Liberação'),
              onPressed: () async {
                try {
                  Map<String, dynamic> updateData = {
                    'is_suspended': false,
                    'red_cards': 0,
                    if (suspendedByYellow) 'yellow_cards': 0,
                  };

                  await _firestore.collection('players').doc(player.id).update(updateData);
                      
                  final logQuery = await _firestore
                      .collection('suspension_log')
                      .where('playerId', isEqualTo: player.id)
                      .orderBy('timestamp', descending: true)
                      .limit(1)
                      .get();
                  
                  if (logQuery.docs.isNotEmpty) {
                    await logQuery.docs.first.reference.update({
                      'return_date': FieldValue.serverTimestamp(),
                    });
                  }

                  if(dialogContext.mounted) Navigator.of(dialogContext).pop();
                  if (context.mounted) { 
                     ScaffoldMessenger.of(context).showSnackBar(
                       SnackBar(content: Text('$playerName liberado da suspensão.')),
                     );
                  }
                } catch (e) {
                  debugPrint("Erro ao liberar: $e");
                   if (context.mounted) {
                     ScaffoldMessenger.of(context).showSnackBar(
                       SnackBar(content: Text('Erro: $e')),
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 9,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Estatísticas dos Jogadores'),
          actions: [
            IconButton(
              icon: const Icon(Icons.help_outline),
              onPressed: () => _showPlayerStatsHelp(context),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Artilheiros'),
              Tab(text: 'Assistências'),
              Tab(text: 'Goleiro MV'),
              Tab(text: 'Craque do Jogo'),
              Tab(text: 'Pendurados'),
              Tab(text: 'Suspensos'),
              Tab(text: 'Total Amarelos'),
              Tab(text: 'Total Vermelhos'),
              Tab(text: 'Total Cartões'),
            ],
          ),
        ),
        drawer: const AppDrawer(),
        body: TabBarView(
          children: [
            // 1. Artilheiros
            ServerSidePaginatedList(
              firestore: _firestore,
              baseQuery: _firestore.collection('players').where('isActive', isEqualTo: true).where('is_staff', isEqualTo: false).where('goals', isGreaterThan: 0).orderBy('goals', descending: true).orderBy('name'),
              statKey: 'goals', statLabel: 'Gols', emptyMsg: 'Nenhum artilheiro.',
              onAvatarBuild: _buildOptimizedAvatar, onTeamTap: _navigateToTeam,
            ),
            // 2. Assistências
            ServerSidePaginatedList(
              firestore: _firestore,
              baseQuery: _firestore.collection('players').where('isActive', isEqualTo: true).where('is_staff', isEqualTo: false).where('assists', isGreaterThan: 0).orderBy('assists', descending: true).orderBy('name'),
              statKey: 'assists', statLabel: 'Ass', emptyMsg: 'Nenhuma assistência.',
              onAvatarBuild: _buildOptimizedAvatar, onTeamTap: _navigateToTeam,
            ),
            // 3. Goleiro MV
            ServerSidePaginatedList(
              firestore: _firestore,
              baseQuery: _firestore.collection('players').where('isActive', isEqualTo: true).where('is_staff', isEqualTo: false).where('is_goalkeeper', isEqualTo: true).orderBy('goals_conceded', descending: false).orderBy('name'),
              statKey: 'goals_conceded', statLabel: 'GS', emptyMsg: 'Nenhum goleiro.',
              onAvatarBuild: _buildOptimizedAvatar, onTeamTap: _navigateToTeam,
            ),
            // 4. Craque do Jogo
            ServerSidePaginatedList(
              firestore: _firestore,
              baseQuery: _firestore.collection('players').where('isActive', isEqualTo: true).where('is_staff', isEqualTo: false).where('man_of_the_match_awards', isGreaterThan: 0).orderBy('man_of_the_match_awards', descending: true).orderBy('name'),
              statKey: 'man_of_the_match_awards', statLabel: 'x', emptyMsg: 'Nenhum prêmio.',
              onAvatarBuild: _buildOptimizedAvatar, onTeamTap: _navigateToTeam,
            ),
            // 5. Pendurados (Status)
            ServerSidePaginatedList(
              firestore: _firestore,
              baseQuery: _firestore.collection('players').where('isActive', isEqualTo: true).where('yellow_cards', isEqualTo: AdminService.pendingYellowCards).orderBy('name'),
              statKey: 'yellow_cards', statLabel: 'STATUS_PENDURADO', emptyMsg: 'Ninguém pendurado.',
              onAvatarBuild: _buildOptimizedAvatar, onTeamTap: _navigateToTeam,
            ),
            // 6. Suspensos (Status)
            ServerSidePaginatedList(
              firestore: _firestore,
              baseQuery: _firestore.collection('players').where('isActive', isEqualTo: true).where('is_suspended', isEqualTo: true).orderBy('name'),
              statKey: 'is_suspended', statLabel: 'STATUS_SUSPENSO', emptyMsg: 'Ninguém suspenso.',
              onAvatarBuild: _buildOptimizedAvatar, onTeamTap: _navigateToTeam,
              onItemTap: (doc) {
                if (AdminService.isAdmin) _showClearSuspensionDialog(context, doc);
                else _navigateToProfile(context, doc.id);
              },
            ),
            // 7. Total Amarelos
            ServerSidePaginatedList(
              firestore: _firestore,
              baseQuery: _firestore.collection('players').where('isActive', isEqualTo: true).where('total_yellow_cards', isGreaterThan: 0).orderBy('total_yellow_cards', descending: true).orderBy('name'),
              statKey: 'total_yellow_cards', statLabel: 'CA', emptyMsg: 'Sem cartões amarelos.',
              onAvatarBuild: _buildOptimizedAvatar, onTeamTap: _navigateToTeam,
            ),
            // 8. Total Vermelhos
            ServerSidePaginatedList(
              firestore: _firestore,
              baseQuery: _firestore.collection('players').where('isActive', isEqualTo: true).where('total_red_cards', isGreaterThan: 0).orderBy('total_red_cards', descending: true).orderBy('name'),
              statKey: 'total_red_cards', statLabel: 'CV', emptyMsg: 'Sem cartões vermelhos.',
              onAvatarBuild: _buildOptimizedAvatar, onTeamTap: _navigateToTeam,
            ),
            // 9. Total Cartões (CLIENT SIDE)
            ClientSidePaginatedList(
              firestore: _firestore, emptyMsg: 'Sem cartões.',
              onAvatarBuild: _buildOptimizedAvatar, onTeamTap: _navigateToTeam,
            ),
          ],
        ),
        bottomNavigationBar: const SponsorBannerRotator(),
      ),
    );
  }
}

// =============================================================================
// WIDGET 1: PAGINAÇÃO SERVER-SIDE (10 em 10)
// =============================================================================
class ServerSidePaginatedList extends StatefulWidget {
  final FirebaseFirestore firestore;
  final Query baseQuery;
  final String statKey;
  final String statLabel;
  final String emptyMsg;
  final Widget Function(String?, bool) onAvatarBuild;
  final Function(BuildContext, String?) onTeamTap;
  final Function(DocumentSnapshot)? onItemTap; 

  const ServerSidePaginatedList({
    super.key,
    required this.firestore,
    required this.baseQuery,
    required this.statKey,
    required this.statLabel,
    required this.emptyMsg,
    required this.onAvatarBuild,
    required this.onTeamTap,
    this.onItemTap,
  });

  @override
  State<ServerSidePaginatedList> createState() => _ServerSidePaginatedListState();
}

class _ServerSidePaginatedListState extends State<ServerSidePaginatedList> with AutomaticKeepAliveClientMixin {
  final int _pageSize = 10; 
  List<DocumentSnapshot> _docs = [];
  bool _isLoading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadNextPage();
  }

  Future<void> _loadNextPage() async {
    if (_isLoading || !_hasMore) return;

    setState(() => _isLoading = true);

    try {
      Query query = widget.baseQuery.limit(_pageSize);
      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

      final snapshot = await query.get();

      if (snapshot.docs.length < _pageSize) {
        _hasMore = false;
      }

      if (snapshot.docs.isNotEmpty) {
        _lastDocument = snapshot.docs.last;
        _docs.addAll(snapshot.docs);
      }
    } catch (e) {
      debugPrint("Erro paginação: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildTrailing(Map<String, dynamic> data) {
    if (widget.statLabel == 'STATUS_SUSPENSO') {
      int reds = data['red_cards'] ?? 0;
      int yellows = data['yellow_cards'] ?? 0;
      List<Widget> icons = [];
      bool hasRed = (reds > 0);
      bool isYellowSuspension = (yellows >= AdminService.suspensionYellowCards) || (reds == 0);

      if (isYellowSuspension) {
        icons.addAll(List.generate(3, (index) => Padding(
          padding: const EdgeInsets.only(right: 2.0),
          child: Icon(Icons.style, color: Colors.yellow[700], size: 18),
        )));
      }

      if (hasRed) {
        if (isYellowSuspension) icons.add(const SizedBox(width: 6)); 
        icons.add(Icon(Icons.style, color: Colors.red[700], size: 18));
      }

      return Row(mainAxisSize: MainAxisSize.min, children: icons);
    } 
    
    if (widget.statLabel == 'STATUS_PENDURADO') {
       int currentYellows = data['yellow_cards'] ?? 0;
       return Row(
         mainAxisSize: MainAxisSize.min,
         children: List.generate(currentYellows, (index) => Padding(
           padding: const EdgeInsets.only(right: 2.0),
           child: Icon(Icons.style, color: Colors.yellow[700], size: 18),
         )),
       );
    }

    final int value = data[widget.statKey] ?? 0;
    
    if (widget.statLabel == 'CA') {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$value', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(width: 4),
        Icon(Icons.style, color: Colors.yellow[700], size: 20),
      ]);
    } else if (widget.statLabel == 'CV') {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$value', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(width: 4),
        Icon(Icons.style, color: Colors.red[700], size: 20),
      ]);
    }

    return Text('$value ${widget.statLabel}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); 

    if (_docs.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_docs.isEmpty && !_isLoading) {
      return Center(child: Text(widget.emptyMsg));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: _docs.length + 1, 
      itemBuilder: (context, index) {
        if (index == _docs.length) {
          if (_hasMore) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 40.0),
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _loadNextPage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30.0),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      elevation: 3,
                    ),
                    child: const Text('Carregar Mais...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
            );
          } else {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: Text('Fim da lista.', style: TextStyle(color: Colors.grey))),
            );
          }
        }

        final doc = _docs[index];
        final data = doc.data() as Map<String, dynamic>;
        
        final String? photoUrl = (data.containsKey('photo_url') && data['photo_url'] != null) ? data['photo_url'].toString() : null;
        final bool isStaff = data['is_staff'] ?? false;
        final String name = data['name'] ?? 'Nome';
        final int? num = data['jersey_number'];
        final String displayName = isStaff ? '$name (Staff)' : (num != null ? '$num. $name' : name);

        // --- CORREÇÃO: Extração segura do escudo do time ---
        final String? shieldUrl = (data.containsKey('team_shield_url') && data['team_shield_url'] != null)
            ? data['team_shield_url'].toString()
            : null;
        // ---------------------------------------------------

        return ListTile(
          leading: widget.onAvatarBuild(photoUrl, isStaff),
          title: Text(displayName, style: TextStyle(fontStyle: isStaff ? FontStyle.italic : FontStyle.normal)),
          subtitle: InkWell(
            onTap: () => widget.onTeamTap(context, data['team_id']),
            child: Row(
              children: [
                // --- CORREÇÃO: Exibição do escudo do time ---
                if (shieldUrl != null && shieldUrl.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: SizedBox(
                      width: 18, height: 18, 
                      child: CachedNetworkImage(
                        imageUrl: shieldUrl, 
                        fit: BoxFit.contain,
                        placeholder: (c,u) => const SizedBox(),
                        errorWidget: (c,u,e) => const Icon(Icons.shield, size: 15),
                      )
                    ),
                  ),
                // ---------------------------------------------
                Flexible(child: Text(data['team_name'] ?? 'Time', overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          trailing: _buildTrailing(data),
          onTap: () {
             if (widget.onItemTap != null) {
               widget.onItemTap!(doc); 
             } else {
               Navigator.of(context).push(
                  MaterialPageRoute(builder: (ctx) => PlayerProfileScreen(playerId: doc.id)),
               );
             }
          },
        );
      },
    );
  }
}

// =============================================================================
// WIDGET 2: PAGINAÇÃO CLIENT-SIDE (Para Total de Cartões)
// =============================================================================
class ClientSidePaginatedList extends StatefulWidget {
  final FirebaseFirestore firestore;
  final String emptyMsg;
  final Widget Function(String?, bool) onAvatarBuild;
  final Function(BuildContext, String?) onTeamTap;

  const ClientSidePaginatedList({
    super.key,
    required this.firestore,
    required this.emptyMsg,
    required this.onAvatarBuild,
    required this.onTeamTap,
  });

  @override
  State<ClientSidePaginatedList> createState() => _ClientSidePaginatedListState();
}

class _ClientSidePaginatedListState extends State<ClientSidePaginatedList> with AutomaticKeepAliveClientMixin {
  final int _pageSize = 10; 
  List<Map<String, dynamic>> _allPlayersSorted = [];
  List<Map<String, dynamic>> _displayedPlayers = [];
  bool _isInitialLoading = true;
  bool _hasMore = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchAllAndSort();
  }

  Future<void> _fetchAllAndSort() async {
    setState(() => _isInitialLoading = true);
    try {
      final snapshot = await widget.firestore.collection('players')
          .where('isActive', isEqualTo: true)
          .get();

      List<Map<String, dynamic>> temp = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        int y = data['total_yellow_cards'] ?? 0;
        int r = data['total_red_cards'] ?? 0;
        int total = y + r;
        if (total > 0) {
          temp.add({
            'docId': doc.id,
            'data': data,
            'total': total,
            'y': y,
            'r': r,
          });
        }
      }

      temp.sort((a, b) => b['total'].compareTo(a['total']));

      _allPlayersSorted = temp;
      _loadMoreChunk();

    } catch (e) {
      debugPrint("Erro total cartões: $e");
    } finally {
      if (mounted) setState(() => _isInitialLoading = false);
    }
  }

  void _loadMoreChunk() {
    int currentLen = _displayedPlayers.length;
    int nextLen = currentLen + _pageSize;
    
    if (nextLen >= _allPlayersSorted.length) {
      nextLen = _allPlayersSorted.length;
      _hasMore = false;
    } else {
      _hasMore = true;
    }

    setState(() {
      _displayedPlayers = _allPlayersSorted.sublist(0, nextLen);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isInitialLoading) return const Center(child: CircularProgressIndicator());
    if (_displayedPlayers.isEmpty) return Center(child: Text(widget.emptyMsg));

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: _displayedPlayers.length + 1,
      itemBuilder: (context, index) {
        if (index == _displayedPlayers.length) {
          if (_hasMore) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 40.0),
              child: ElevatedButton(
                onPressed: _loadMoreChunk,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30.0),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  elevation: 3,
                ),
                child: const Text(
                  'Carregar Mais...',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            );
          } else {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: Text('Fim da lista.', style: TextStyle(color: Colors.grey))),
            );
          }
        }

        final item = _displayedPlayers[index];
        final data = item['data'] as Map<String, dynamic>;
        
        final String? photoUrl = (data.containsKey('photo_url') && data['photo_url'] != null) ? data['photo_url'].toString() : null;
        final bool isStaff = data['is_staff'] ?? false;
        final String name = data['name'] ?? 'Nome';
        final int? num = data['jersey_number'];
        final String displayName = isStaff ? '$name (Staff)' : (num != null ? '$num. $name' : name);
        
        // --- CORREÇÃO: Extração do escudo na ClientSide ---
        final String? shieldUrl = (data.containsKey('team_shield_url') && data['team_shield_url'] != null)
            ? data['team_shield_url'].toString()
            : null;
        // -------------------------------------------------

        return ListTile(
          leading: widget.onAvatarBuild(photoUrl, isStaff),
          title: Text(displayName),
          subtitle: InkWell(
            onTap: () => widget.onTeamTap(context, data['team_id']),
            child: Row(
              children: [
                // --- CORREÇÃO: Exibição do escudo do time ---
                if (shieldUrl != null && shieldUrl.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: SizedBox(
                      width: 18, height: 18, 
                      child: CachedNetworkImage(
                        imageUrl: shieldUrl, 
                        fit: BoxFit.contain,
                        placeholder: (c,u) => const SizedBox(),
                        errorWidget: (c,u,e) => const Icon(Icons.shield, size: 15),
                      )
                    ),
                  ),
                // ---------------------------------------------
                Flexible(child: Text(data['team_name'] ?? '', style: const TextStyle(fontSize: 12))),
              ],
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${item['total']} Cartões', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${item['y']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  Icon(Icons.style, color: Colors.yellow[700], size: 12),
                  const Text(' / '),
                  Text('${item['r']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  Icon(Icons.style, color: Colors.red[700], size: 12),
                ],
              )
            ],
          ),
          onTap: () {
             Navigator.of(context).push(
                MaterialPageRoute(builder: (ctx) => PlayerProfileScreen(playerId: item['docId'])),
             );
          },
        );
      },
    );
  }
}