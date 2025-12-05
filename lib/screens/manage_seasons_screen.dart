import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/championship_service.dart';

class ManageSeasonsScreen extends StatefulWidget {
  const ManageSeasonsScreen({super.key});

  @override
  State<ManageSeasonsScreen> createState() => _ManageSeasonsScreenState();
}

class _ManageSeasonsScreenState extends State<ManageSeasonsScreen> {
  bool _isProcessing = false;

  // --- LÓGICA DE CRIAÇÃO ---
  Future<void> _handleCreateSeason(
    int year, String name, String honoree, bool copyTeams, bool copyPlayers
  ) async {
    setState(() => _isProcessing = true);
    
    final service = Provider.of<ChampionshipService>(context, listen: false);
    final result = await service.createSeason(
      year, name, honoree,
      copyTeams: copyTeams,
      copyPlayers: copyPlayers,
    );

    if (mounted) {
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result == "Sucesso" ? 'Temporada criada com sucesso!' : result),
        backgroundColor: result == "Sucesso" ? Colors.green : Colors.red,
      ));
    }
  }

  Future<void> _showCreateDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => _CreateSeasonDialog(onConfirm: _handleCreateSeason),
    );
  }

  // --- LÓGICA DE EDIÇÃO ---
  Future<void> _showEditDialog(Map<String, dynamic> seasonData) async {
    final TextEditingController nameCtrl = TextEditingController(text: seasonData['name']);
    final TextEditingController honoreeCtrl = TextEditingController(text: seasonData['honoree']);
    
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar ${seasonData['year']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nome')),
            TextFormField(controller: honoreeCtrl, decoration: const InputDecoration(labelText: 'Homenageado')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isProcessing = true);
              
              final service = Provider.of<ChampionshipService>(context, listen: false);
              final res = await service.updateSeason(seasonData['id'], nameCtrl.text, honoreeCtrl.text);
              
              if (mounted) {
                setState(() => _isProcessing = false);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res)));
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final championshipService = Provider.of<ChampionshipService>(context);
    final currentId = championshipService.currentSeasonId;
    
    // Lista apenas as temporadas disponíveis no banco (sem injetar legado manualmente)
    final List<Map<String, dynamic>> allSeasons = championshipService.availableSeasons;

    return Scaffold(
      appBar: AppBar(title: const Text('Gerenciar Temporadas')),
      body: _isProcessing 
        ? const Center(child: CircularProgressIndicator())
        : allSeasons.isEmpty 
            ? const Center(child: Text("Nenhuma temporada encontrada.\nCrie a primeira abaixo.", textAlign: TextAlign.center))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: allSeasons.length,
                itemBuilder: (context, index) {
                  final season = allSeasons[index];
                  final bool isSelected = (season['id'] == currentId);
                  final bool isGlobalActive = season['isActive'] == true;
                  
                  return _SeasonCard(
                    season: season,
                    isSelected: isSelected,
                    isGlobalActive: isGlobalActive,
                    onEdit: () => _showEditDialog(season),
                    onActivate: () async {
                       setState(() => _isProcessing = true);
                       final res = await championshipService.setGlobalActiveSeason(season['id']);
                       if (mounted) {
                         setState(() => _isProcessing = false);
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res)));
                       }
                    },
                    onView: () async {
                       await championshipService.setSeason(season['id']);
                       if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Visualizando temporada.')));
                    },
                  );
                },
              ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        label: const Text('Nova Temporada'),
        icon: const Icon(Icons.add),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
    );
  }
}

// --- COMPONENTES INTERNOS ---

class _SeasonCard extends StatelessWidget {
  final Map<String, dynamic> season;
  final bool isSelected;
  final bool isGlobalActive;
  final VoidCallback onEdit;
  final VoidCallback onActivate;
  final VoidCallback onView;

  const _SeasonCard({
    required this.season,
    required this.isSelected,
    required this.isGlobalActive,
    required this.onEdit,
    required this.onActivate,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: isSelected ? 4 : 1,
      color: isSelected ? Colors.green[50] : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isSelected ? BorderSide(color: Colors.green[700]!, width: 2) : BorderSide.none
      ),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: isGlobalActive ? Colors.amber : Colors.grey[300],
              child: Icon(Icons.emoji_events, color: isGlobalActive ? Colors.black : Colors.grey[700]),
            ),
            title: Text(season['name'], style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(season['honoree'] ?? ''),
                if (isGlobalActive) 
                  const Text('★ PADRÃO (Ativa) ★', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 10)),
              ],
            ),
            // Agora todas as temporadas são editáveis, pois todas seguem o padrão novo
            trailing: IconButton(icon: const Icon(Icons.edit), onPressed: onEdit),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!isGlobalActive)
                  TextButton(
                    onPressed: onActivate,
                    child: const Text('Tornar Padrão', style: TextStyle(color: Colors.amber)),
                  ),
                const SizedBox(width: 8),
                if (isSelected)
                  const Chip(label: Text('Visualizando', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green)
                else
                  ElevatedButton(
                    onPressed: onView,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[200], foregroundColor: Colors.black87, elevation: 0),
                    child: const Text('Visualizar'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateSeasonDialog extends StatefulWidget {
  final Function(int, String, String, bool, bool) onConfirm;
  const _CreateSeasonDialog({required this.onConfirm});

  @override
  State<_CreateSeasonDialog> createState() => _CreateSeasonDialogState();
}

class _CreateSeasonDialogState extends State<_CreateSeasonDialog> {
  final _formKey = GlobalKey<FormState>();
  final _yearCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _honoreeCtrl = TextEditingController();
  bool _copyTeams = true;
  bool _copyPlayers = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova Temporada'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _yearCtrl,
                decoration: const InputDecoration(labelText: 'Ano (ex: 2026)'),
                keyboardType: TextInputType.number,
                maxLength: 4,
                validator: (v) => (v == null || v.length != 4) ? 'Ano inválido' : null,
              ),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nome (ex: Copa 2026)'),
                validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
              ),
              TextFormField(
                controller: _honoreeCtrl,
                decoration: const InputDecoration(labelText: 'Homenageado'),
                validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('Importar Times'),
                subtitle: const Text('Copia os times da temporada atual zerando pontos.'),
                value: _copyTeams,
                onChanged: (v) => setState(() => _copyTeams = v),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: const Text('Manter Elencos'),
                subtitle: const Text('Copia jogadores e vincula aos times.'),
                value: _copyPlayers,
                onChanged: _copyTeams ? (v) => setState(() => _copyPlayers = v) : null,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context);
              widget.onConfirm(
                int.parse(_yearCtrl.text),
                _nameCtrl.text,
                _honoreeCtrl.text,
                _copyTeams,
                _copyPlayers,
              );
            }
          },
          child: const Text('Criar'),
        ),
      ],
    );
  }
}