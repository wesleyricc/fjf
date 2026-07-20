import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/championship_service.dart';
import '../../services/voting_service.dart';
import '../../models/poll_model.dart';
import '../../models/player_model.dart';

class AdminEditPollScreen extends StatefulWidget {
  final Poll? poll;

  const AdminEditPollScreen({super.key, this.poll});

  @override
  State<AdminEditPollScreen> createState() => _AdminEditPollScreenState();
}

class _AdminEditPollScreenState extends State<AdminEditPollScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _videoUrlController;
  late String _selectedCategory;
  late bool _isActive;
  bool _isSaving = false;

  final Map<String, String> _categories = {
    'craque_rodada': 'Craque da Rodada',
    'bola_cheia': 'Bola Cheia (com Vídeo)',
    'bola_murcha': 'Bola Murcha (com Vídeo)',
    'craque_campeonato': 'Craque do Campeonato',
    'craque_galera': 'Craque da Galera',
    'melhor_treinador': 'Melhor Treinador',
    'revelacao': 'Revelação',
    'selecao_campeonato': 'Seleção do Campeonato'
  };

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.poll?.title ?? '');
    _videoUrlController = TextEditingController(text: widget.poll?.videoUrl ?? '');
    _selectedCategory = widget.poll?.category ?? 'craque_rodada';
    _isActive = widget.poll?.isActive ?? false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ChampionshipService>(context, listen: false).fetchAllPlayers();
    });
  }

  Future<void> _savePoll() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
      final votingService = VotingService();

      final data = {
        'title': _titleController.text.trim(),
        'category': _selectedCategory,
        'video_url': _videoUrlController.text.trim(),
        'is_active': _isActive,
      };

      if (widget.poll == null) {
        await votingService.createPoll(seasonId, data);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Votação criada!')));
          Navigator.pop(context); 
        }
      } else {
        await votingService.updatePoll(seasonId, widget.poll!.id, data);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Votação atualizada!')));
          Navigator.pop(context); 
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _removeNominee(String nomineeId) async {
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    await VotingService().removeNominee(seasonId, widget.poll!.id, nomineeId);
  }

  Future<void> _deletePoll() async {
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    await VotingService().deletePoll(seasonId, widget.poll!.id);
    if (mounted) Navigator.pop(context);
  }

  void _showAddNomineeModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _PlayerSearchModal(pollId: widget.poll!.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.poll == null ? 'Nova Votação' : 'Editar Votação'),
        actions: [
          if (widget.poll != null)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              onPressed: _deletePoll,
            )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(labelText: 'Título da Votação (Ex: Craque da 3ª Rodada)', border: OutlineInputBorder()),
                    validator: (v) => v!.isEmpty ? 'Informe o título' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    decoration: const InputDecoration(labelText: 'Categoria', border: OutlineInputBorder()),
                    items: _categories.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (val) => setState(() => _selectedCategory = val!),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _videoUrlController,
                    decoration: const InputDecoration(labelText: 'Link do YouTube/Instagram (Opcional)', border: OutlineInputBorder(), hintText: 'https://www.youtube.com/watch?v=...'),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Votação Ativa (Aparece no App)'),
                    subtitle: const Text('Apenas uma votação deve ficar ativa por vez no banner principal.'),
                    value: _isActive,
                    onChanged: (val) => setState(() => _isActive = val),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _savePoll,
                      child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text('SALVAR VOTAÇÃO', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            if (widget.poll == null)
              const Center(child: Text("Salve a votação primeiro para adicionar os indicados.", style: TextStyle(color: Colors.grey)))
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Atletas Indicados', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  if (!['craque_galera', 'melhor_treinador', 'selecao_campeonato'].contains(widget.poll!.category))
                    TextButton.icon(
                      onPressed: _showAddNomineeModal,
                      icon: const Icon(Icons.person_add),
                      label: const Text('Adicionar'),
                    )
                ],
              ),
              const Divider(),
              // OTIMIZADO: Substituído QuerySnapshot genérico pelo Stream Tipado
              StreamBuilder<List<Nominee>>(
                stream: VotingService().streamNominees(seasonId, widget.poll!.id),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final nominees = snapshot.data!;

                  if (nominees.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text("Nenhum indicado cadastrado."));

                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: nominees.length,
                    itemBuilder: (context, index) {
                      final nom = nominees[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: nom.playerPhotoUrl.isNotEmpty ? CachedNetworkImageProvider(nom.playerPhotoUrl) : null,
                          child: nom.playerPhotoUrl.isEmpty ? const Icon(Icons.person) : null,
                        ),
                        title: Text(nom.playerName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("${nom.teamName} • ${nom.voteCount} votos"),
                        trailing: IconButton(icon: const Icon(Icons.remove_circle_outline, color: Colors.red), onPressed: () => _removeNominee(nom.id)),
                      );
                    },
                  );
                },
              )
            ]
          ],
        ),
      ),
    );
  }
}

class _PlayerSearchModal extends StatefulWidget {
  final String pollId;
  const _PlayerSearchModal({required this.pollId});

  @override
  State<_PlayerSearchModal> createState() => _PlayerSearchModalState();
}

class _PlayerSearchModalState extends State<_PlayerSearchModal> {
  String _searchQuery = '';

  Future<void> _addSelectedPlayer(Player player) async {
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
    
    final data = {
      'player_id': player.id,
      'player_name': player.name,
      'player_photo_url': player.photoUrl,
      'team_name': player.teamName,
      'team_shield_url': player.teamShieldUrl,
      'vote_count': 0,
    };

    await VotingService().addNominee(seasonId, widget.pollId, data);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final allPlayers = Provider.of<ChampionshipService>(context).allPlayers;
    
    final filteredPlayers = allPlayers.where((p) {
      return p.name.toLowerCase().contains(_searchQuery.toLowerCase()) || 
             p.teamName.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text("Selecionar Atleta", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(
                hintText: "Buscar por nome ou equipe...",
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: filteredPlayers.length,
                itemBuilder: (context, index) {
                  final p = filteredPlayers[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: p.photoUrl.isNotEmpty ? CachedNetworkImageProvider(p.photoUrl) : null,
                      child: p.photoUrl.isEmpty ? const Icon(Icons.person) : null,
                    ),
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(p.teamName),
                    trailing: const Icon(Icons.add_circle, color: Colors.green),
                    onTap: () => _addSelectedPlayer(p),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }
}