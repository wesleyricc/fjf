import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/firebase_storage_service.dart';

class AdminSponsorsScreen extends StatelessWidget {
  const AdminSponsorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Gestão de Patrocinadores'),
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('sponsors')
            .orderBy('location')
            .orderBy('order')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Nenhum patrocinador cadastrado.'));
          }

          final sponsors = snapshot.data!.docs;

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: sponsors.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final doc = sponsors[index];
              final data = doc.data() as Map<String, dynamic>;

              return Card(
                elevation: 2,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 50, height: 50,
                      child: data['imageUrl'] != null && data['imageUrl'].toString().isNotEmpty
                          ? Image.network(
                              data['imageUrl'], 
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.red),
                            )
                          : const Icon(Icons.image, color: Colors.grey),
                    ),
                  ),
                  title: Text(data['name'] ?? 'Sem Nome (ID: ${doc.id.substring(0, 5)})', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("Categoria: ${data['category'] ?? 'BRONZE'}\nLocal: ${data['location']} | Ordem: ${data['order'] ?? 0}\n${data['isActive'] == true ? '🟢 ATIVO' : '🔴 INATIVO'}"),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.edit, color: Colors.indigo),
                    onPressed: () => _showSponsorForm(context, doc),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showSponsorForm(context, null),
        backgroundColor: Colors.green,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text("Novo Banner", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _showSponsorForm(BuildContext context, DocumentSnapshot? doc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _SponsorFormModal(sponsorDoc: doc),
    );
  }
}

class _SponsorFormModal extends StatefulWidget {
  final DocumentSnapshot? sponsorDoc;
  const _SponsorFormModal({this.sponsorDoc});

  @override
  State<_SponsorFormModal> createState() => _SponsorFormModalState();
}

class _SponsorFormModalState extends State<_SponsorFormModal> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _nameController;
  late TextEditingController _imageUrlController;
  late TextEditingController _targetUrlController;
  late TextEditingController _displayTimeSecondsController; 
  late TextEditingController _orderController;
  late TextEditingController _roundController; 
  
  List<String> _selectedLocations = [];
  String _selectedCategory = 'BRONZE';
  bool _isActive = true;
  bool _isSaving = false;
  bool _isUploadingImage = false;

  @override
  void initState() {
    super.initState();
    final data = widget.sponsorDoc?.data() as Map<String, dynamic>?;

    _nameController = TextEditingController(text: data?['name'] ?? '');
    _imageUrlController = TextEditingController(text: data?['imageUrl'] ?? '');
    _targetUrlController = TextEditingController(text: data?['targetUrl'] ?? '');
    _displayTimeSecondsController = TextEditingController(text: (data?['displayTimeSeconds'] ?? 5).toString());
    _orderController = TextEditingController(text: (data?['order'] ?? 1).toString());
    _roundController = TextEditingController(text: data?['round']?.toString() ?? '');
    
    if (data != null && data['locations'] != null) {
      _selectedLocations = List<String>.from(data['locations']);
    } else if (data != null && data['location'] != null) {
      _selectedLocations = [data['location']];
    } else {
      _selectedLocations = ['footer_home'];
    }
    _selectedCategory = data?['category'] ?? 'BRONZE';
    _isActive = data?['isActive'] ?? true;
  }

  Future<void> _pickAndUploadImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (image == null) return;

    setState(() => _isUploadingImage = true);

    try {
      final downloadUrl = await FirebaseStorageService.uploadImage(
        image: image,
        bucketUrl: 'gs://acefjf-us-storage',
        folderPath: 'sponsors',
      );
      
      setState(() {
        _imageUrlController.text = downloadUrl ?? '';
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload de imagem concluído!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro no upload: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _saveSponsor() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final collection = FirebaseFirestore.instance.collection('sponsors');

      final Map<String, dynamic> sponsorData = {
        'name': _nameController.text.trim(),
        'imageUrl': _imageUrlController.text.trim(),
        'targetUrl': _targetUrlController.text.trim(),
        'location': _selectedLocations.isNotEmpty ? _selectedLocations.first : 'footer_home',
        'locations': _selectedLocations,
        'category': _selectedCategory,
        'displayTimeSeconds': int.tryParse(_displayTimeSecondsController.text) ?? 5,
        'order': int.tryParse(_orderController.text) ?? 1,
        'isActive': _isActive,
      };

      final roundNumber = int.tryParse(_roundController.text.trim());
      
      if (widget.sponsorDoc == null) {
        if (_selectedLocations.contains('header_fixtures') && roundNumber != null) {
          sponsorData['round'] = roundNumber; 
        }
        await collection.add(sponsorData);
        
      } else {
        if (_selectedLocations.contains('header_fixtures') && roundNumber != null) {
          sponsorData['round'] = roundNumber;
        } else {
          sponsorData['round'] = FieldValue.delete();
        }
        await collection.doc(widget.sponsorDoc!.id).update(sponsorData);
      }

      if (mounted) {
        Navigator.pop(context); 
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Patrocinador salvo com sucesso!'), backgroundColor: Colors.green)
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteSponsor() async {
    if (widget.sponsorDoc == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Banner?'),
        content: const Text('Tem certeza que deseja remover este patrocinador?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir', style: TextStyle(color: Colors.white))),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('sponsors').doc(widget.sponsorDoc!.id).delete();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(widget.sponsorDoc == null ? 'Novo Patrocinador' : 'Editar Patrocinador', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  if (widget.sponsorDoc != null)
                    IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: _deleteSponsor)
                ],
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Nome da Empresa (Controle Interno)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedCategory,
                      decoration: const InputDecoration(labelText: 'Categoria', border: OutlineInputBorder(), prefixIcon: Icon(Icons.star)),
                      items: const [
                        DropdownMenuItem(value: 'MASTER', child: Text('MASTER (Destaque Máximo)')),
                        DropdownMenuItem(value: 'PREMIUM', child: Text('PREMIUM (Destaque Alto)')),
                        DropdownMenuItem(value: 'OURO', child: Text('OURO (Destaque Médio)')),
                        DropdownMenuItem(value: 'PRATA', child: Text('PRATA (Destaque Normal)')),
                        DropdownMenuItem(value: 'BRONZE', child: Text('BRONZE (Padrão)')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedCategory = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text('Locais de Exibição:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: _buildLocationChips(),
                    ),
                    const SizedBox(height: 12),
                    if (_selectedLocations.contains('header_fixtures')) ...[
                      TextFormField(
                        controller: _roundController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Rodada Específica (Opcional)', 
                          hintText: 'Ex: 3 (Deixe vazio para aparecer em todas)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.sports_soccer)
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _imageUrlController,
                            decoration: const InputDecoration(labelText: 'Link da Imagem (URL)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.image)),
                            validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _isUploadingImage ? null : _pickAndUploadImage,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                            backgroundColor: Colors.blueGrey[800],
                            foregroundColor: Colors.white,
                          ),
                          icon: _isUploadingImage 
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                            : const Icon(Icons.upload_file),
                          label: const Text('Upload'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _targetUrlController,
                      decoration: const InputDecoration(labelText: 'Link de Redirecionamento (WhatsApp/Site)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.link)),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _orderController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Ordem (1, 2, 3...)', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _displayTimeSecondsController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Tempo (Segundos)', border: OutlineInputBorder()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Banner Ativo', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Exibir no aplicativo agora'),
                      value: _isActive,
                      activeColor: Colors.green,
                      onChanged: (val) => setState(() => _isActive = val),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveSponsor,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[900], foregroundColor: Colors.white),
                  child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text('SALVAR DADOS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildLocationChips() {
    final Map<String, String> availableLocations = {
      'home_partners_grid': 'Vitrine de Parceiros (Home)',
      'footer_home': 'Rodapé Fixo (Global)',
      'app_open': 'Splash Screen (Abertura)',
      'home_mid': 'Meio da Tela Inicial',
      'header_fixtures': 'Topo da Tabela de Jogos',
      'news_feed': 'Feed de Notícias',
      'grid_teams': 'Grid de Equipes',
      'fantasy': 'Módulo Fantasy / Bolão',
      'header_live': 'Ao Vivo',
      'header_match_roster': 'Pré-Jogo (Escalação)',
      'header_match_stats': 'Resumo da Partida',
      'header_teams': 'Lista de Equipes',
      'header_standings': 'Classificação',
      'header_team_stats': 'Estatísticas da Equipe',
      'header_summary': 'Resumo da Temporada',
      'header_player_stats': 'Estatísticas do Jogador',
      'header_comparator': 'Comparador de Jogadores',
      'header_suspensions': 'Histórico de Suspensões',
      'footer_player_profile': 'Rodapé do Perfil do Jogador',
      'footer_team_detail': 'Rodapé dos Detalhes da Equipe',
    };

    return availableLocations.entries.map((entry) {
      final isSelected = _selectedLocations.contains(entry.key);
      return FilterChip(
        label: Text(entry.value, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : Colors.black87)),
        selected: isSelected,
        selectedColor: Colors.blue.shade700,
        checkmarkColor: Colors.white,
        onSelected: (bool selected) {
          setState(() {
            if (selected) {
              _selectedLocations.add(entry.key);
            } else {
              _selectedLocations.remove(entry.key);
            }
          });
        },
      );
    }).toList();
  }
}