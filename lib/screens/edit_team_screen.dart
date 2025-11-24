import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart'; // <-- Importante
import '../services/firestore_service.dart';
import '../services/championship_service.dart'; // <-- Importante
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart'; 

class EditTeamScreen extends StatefulWidget {
  final DocumentSnapshot? team;

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
    
    final data = widget.team?.data() as Map<String, dynamic>? ?? {};

    _nameController = TextEditingController(text: data['name'] ?? '');
    _shortNameController = TextEditingController(text: data['short_name'] ?? '');
    _shieldUrlController = TextEditingController(text: data['shield_url'] ?? '');
    _currentShieldUrl = data['shield_url'] ?? '';

    if (data['championship_history'] != null) {
      _championshipHistory = List<Map<String, dynamic>>.from(
        (data['championship_history'] as List<dynamic>).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      _championshipHistory.sort((a, b) => (b['year'] as int).compareTo(a['year'] as int));
    }

    _shieldUrlController.addListener(() {
      if (mounted) {
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

    setState(() { _isSaving = true; });

    // 1. Obtém o ID da Temporada Atual
    // Usamos listen: false porque não precisamos reconstruir a tela se o ano mudar durante o save
    final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;

    String result;
    try {
      final name = _nameController.text;
      final shortName = _shortNameController.text.toUpperCase();
      final shieldUrl = _shieldUrlController.text;

      _championshipHistory.sort((a, b) => (b['year'] as int).compareTo(a['year'] as int));

      if (widget.team == null) {
        // --- MODO CRIAÇÃO ---
        // Passamos o seasonId para saber onde criar
        result = await _firestoreService.createTeam(
          seasonId: seasonId, // <-- NOVO
          name: name,
          shortName: shortName,
          shieldUrl: shieldUrl,
          championshipHistory: _championshipHistory,
        );
      } else {
        // --- MODO ATUALIZAÇÃO ---
        // A atualização é feita direto na referência do documento, então seasonId é menos crítico aqui,
        // mas a estrutura do serviço já lida com isso.
        result = await _firestoreService.updateTeam(
          teamDoc: widget.team!,
          name: name,
          shortName: shortName,
          shieldUrl: shieldUrl,
          championshipHistory: _championshipHistory,
        );
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
       if (mounted) setState(() { _isSaving = false; });
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
                      if (value != null) {
                        setDialogState(() => selectedRank = value);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
                TextButton(
                  onPressed: () {
                    final int? year = int.tryParse(yearController.text);
                    if (year == null || yearController.text.length != 4) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Ano inválido.')),
                      );
                      return;
                    }
                    setState(() {
                      _championshipHistory.add({'year': year, 'rank': selectedRank});
                      _championshipHistory.sort((a, b) => (b['year'] as int).compareTo(a['year'] as int));
                    });
                    Navigator.of(ctx).pop(true);
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
    bool isEditing = widget.team != null;
    final currentSeasonName = Provider.of<ChampionshipService>(context, listen: false).currentSeasonName;
    
    return Scaffold(
      appBar: AppBar(
        // Contexto visual para o admin saber onde está criando
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isEditing ? 'Editar Equipe' : 'Criar Nova Equipe'),
            Text('Em: $currentSeasonName', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w300)),
          ],
        ),
        actions: [
          IconButton(
            icon: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.save),
            onPressed: _isSaving ? null : _saveForm,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            if (_currentShieldUrl.isNotEmpty)
              Center(
                child: CachedNetworkImage(
                  imageUrl: _currentShieldUrl,
                  height: 80, width: 80, fit: BoxFit.contain,
                  placeholder: (c, u) => const SizedBox(height: 80, width: 80, child: Center(child: CircularProgressIndicator())),
                  errorWidget: (c, u, e) => const SizedBox(height: 80, width: 80, child: Icon(Icons.error_outline, color: Colors.red, size: 40)),
                ),
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nome Completo da Equipe', border: OutlineInputBorder()),
              validator: (value) => (value == null || value.isEmpty) ? 'Obrigatório' : null,
              enabled: !_isSaving,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _shortNameController,
              decoration: const InputDecoration(labelText: 'Sigla (Ex: FLA)', border: OutlineInputBorder()),
              maxLength: 3,
              textCapitalization: TextCapitalization.characters,
              validator: (value) => (value == null || value.isEmpty) ? 'Obrigatório' : null,
              enabled: !_isSaving,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _shieldUrlController,
              decoration: const InputDecoration(labelText: 'URL do Escudo (https://...)', border: OutlineInputBorder()),
              keyboardType: TextInputType.url,
              validator: (value) {
                if (value == null || value.isEmpty) return 'Obrigatório';
                if (!value.startsWith('http://') && !value.startsWith('https://')) return 'URL inválida';
                return null;
              },
              enabled: !_isSaving,
            ),
            const Divider(height: 32),
            Card(
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Histórico de Títulos', style: Theme.of(context).textTheme.titleMedium),
                        IconButton(
                          icon: Icon(Icons.add_circle, color: Theme.of(context).primaryColor),
                          tooltip: 'Adicionar Título',
                          onPressed: _isSaving ? null : _showAddTitleDialog,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_championshipHistory.isEmpty)
                      const Center(child: Text('Nenhum título registrado.', style: TextStyle(color: Colors.grey)))
                    else
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 4.0,
                        children: _championshipHistory.map((title) {
                          final int rank = title['rank'];
                          final int year = title['year'];
                          final Color color = rank == 1 ? Colors.amber : Colors.grey[600]!;
                          final Color labelColor = rank == 1 ? Colors.black87 : Colors.white;

                          return Chip(
                            avatar: Icon(Icons.emoji_events, color: labelColor, size: 18),
                            label: Text(year.toString(), style: TextStyle(color: labelColor, fontWeight: FontWeight.bold)),
                            backgroundColor: color,
                            deleteIcon: Icon(Icons.cancel, color: labelColor.withOpacity(0.7), size: 18),
                            onDeleted: _isSaving ? null : () {
                              setState(() {
                                _championshipHistory.remove(title);
                              });
                            },
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}