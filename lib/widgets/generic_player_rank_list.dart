import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../services/admin_service.dart';
import '../services/auth_service.dart';
import '../services/championship_service.dart';
import '../services/firestore_service.dart';
import '../screens/player_profile_screen.dart';
import '../screens/team_detail_screen.dart';
import '../utils/custom_cache_manager.dart';

class GenericPlayerRankList extends StatefulWidget {
  final Query baseQuery;
  final String emptyMessage;
  final String? statField;
  final String? statLabel;
  final bool isStatusList; // Se true, muda o layout para Pendurados/Suspensos
  final bool isSuspendedTab; // Layout específico para suspensos

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
  bool get wantKeepAlive => true; // Mantém a lista na memória ao trocar de aba

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (_isLoading || !_hasMore) return;

    if (mounted) setState(() { _isLoading = true; _hasError = false; });

    try {
      Query query = widget.baseQuery.limit(_pageSize);
      if (_lastDocument != null) {
        query = query.startAfterDocument(_lastDocument!);
      }

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
      debugPrint("Erro carregando lista: $e");
      if (mounted) setState(() => _hasError = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- DIÁLOGO DE LIMPAR SUSPENSÃO ---
  Future<void> _showClearSuspensionDialog(DocumentSnapshot player) async {
    final playerName = player['name'] ?? 'Jogador';
    final data = player.data() as Map<String, dynamic>? ?? {};
    final int currentYellows = data['yellow_cards'] ?? 0;
    final int currentReds = data['red_cards'] ?? 0;

    bool suspendedByRed = (currentReds > 0 && AdminService.suspensionOnRed);
    bool suspendedByYellow = (currentYellows >= AdminService.suspensionYellowCards);
    
    String reason = "Motivo desconhecido.";
    if (suspendedByRed && suspendedByYellow) reason = "Acúmulo de CA e Cartão Vermelho.";
    else if (suspendedByRed) reason = "Cartão Vermelho.";
    else if (suspendedByYellow) reason = "Acúmulo de Cartões Amarelos.";

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpar Suspensão'),
        content: Text('Liberar $playerName?\n\n$reason\n\nIsso removerá a flag de suspenso e resetará contadores conforme a regra.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        // 1. Atualiza Jogador
        Map<String, dynamic> updateData = {'is_suspended': false, 'red_cards': 0};
        if (currentYellows >= AdminService.suspensionYellowCards) updateData['yellow_cards'] = 0;
        await player.reference.update(updateData);

        // 2. Atualiza Log
        final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
        Query logQuery;
        if (seasonId == FirestoreService.LEGACY_ID) {
          logQuery = FirebaseFirestore.instance.collection('suspension_log');
        } else {
          logQuery = FirebaseFirestore.instance.collection('championships').doc(seasonId).collection('disciplinary_log');
        }
        
        final logsSnapshot = await logQuery
            .where('playerId', isEqualTo: player.id)
            .where('status', isEqualTo: 'pending')
            .orderBy('timestamp', descending: true)
            .limit(1)
            .get();

        if (logsSnapshot.docs.isNotEmpty) {
          await logsSnapshot.docs.first.reference.update({'status': 'cleared', 'cleared_timestamp': FieldValue.serverTimestamp()});
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$playerName liberado.')));
          // Remove da lista visualmente
          setState(() {
             _players.removeWhere((doc) => doc.id == player.id);
          });
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_players.isEmpty && _isLoading) return const Center(child: CircularProgressIndicator());
    if (_players.isEmpty && !_hasError) return Center(child: Text(widget.emptyMessage));
    if (_hasError && _players.isEmpty) return Center(child: TextButton(onPressed: _loadData, child: const Text("Erro. Tentar novamente")));

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 20, top: 8),
      itemCount: _players.length + (_hasMore ? 1 : 0),
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 70),
      itemBuilder: (context, index) {
        if (index == _players.length) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Center(child: _isLoading ? const CircularProgressIndicator() : ElevatedButton(onPressed: _loadData, child: const Text("Carregar mais"))),
          );
        }
        return _buildPlayerItem(_players[index]);
      },
    );
  }

  Widget _buildPlayerItem(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final bool isStaff = data['is_staff'] ?? false;
    final String name = data['name'] ?? 'Desconhecido';
    final String displayName = isStaff ? '$name (Comissão)' : "${data['jersey_number'] ?? '-'} $name";
    final String photoUrl = data['photo_url'] ?? '';
    final String teamName = data['team_name'] ?? '';
    final String shieldUrl = data['team_shield_url'] ?? '';

    Widget trailing;
    if (widget.isStatusList) {
      if (widget.isSuspendedTab) {
        int r = data['red_cards'] ?? 0;
        int y = data['yellow_cards'] ?? 0;
        List<Widget> icons = [];
        if (r > 0) icons.add(const Icon(Icons.style, color: Colors.red, size: 20));
        if (y >= AdminService.suspensionYellowCards) {
          if (icons.isNotEmpty) icons.add(const SizedBox(width: 4));
          icons.add(Icon(Icons.style, color: Colors.amber[700], size: 20));
        }
        trailing = Row(mainAxisSize: MainAxisSize.min, children: icons);
      } else {
        trailing = Text("${data['yellow_cards'] ?? 0} amarelos", style: TextStyle(color: Colors.amber[800], fontWeight: FontWeight.bold));
      }
    } else {
      final val = data[widget.statField] ?? 0;
      trailing = Text("$val ${widget.statLabel ?? ''}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16));
    }

    return ListTile(
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: Colors.grey[200],
        backgroundImage: photoUrl.isNotEmpty ? CachedNetworkImageProvider(photoUrl, cacheManager: PlayerCacheManager.instance) : null,
        child: photoUrl.isEmpty ? Icon(isStaff ? Icons.assignment_ind : Icons.person, color: Colors.grey) : null,
      ),
      title: Text(displayName, style: TextStyle(fontStyle: isStaff ? FontStyle.italic : FontStyle.normal)),
      subtitle: Row(
        children: [
          if (shieldUrl.isNotEmpty) ...[
            CachedNetworkImage(imageUrl: shieldUrl, width: 16, height: 16, fit: BoxFit.contain, errorWidget: (_,__,___)=>const Icon(Icons.shield, size:16)),
            const SizedBox(width: 4)
          ],
          Flexible(child: Text(teamName, overflow: TextOverflow.ellipsis)),
        ],
      ),
      trailing: trailing,
      onTap: () {
        final auth = Provider.of<AuthService>(context, listen: false);
        if (widget.isSuspendedTab && auth.isAuthenticated) {
          _showClearSuspensionDialog(doc);
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerProfileScreen(playerId: doc.id)));
        }
      },
    );
  }
}