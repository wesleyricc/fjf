// lib/screens/voting/voting_list_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../../widgets/sponsor_banner_rotator.dart';

class VotingListScreen extends StatefulWidget {
  final String categoryTitle;
  final String categoryKey;

  const VotingListScreen({
    super.key,
    required this.categoryTitle,
    required this.categoryKey,
  });

  @override
  State<VotingListScreen> createState() => _VotingListScreenState();
}

class _VotingListScreenState extends State<VotingListScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isVoting = false;
  String? _filterTeamId; 

  Future<void> _submitVote(DocumentSnapshot doc, bool isFromPlayerCollection) async {
    setState(() => _isVoting = true);

    try {
      if (isFromPlayerCollection) {
        // Voto automático (Lê de players -> Salva em voting_stats)
        final data = doc.data() as Map<String, dynamic>;
        final String originalId = doc.id;
        final String statsDocId = '${widget.categoryKey}_$originalId';
        
        await _firestore.collection('voting_stats').doc(statsDocId).set({
          'category': widget.categoryKey,
          'original_id': originalId,
          'name': data['name'],
          'team_name': data['team_name'],
          'photo_url': data['photo_url'],
          'votes': FieldValue.increment(1),
          'last_vote_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

      } else {
        // Voto manual (Já está em voting_stats)
        await doc.reference.update({
          'votes': FieldValue.increment(1),
          'last_vote_at': FieldValue.serverTimestamp(),
        });
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('voted_${widget.categoryKey}', true);

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Voto Confirmado!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 60),
              const SizedBox(height: 16),
              Text('Seu voto para "${widget.categoryTitle}" foi registrado.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop();
              },
              child: const Text('OK', style: TextStyle(fontSize: 18)),
            )
          ],
        ),
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao votar: $e')));
    } finally {
      if (mounted) setState(() => _isVoting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- ALTERAÇÃO: Removido 'melhor_jogador' da lista automática ---
    final bool isAutomaticPlayerList = 
        widget.categoryKey == 'craque' || 
        // widget.categoryKey == 'melhor_jogador' ||  <-- REMOVIDO
        widget.categoryKey == 'treinador';

    final bool showFilter = isAutomaticPlayerList && widget.categoryKey != 'treinador';

    return Scaffold(
      appBar: AppBar(title: Text(widget.categoryTitle)),
      body: _isVoting
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (showFilter)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                    child: StreamBuilder<QuerySnapshot>(
                      stream: _firestore.collection('teams').orderBy('name').snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) return Text("Erro ao carregar times: ${snapshot.error}");
                        if (!snapshot.hasData) return const LinearProgressIndicator();
                        
                        List<DropdownMenuItem<String>> items = [];
                        items.add(const DropdownMenuItem(value: null, child: Text('Selecione uma Equipe...')));
                        
                        for(var doc in snapshot.data!.docs) {
                           final data = doc.data() as Map<String, dynamic>;
                           final String shieldUrl = data['shield_url'] ?? '';
                           
                           items.add(DropdownMenuItem(
                             value: doc.id, 
                             child: Row(
                               children: [
                                 if (shieldUrl.isNotEmpty)
                                   Padding(
                                     padding: const EdgeInsets.only(right: 8.0),
                                     child: CachedNetworkImage(
                                       imageUrl: shieldUrl,
                                       width: 24, height: 24,
                                       errorWidget: (c, u, e) => const Icon(Icons.shield, size: 24, color: Colors.grey),
                                     ),
                                   ),
                                 Expanded(child: Text(data['name'] ?? 'Time', overflow: TextOverflow.ellipsis)),
                               ],
                             ),
                           ));
                        }
                        return SizedBox(
                          height: 60,
                          child: DropdownButtonFormField<String>(
                            value: _filterTeamId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Filtrar por Equipe', 
                              border: OutlineInputBorder(), 
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)
                            ),
                            items: items,
                            onChanged: (v) => setState(() => _filterTeamId = v),
                          ),
                        );
                      },
                    ),
                  ),

                Expanded(
                  child: isAutomaticPlayerList 
                      ? _buildAutomaticList() 
                      : _buildManualList(),
                ),
              ],
            ),
      bottomNavigationBar: const SponsorBannerRotator(),
    );
  }

  // Agora 'melhor_jogador' cai aqui (Manual List)
  Widget _buildManualList() {
    bool isVideo = widget.categoryKey == 'bola_cheia' || widget.categoryKey == 'bola_murcha';

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('voting_stats').where('category', isEqualTo: widget.categoryKey).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("Nenhum candidato disponível."));

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final data = doc.data() as Map<String, dynamic>;
            
            if (isVideo) {
              return _buildVideoCandidateCard(doc, data);
            }
            return _buildPlayerCard(doc, data, false); 
          },
        );
      },
    );
  }

  Widget _buildAutomaticList() {
    bool isFilterMandatory = widget.categoryKey == 'craque'; // Melhor jogador saiu daqui

    if (isFilterMandatory && _filterTeamId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.filter_alt_outlined, size: 60, color: Colors.grey[400]),
              const SizedBox(height: 16),
              const Text(
                "Para votar nesta categoria, selecione primeiro uma equipe acima.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      );
    }

    Query query = _firestore.collection('players').where('isActive', isEqualTo: true);

    if (_filterTeamId != null) {
      query = query.where('team_id', isEqualTo: _filterTeamId);
    }

    if (widget.categoryKey == 'treinador') {
      query = query.where('is_staff', isEqualTo: true);
    } 
    else {
      query = query.where('is_staff', isEqualTo: false).orderBy('name');
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("Nenhum candidato encontrado."));

        var docs = snapshot.data!.docs;
        
        if (widget.categoryKey == 'treinador') {
          docs = docs.where((d) {
            final role = (d['staff_role'] ?? '').toString().toLowerCase();
            return role.trim() == 'técnico'; 
          }).toList();
        }

        if (docs.isEmpty) return const Center(child: Text("Nenhum candidato encontrado."));

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildPlayerCard(doc, data, true); 
          },
        );
      },
    );
  }

  Widget _buildPlayerCard(DocumentSnapshot doc, Map<String, dynamic> data, bool isPlayerCollection) {
    final String name = data['name'] ?? 'Nome';
    final String team = data['team_name'] ?? 'Time';
    final String photoUrl = data['photo_url'] ?? '';
    
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: SizedBox(
              height: 400,
              width: double.infinity,
              child: photoUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: photoUrl,
                      fit: BoxFit.cover,
                      placeholder: (c, u) => const Center(child: CircularProgressIndicator()),
                      errorWidget: (c, u, e) => Container(color: Colors.grey[300], child: const Icon(Icons.person, size: 80, color: Colors.grey)),
                    )
                  : Container(color: Colors.grey[300], child: const Icon(Icons.person, size: 80, color: Colors.grey)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text(team, style: const TextStyle(fontSize: 16, color: Colors.grey)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                    onPressed: () => _submitVote(doc, isPlayerCollection),
                    child: const Text('VOTAR', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoCandidateCard(DocumentSnapshot doc, Map<String, dynamic> data) {
    final String playTitle = data['description'] ?? 'Lance'; 
    final String playerName = data['name'] ?? 'Jogador';
    final String teamName = data['team_name'] ?? 'Time';
    final String videoUrl = data['video_url'] ?? '';
    
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 24.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsets.all(12.0), child: Text(playTitle, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
          if (videoUrl.isNotEmpty)
            _FirebaseVideoPlayerItem(videoUrl: videoUrl)
          else
            Container(height: 200, color: Colors.black, child: const Center(child: Text('Vídeo indisponível', style: TextStyle(color: Colors.white)))),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(children: [
                Text("$playerName ($teamName)", style: const TextStyle(fontSize: 16, color: Colors.black87), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity, 
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))), 
                    onPressed: () => _submitVote(doc, false), 
                    child: const Text('VOTAR NESTE LANCE', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))
                  )
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _FirebaseVideoPlayerItem extends StatefulWidget {
  final String videoUrl;
  const _FirebaseVideoPlayerItem({required this.videoUrl});
  @override
  State<_FirebaseVideoPlayerItem> createState() => _FirebaseVideoPlayerItemState();
}
class _FirebaseVideoPlayerItemState extends State<_FirebaseVideoPlayerItem> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isError = false;
  @override
  void initState() { super.initState(); _initializePlayer(); }
  Future<void> _initializePlayer() async {
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await _videoPlayerController.initialize();
      _chewieController = ChewieController(videoPlayerController: _videoPlayerController, autoPlay: false, looping: false, aspectRatio: _videoPlayerController.value.aspectRatio, placeholder: Container(color: Colors.black), autoInitialize: true, showControls: true, errorBuilder: (context, errorMessage) => Center(child: Text(errorMessage, style: const TextStyle(color: Colors.white))));
      if(mounted) setState(() {});
    } catch (e) { debugPrint("Erro ao carregar vídeo: $e"); if (mounted) setState(() => _isError = true); }
  }
  @override
  void dispose() { _videoPlayerController.dispose(); _chewieController?.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (_isError) return Container(height: 200, color: Colors.black, child: const Center(child: Text("Erro ao carregar", style: TextStyle(color: Colors.white))));
    if (_chewieController != null && _videoPlayerController.value.isInitialized) return AspectRatio(aspectRatio: _videoPlayerController.value.aspectRatio, child: Chewie(controller: _chewieController!));
    return Container(height: 200, color: Colors.black, child: const Center(child: CircularProgressIndicator(color: Colors.white)));
  }
}