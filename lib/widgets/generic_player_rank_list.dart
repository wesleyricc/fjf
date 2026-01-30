// lib/widgets/generic_player_rank_list.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../services/admin_service.dart';
import '../services/auth_service.dart';
import '../services/championship_service.dart';
import '../screens/player_profile_screen.dart';
import '../utils/custom_cache_manager.dart';
import '../widgets/rank_highlight_card.dart';
import '../widgets/rank_indicator.dart'; // Certifique-se de ter este widget ou use o código abaixo

class GenericPlayerRankList extends StatefulWidget {
  final Query baseQuery;
  final String emptyMessage;
  final String? statField;
  final String? statLabel;
  final bool isStatusList;
  final bool isSuspendedTab;

  const GenericPlayerRankList({
    super.key,
    required this.baseQuery,
    required this.emptyMessage,
    this.statField,
    this.statLabel,
    this.isStatusList = false,
    this.isSuspendedTab = false,
  });

  @override
  State<GenericPlayerRankList> createState() => _GenericPlayerRankListState();
}

class _GenericPlayerRankListState extends State<GenericPlayerRankList> with AutomaticKeepAliveClientMixin {
  final int _pageSize = 20;
  final List<DocumentSnapshot> _players = [];
  bool _isLoading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDocument;
  bool _hasError = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

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
          content: Text('Tem certeza que deseja liberar $playerName?\n\n$reason\n\nIsso definirá "Suspenso=Falso" e zerará os cartões da suspensão atual.'),
          actions: <Widget>[
            TextButton(child: const Text('Cancelar'), onPressed: () => Navigator.of(dialogContext).pop()),
            TextButton(
              child: const Text('Confirmar Liberação'),
              onPressed: () async {
                try {
                  final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
                  final playerRef = FirebaseFirestore.instance.collection('championships').doc(seasonId).collection('player_stats').doc(player.id);

                  Map<String, dynamic> updateData = {
                    'is_suspended': false,
                    'red_cards': 0, 
                    if (suspendedByYellow) 'yellow_cards': 0,
                  };

                  await playerRef.update(updateData);
                  
                  final logQuery = await FirebaseFirestore.instance.collection('championships').doc(seasonId).collection('disciplinary_log').where('playerId', isEqualTo: player.id).orderBy('timestamp', descending: true).limit(1).get();
                  if (logQuery.docs.isNotEmpty) {
                    await logQuery.docs.first.reference.update({'return_date': FieldValue.serverTimestamp()});
                  }

                  if(dialogContext.mounted) Navigator.of(dialogContext).pop();
                  if (context.mounted) { 
                     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$playerName liberado da suspensão.')));
                     _loadData();
                  }
                } catch (e) {
                   if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadData() async {
    if (_isLoading || !_hasMore) return;
    if (mounted) setState(() { _isLoading = true; _hasError = false; });

    try {
      Query query = widget.baseQuery.limit(_pageSize);
      if (_lastDocument != null) query = query.startAfterDocument(_lastDocument!);

      final snapshot = await query.get();

      if (snapshot.docs.isNotEmpty) {
        if (mounted) {
          setState(() {
            _lastDocument = snapshot.docs.last;
            _players.addAll(snapshot.docs);
            if (snapshot.docs.length < _pageSize) _hasMore = false;
          });
        }
      } else {
        if (mounted) setState(() => _hasMore = false);
      }
    } catch (e) {
      if (mounted) setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_players.isEmpty && _isLoading) return const Center(child: CircularProgressIndicator());
    if (_players.isEmpty && !_hasError) return Center(child: Text(widget.emptyMessage));
    if (_hasError && _players.isEmpty) return Center(child: TextButton(onPressed: _loadData, child: const Text("Erro. Tentar novamente")));

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 20, top: 8),
      itemCount: _players.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _players.length) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(child: _isLoading ? const CircularProgressIndicator() : ElevatedButton(onPressed: _loadData, child: const Text("Carregar mais"))),
          );
        }

        final doc = _players[index];
        final rank = index + 1;

        // --- DESTAQUE TOP 3 ---
        // Exibe o Card Grande com Foto
        if (index < 3 && !widget.isStatusList) {
          return _buildTopRankItem(doc, rank);
        }

        // --- LISTA PADRÃO (4º em diante) ---
        // Sem foto, apenas Nome, Time e Estatística
        return Column(
          children: [
            _buildCompactPlayerItem(doc, rank),
            const Divider(height: 1, indent: 60), // Indent ajustado
          ],
        );
      },
    );
  }

  Widget _buildTopRankItem(DocumentSnapshot doc, int rank) {
    final data = doc.data() as Map<String, dynamic>;
    final val = data[widget.statField] ?? 0;
    
    IconData icon = Icons.star;
    if (widget.statLabel == 'Gols') icon = Icons.sports_soccer;
    else if (widget.statLabel == 'Ass') icon = Icons.assistant;
    else if (widget.statLabel == 'GS') icon = Icons.pan_tool_outlined;
    else if (widget.statLabel == 'CA') icon = Icons.style;
    else if (widget.statLabel == 'CV') icon = Icons.style;

    Color? customColor;
    if (widget.statLabel == 'CA') customColor = Colors.amber[800];
    if (widget.statLabel == 'CV') customColor = Colors.red;

    return RankHighlightCard(
      rank: rank,
      title: data['name'] ?? 'Desconhecido',
      subtitle: data['team_name'] ?? '',
      imageUrl: data['photo_url'] ?? '',
      statValue: '$val',
      statLabel: widget.statLabel ?? '',
      statIcon: icon,
      customColor: customColor,
      isPlayer: true, // Garante o recorte circular na foto
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerProfileScreen(playerId: doc.id))),
    );
  }

  Widget _buildCompactPlayerItem(DocumentSnapshot doc, int rank) {
    final data = doc.data() as Map<String, dynamic>;
    final bool isStaff = data['is_staff'] ?? false;
    final String name = data['name'] ?? 'Desconhecido';
    final String teamName = data['team_name'] ?? '';
    final String shieldUrl = data['team_shield_url'] ?? '';
    final isAdmin = Provider.of<AuthService>(context).isAuthenticated;

    // Definição do valor (Trailing)
    Widget trailing;
    if (widget.isStatusList) {
      // Lógica de ícones para cartões (mantida)
      int y = (data['yellow_cards'] as num?)?.toInt() ?? 0;
      int r = (data['red_cards'] as num?)?.toInt() ?? 0;
      List<Widget> icons = [];
      
      if (widget.isSuspendedTab) {
        if (r > 0) icons.add(const Icon(Icons.style, color: Colors.red, size: 18));
        if (y >= (AdminService.suspensionYellowCards > 0 ? AdminService.suspensionYellowCards : 3)) {
           if (icons.isNotEmpty) icons.add(const SizedBox(width: 4));
           icons.add(Icon(Icons.style, color: Colors.amber[700], size: 18));
        }
      } else {
        for(int i=0; i<y; i++) icons.add(Icon(Icons.style, color: Colors.amber[700], size: 18));
      }
      trailing = Row(mainAxisSize: MainAxisSize.min, children: icons);
    } else {
      final val = data[widget.statField] ?? 0;
      trailing = Text(
        "$val ${widget.statLabel ?? ''}", 
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)
      );
    }

    return ListTile(
      visualDensity: VisualDensity.compact, // Lista mais densa
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      
      // 1. LEADING: Apenas o Rank (Sem foto do jogador)
      leading: RankIndicator(rank: rank, size: 28, fontSize: 12),

      // 2. TÍTULO: Nome do Jogador
      title: Text(
        name,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          fontStyle: isStaff ? FontStyle.italic : FontStyle.normal
        ),
      ),

      // 3. SUBTÍTULO: Escudo + Nome do Time
      subtitle: Row(
        children: [
          if (shieldUrl.isNotEmpty) ...[
            CachedNetworkImage(
              imageUrl: shieldUrl, 
              width: 14, 
              height: 14, 
              fit: BoxFit.contain,
              memCacheWidth: 42,
              errorWidget: (_,__,___)=>const Icon(Icons.shield, size: 14, color: Colors.grey),
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              teamName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
        ],
      ),

      // 4. TRAILING: Estatística
      trailing: trailing,
      onTap: () {
        if (widget.isSuspendedTab && isAdmin) {
          _showClearSuspensionDialog(context, doc);
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerProfileScreen(playerId: doc.id)));
        }
      },
    );
  }
}