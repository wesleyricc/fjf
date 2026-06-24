import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../models/poll_model.dart';
import '../models/player_model.dart';
import '../services/championship_service.dart';
import '../services/voting_service.dart';
import '../services/fantasy_auth_service.dart';
import '../services/analytics_service.dart'; // 🚨 RASTREAMENTO
import 'draft_selection_screen.dart';

class VotingScreen extends StatefulWidget {
  final Poll poll;

  const VotingScreen({super.key, required this.poll});

  @override
  State<VotingScreen> createState() => _VotingScreenState();
}

class _VotingScreenState extends State<VotingScreen> {
  YoutubePlayerController? _ytController;
  bool _hasVoted = false;
  bool _isCheckingVote = true;
  String? _userVotedNomineeId;
  bool _isProcessingVote = false;
  
  // Para Votação Livre
  String _searchQuery = '';

  bool get _isFreeVote => widget.poll.category == 'craque_galera' || widget.poll.category == 'melhor_treinador';
  bool get _isDraftSelection => widget.poll.category == 'selecao_campeonato';

  @override
  void initState() {
    super.initState();
    
    // 🚨 Analytics: Acesso à tela de Votação/Enquetes Específicas
    AnalyticsService.logCustomScreenView(
      'Voting_Screen', 
      parameters: {
        'poll_id': widget.poll.id, 
        'poll_category': widget.poll.category
      }
    );

    _initializeVideo();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIfUserHasVoted();
      // Se for votação livre ou draft, garante que todos os jogadores estão carregados no cache
      if (_isFreeVote || _isDraftSelection) {
        Provider.of<ChampionshipService>(context, listen: false).fetchAllPlayers();
      }
    });
  }

  void _initializeVideo() {
    if (widget.poll.videoUrl != null && widget.poll.videoUrl!.isNotEmpty) {
      final videoId = YoutubePlayerController.convertUrlToId(widget.poll.videoUrl!);
      if (videoId != null) {
        _ytController = YoutubePlayerController.fromVideoId(
          videoId: videoId,
          autoPlay: false,
          params: const YoutubePlayerParams(
            showControls: true,
            mute: false,
            showFullscreenButton: true,
            loop: false,
          ),
        );
      }
    }
  }

  Future<void> _checkIfUserHasVoted() async {
    final authService = Provider.of<FantasyAuthService>(context, listen: false);
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    if (authService.user != null) {
      final hasVoted = await VotingService().hasUserVoted(seasonId, widget.poll.id, authService.user!.uid);
      if (mounted) {
        setState(() {
          _hasVoted = hasVoted;
          _isCheckingVote = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _hasVoted = false;
          _isCheckingVote = false;
        });
      }
    }
  }

  // Voto em Lista Fechada
  Future<void> _handleVote(Nominee nominee) async {
    // 🚨 Analytics: Tentativa de voto em lista fechada
    AnalyticsService.logCustomScreenView('Voting_Action_Vote_Cast', parameters: {'poll_id': widget.poll.id});
    await _processVote(nomineeId: nominee.id);
  }

  // Voto Livre (Busca)
  Future<void> _handleFreeVote(Player player) async {
    // 🚨 Analytics: Tentativa de voto aberto
    AnalyticsService.logCustomScreenView('Voting_Action_Vote_Cast', parameters: {'poll_id': widget.poll.id});

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar Voto'),
        content: Text('Deseja confirmar seu voto em ${player.name} para ${widget.poll.title}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true), 
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.purple.shade900),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _processVote(freePlayerPick: player);
    }
  }

  Future<void> _processVote({String? nomineeId, Player? freePlayerPick}) async {
    final authService = Provider.of<FantasyAuthService>(context, listen: false);
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    if (authService.user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Faça login com o Google para registrar seu voto único!')));
      try {
        await authService.signInWithGoogle(); 
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Login cancelado ou falhou.')));
        return;
      }
      if (authService.user == null) return;
    }

    setState(() => _isProcessingVote = true);

    final result = await VotingService().castVote(
      seasonId: seasonId,
      pollId: widget.poll.id,
      userId: authService.user!.uid,
      existingNomineeId: nomineeId,
      freePlayerPick: freePlayerPick,
    );

    if (mounted) {
      setState(() => _isProcessingVote = false);
      if (result == "Sucesso") {
        setState(() {
          _hasVoted = true;
          _userVotedNomineeId = nomineeId ?? freePlayerPick?.id;
        });
        
        // 🚨 Analytics: Voto computado com Sucesso!
        AnalyticsService.logCustomScreenView('Vote_Cast_Success', parameters: {'poll_id': widget.poll.id});

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voto registrado com sucesso! Obrigado.', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.green));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result), backgroundColor: Colors.red));
      }
    }
  }

  @override
  void dispose() {
    _ytController?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Votação Oficial'),
        backgroundColor: Colors.purple.shade900,
        foregroundColor: Colors.white,
      ),
      body: _isCheckingVote
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildVotingContent()),
              ],
            ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.poll.category.toUpperCase().replaceAll('_', ' '), style: TextStyle(color: Colors.purple.shade900, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
                const SizedBox(height: 4),
                Text(widget.poll.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.black87)),
              ],
            ),
          ),
          if (_ytController != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 5))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: YoutubePlayer(controller: _ytController!),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildVotingContent() {
    if (_hasVoted) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 80),
            const SizedBox(height: 16),
            const Text("Voto Computado!", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green)),
            const SizedBox(height: 8),
            const Text("Seu voto foi registrado com segurança.\nOs resultados são secretos até o encerramento.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade900, foregroundColor: Colors.white),
              child: const Text("Voltar para o Início"),
            )
          ],
        ),
      );
    }

    if (_isDraftSelection) {
      return _buildDraftEntry();
    } else if (_isFreeVote) {
      return _buildFreeVotingList();
    } else {
      return _buildStandardVotingList();
    }
  }

  // --- MODO: SELEÇÃO DO CAMPEONATO ---
  Widget _buildDraftEntry() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sports_soccer, size: 60, color: Colors.purple.shade900),
            const SizedBox(height: 16),
            const Text("Monte a sua Seleção!", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text("Escale os 11 melhores atletas do campeonato na sua opinião (Goleiros, Fixos, Alas, Pivôs e Treinador).", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () async {
                  // O 'await' espera ele voltar da tela de Draft. 
                  // Se ele voltar com 'true' (salvou), atualizamos a tela para "Computado"
                  final didVote = await Navigator.push(
                    context, 
                    MaterialPageRoute(builder: (_) => DraftSelectionScreen(poll: widget.poll))
                  );
                  if (didVote == true && mounted) {
                    setState(() {
                      _hasVoted = true;
                    });
                  }
                },
                icon: const Icon(Icons.edit_attributes),
                label: const Text("ENTRAR NO CAMPO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.purple.shade900),
              )
            )
          ],
        ),
      ),
    );
  }

  // --- MODO: VOTAÇÃO LIVRE (PESQUISA) ---
  Widget _buildFreeVotingList() {
    final allPlayers = Provider.of<ChampionshipService>(context).allPlayers;
    
    // Se for votação de Treinador, filtramos apenas quem é "Staff". Senão, todos.
    final List<Player> pool = widget.poll.category == 'melhor_treinador' 
        ? allPlayers.where((p) => p.isStaff).toList()
        : allPlayers;

    final filteredPlayers = pool.where((p) {
      return p.name.toLowerCase().contains(_searchQuery.toLowerCase()) || 
             p.teamName.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            decoration: InputDecoration(
              hintText: "Digite o nome do atleta ou equipe...",
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 0)
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ),
        Expanded(
          child: filteredPlayers.isEmpty 
              ? const Center(child: Text("Nenhum atleta encontrado.", style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filteredPlayers.length,
                  itemBuilder: (context, index) {
                    final player = filteredPlayers[index];
                    return Card(
                      elevation: 1,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: player.photoUrl.isNotEmpty ? CachedNetworkImageProvider(player.photoUrl) : null,
                          child: player.photoUrl.isEmpty ? const Icon(Icons.person) : null,
                        ),
                        title: Text(player.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(player.teamName),
                        trailing: _isProcessingVote 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : ElevatedButton(
                                onPressed: () => _handleFreeVote(player),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.purple.shade900),
                                child: const Text("VOTAR"),
                              ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // --- MODO: VOTAÇÃO PADRÃO (LISTA FECHADA) ---
  Widget _buildStandardVotingList() {
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    return StreamBuilder<List<Nominee>>(
      stream: VotingService().streamNominees(seasonId, widget.poll.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('Nenhum atleta indicado ainda.'));

        final nominees = snapshot.data!;

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: nominees.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final nominee = nominees[index];

            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: nominee.playerPhotoUrl.isNotEmpty ? CachedNetworkImageProvider(nominee.playerPhotoUrl) : null,
                      child: nominee.playerPhotoUrl.isEmpty ? const Icon(Icons.person, color: Colors.grey, size: 30) : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(nominee.playerName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              if (nominee.teamShieldUrl.isNotEmpty) ...[
                                CachedNetworkImage(imageUrl: nominee.teamShieldUrl, width: 16, height: 16),
                                const SizedBox(width: 6),
                              ],
                              Expanded(child: Text(nominee.teamName, style: TextStyle(fontSize: 13, color: Colors.grey[600]), overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: ElevatedButton(
                        onPressed: _isProcessingVote ? null : () => _handleVote(nominee),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.purple.shade900,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        child: _isProcessingVote 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.purple, strokeWidth: 2))
                            : const Text("VOTAR", style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}