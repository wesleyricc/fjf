import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Services & Models
import '../services/firestore_service.dart';
import '../services/championship_service.dart';
import '../models/team_model.dart'; 

class EditTeamScreen extends StatefulWidget {
  final Team? team; // Recebe o Objeto Team (null se for criação)

  const EditTeamScreen({super.key, this.team});

  @override
  State<EditTeamScreen> createState() => _EditTeamScreenState();
}

class _EditTeamScreenState extends State<EditTeamScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirestoreService _firestoreService = FirestoreService();

  late TextEditingController _nameController;
  late TextEditingController _shortNameController;
  late TextEditingController _shieldUrlController;

  bool _isSaving = false;
  String _currentShieldUrl = '';
  List<Map<String, dynamic>> _championshipHistory = [];

  @override
  void initState() {
    super.initState();
    
    // Inicializa com dados do Model (se existir)
    _nameController = TextEditingController(text: widget.team?.name ?? '');
    _shortNameController = TextEditingController(text: widget.team?.shortName ?? '');
    _shieldUrlController = TextEditingController(text: widget.team?.shieldUrl ?? '');
    _currentShieldUrl = widget.team?.shieldUrl ?? '';

    if (widget.team != null) {
      // Clona a lista para não alterar o objeto original antes de salvar
      _championshipHistory = List<Map<String, dynamic>>.from(widget.team!.championshipHistory);
      _championshipHistory.sort((a, b) => (b['year'] as int).compareTo(a['year'] as int));
    }

    _shieldUrlController.addListener(() {
      if (mounted && _currentShieldUrl != _shieldUrlController.text) {
        setState(() {
          _currentShieldUrl = _shieldUrlController.text;
        });
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _shortNameController.dispose();
    _shieldUrlController.dispose();
    super.dispose();
  }

  Future<void> _saveForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    // Obtém o ID da Temporada Atual
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    String result;
    try {
      final name = _nameController.text.trim();
      final shortName = _shortNameController.text.toUpperCase().trim();
      final shieldUrl = _shieldUrlController.text.trim();

      _championshipHistory.sort((a, b) => (b['year'] as int).compareTo(a['year'] as int));

      if (widget.team == null) {
        // --- CRIAÇÃO ---
        result = await _firestoreService.createTeam(
          seasonId: seasonId,
          name: name,
          shortName: shortName,
          shieldUrl: shieldUrl,
          championshipHistory: _championshipHistory,
        );
      } else {
        // --- ATUALIZAÇÃO ---
        // Obtém o snapshot atualizado usando o método helper do serviço
        // Isso garante que estamos pegando a referência correta na temporada atual
        final docSnap = await _firestoreService.getTeamSnapshot(widget.team!.id, seasonId);
        
        if (docSnap != null && docSnap.exists) {
           result = await _firestoreService.updateTeam(
            teamDoc: docSnap,
            name: name,
            shortName: shortName,
            shieldUrl: shieldUrl,
            championshipHistory: _championshipHistory,
          );
        } else {
          result = "Erro: Time não encontrado no banco.";
        }
      }

       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
         if (result.startsWith('Sucesso')) {
            Navigator.of(context).pop();
         }
       }
    } catch (e) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e')));
    } finally {
       if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _showAddTitleDialog() async {
    final yearController = TextEditingController();
    int selectedRank = 1; 

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Adicionar Título'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: yearController,
                    decoration: const InputDecoration(labelText: 'Ano (Ex: 2024)'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 4,
                  ),
                  DropdownButtonFormField<int>(
                    value: selectedRank,
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('Campeão (Ouro)')),
                      DropdownMenuItem(value: 2, child: Text('Vice-Campeão (Prata)')),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => selectedRank = value);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                TextButton(
                  onPressed: () {
                    final int? year = int.tryParse(yearController.text);
                    if (year == null || yearController.text.length != 4) return;
                    
                    setState(() {
                      _championshipHistory.add({'year': year, 'rank': selectedRank});
                      _championshipHistory.sort((a, b) => (b['year'] as int).compareTo(a['year'] as int));
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('Adicionar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.team != null;
    final currentSeasonName = Provider.of<ChampionshipService>(context, listen: false).currentSeasonName;
    
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isEditing ? 'Editar Equipe' : 'Criar Nova Equipe'),
            Text('Em: $currentSeasonName', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w300)),
          ],
        ),
        actions: [
          IconButton(
            icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save),
            onPressed: _isSaving ? null : _saveForm,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            Center(
              child: Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: _currentShieldUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: _currentShieldUrl,
                        fit: BoxFit.contain,
                        placeholder: (_,__) => const Center(child: CircularProgressIndicator()),
                        errorWidget: (_,__,___) => const Icon(Icons.broken_image, color: Colors.grey, size: 40),
                      )
                    : const Icon(Icons.shield, size: 50, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 20),
            
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nome Completo', border: OutlineInputBorder(), prefixIcon: Icon(Icons.groups)),
              validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null,
              enabled: !_isSaving,
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _shortNameController,
              decoration: const InputDecoration(labelText: 'Sigla (Ex: FLA)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.short_text)),
              maxLength: 3,
              textCapitalization: TextCapitalization.characters,
              validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null,
              enabled: !_isSaving,
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _shieldUrlController,
              decoration: const InputDecoration(labelText: 'URL do Escudo', border: OutlineInputBorder(), prefixIcon: Icon(Icons.link)),
              keyboardType: TextInputType.url,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Obrigatório';
                if (!v.startsWith('http')) return 'URL inválida';
                return null;
              },
              enabled: !_isSaving,
            ),
            
            const Divider(height: 40),
            
            // Histórico de Títulos
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Títulos Anteriores', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                IconButton(icon: Icon(Icons.add_circle, color: Theme.of(context).primaryColor), onPressed: _isSaving ? null : _showAddTitleDialog),
              ],
            ),
            
            if (_championshipHistory.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: Text('Nenhum título registrado.', style: TextStyle(color: Colors.grey))))
            else
              Wrap(
                spacing: 8.0, runSpacing: 8.0,
                children: _championshipHistory.map((title) {
                  final int rank = title['rank'];
                  final int year = title['year'];
                  final Color bg = rank == 1 ? Colors.amber : Colors.grey[400]!;
                  return Chip(
                    avatar: const Icon(Icons.emoji_events, size: 16, color: Colors.white),
                    label: Text('$year', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    backgroundColor: bg,
                    deleteIcon: const Icon(Icons.close, size: 16, color: Colors.white),
                    onDeleted: () => setState(() => _championshipHistory.remove(title)),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}