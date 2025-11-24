import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/championship_service.dart';
import '../services/firestore_service.dart';

class ManageSeasonsScreen extends StatefulWidget {
  const ManageSeasonsScreen({super.key});

  @override
  State<ManageSeasonsScreen> createState() => _ManageSeasonsScreenState();
}

class _ManageSeasonsScreenState extends State<ManageSeasonsScreen> {
  bool _isProcessing = false;

  // --- DIÁLOGO DE CRIAÇÃO ---
  Future<void> _showCreateSeasonDialog() async {
    final yearController = TextEditingController();
    final nameController = TextEditingController();
    final honoreeController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    // Estados dos Switches
    bool copyTeams = true;   // Padrão: Sim
    bool copyPlayers = true; // Padrão: Sim

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder( 
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Nova Temporada'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: yearController,
                      decoration: const InputDecoration(labelText: 'Ano (ex: 2026)'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      maxLength: 4,
                      validator: (v) => (v == null || v.length != 4) ? 'Ano inválido' : null,
                    ),
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Nome (ex: Copa FJF 2026)'),
                      validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null,
                    ),
                    TextFormField(
                      controller: honoreeController,
                      decoration: const InputDecoration(labelText: 'Homenageado'),
                      validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null,
                    ),
                    const SizedBox(height: 16),
                    const Text('Opções de Importação:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      title: const Text('Importar Equipes'),
                      subtitle: const Text('Copia os times da temporada atual zerando os pontos.'),
                      value: copyTeams,
                      onChanged: (val) => setStateDialog(() => copyTeams = val),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      title: const Text('Manter Elencos'),
                      subtitle: const Text('Mantém os titulares/reservas definidos.'),
                      value: copyPlayers,
                      onChanged: copyTeams ? (val) => setStateDialog(() => copyPlayers = val) : null, 
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
              ElevatedButton(
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  
                  final int year = int.parse(yearController.text);
                  final String name = nameController.text;
                  final String honoree = honoreeController.text;

                  Navigator.of(ctx).pop();
                  setState(() => _isProcessing = true);

                  final service = Provider.of<ChampionshipService>(context, listen: false);
                  
                  // --- CORREÇÃO AQUI ---
                  // Passa os argumentos obrigatórios posicionalmente
                  final result = await service.createSeason(
                    year,      // Posicional 1
                    name,      // Posicional 2
                    honoree,   // Posicional 3
                    copyTeams: copyTeams,      // Nomeado
                    copyPlayers: copyPlayers,  // Nomeado
                  );
                  // ---------------------

                  setState(() => _isProcessing = false);

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(result == "Sucesso" ? 'Temporada criada com sucesso!' : result),
                        backgroundColor: result == "Sucesso" ? Colors.green : Colors.red,
                      ),
                    );
                  }
                },
                child: const Text('Criar'),
              ),
            ],
          );
        }
      ),
    );
  }

  // --- DIÁLOGO EDITAR ---
  Future<void> _showEditSeasonDialog(Map<String, dynamic> seasonData) async {
    final nameController = TextEditingController(text: seasonData['name']);
    final honoreeController = TextEditingController(text: seasonData['honoree']);
    final formKey = GlobalKey<FormState>();
    final String seasonId = seasonData['id'];
    final int year = seasonData['year'];

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar Temporada $year'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(title: const Text("Ano (ID)"), subtitle: Text(year.toString()), contentPadding: EdgeInsets.zero, dense: true),
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Nome do Campeonato'),
                validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: honoreeController,
                decoration: const InputDecoration(labelText: 'Homenageado'),
                validator: (v) => (v == null || v.isEmpty) ? 'Obrigatório' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final String name = nameController.text;
              final String honoree = honoreeController.text;
              Navigator.of(ctx).pop();
              setState(() => _isProcessing = true);
              
              final service = Provider.of<ChampionshipService>(context, listen: false);
              final result = await service.updateSeason(seasonId, name, honoree);
              
              setState(() => _isProcessing = false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result == "Sucesso" ? 'Atualizado!' : result), backgroundColor: result == "Sucesso" ? Colors.green : Colors.red));
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
    
    final List<Map<String, dynamic>> allSeasons = [
      {
        'id': FirestoreService.LEGACY_ID,
        'name': 'FJF 2025 (Dados Originais)',
        'year': 2025,
        'honoree': 'Taça Mary Neusa Espíndola Bif',
        'isActive': false
      },
      ...championshipService.availableSeasons
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Gerenciar Temporadas')),
      body: _isProcessing 
        ? const Center(child: CircularProgressIndicator())
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: allSeasons.length,
            itemBuilder: (context, index) {
              final season = allSeasons[index];
              final String id = season['id'];
              final String name = season['name'];
              final String honoree = season['honoree'] ?? '';
              final bool isSelected = (id == currentId);
              final bool isLegacy = (id == FirestoreService.LEGACY_ID);
              // Lê a flag do objeto da lista (que vem do banco), não do service diretamente
              final bool isGlobalActive = season['isActive'] == true; 

              return Card(
                elevation: isSelected ? 4 : 1,
                color: isSelected ? Colors.green[50] : null,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: isSelected ? BorderSide(color: Colors.green[700]!, width: 2) : BorderSide.none),
                child: Column(
                  children: [
                    ListTile(
                      leading: CircleAvatar(backgroundColor: isGlobalActive ? Colors.amber : Colors.grey[300], child: Icon(Icons.emoji_events, color: isGlobalActive ? Colors.black : Colors.grey[700])),
                      title: Text(name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Homenageado: $honoree'), Text('ID: $id', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                         if (isGlobalActive) const Text('★ TEMPORADA ATIVA (PADRÃO) ★', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 10)),
                      ]),
                      trailing: isLegacy ? null : IconButton(icon: Icon(Icons.edit, color: Theme.of(context).primaryColor), onPressed: () => _showEditSeasonDialog(season)),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (!isGlobalActive && !isLegacy)
                            TextButton.icon(icon: const Icon(Icons.star_border, color: Colors.amber), label: const Text('Tornar Padrão', style: TextStyle(color: Colors.amber)), onPressed: () async {
                                setState(() => _isProcessing = true);
                                final res = await championshipService.setGlobalActiveSeason(id);
                                setState(() => _isProcessing = false);
                                if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res)));
                              }),
                          const SizedBox(width: 8),
                          if (isSelected) const Chip(label: Text('Visualizando'), backgroundColor: Colors.green, labelStyle: TextStyle(color: Colors.white))
                          else ElevatedButton(onPressed: () async {
                                await championshipService.setSeason(id);
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Visualizando: $name')));
                              }, style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[200], foregroundColor: Colors.black87, elevation: 0), child: const Text('Visualizar')),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateSeasonDialog,
        label: const Text('Nova Temporada'),
        icon: const Icon(Icons.add),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
    );
  }
}