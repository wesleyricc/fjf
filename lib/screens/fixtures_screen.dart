// lib/screens/fixtures_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import 'package:intl/intl.dart';
import 'admin_match_screen.dart';
import '../services/admin_service.dart';
import '../services/data_uploader_service.dart';
import '../widgets/sponsor_banner_rotator.dart';

class FixturesScreen extends StatefulWidget {
  const FixturesScreen({super.key});

  @override
  State<FixturesScreen> createState() => _FixturesScreenState();
}



class _FixturesScreenState extends State<FixturesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  int _selectedRound = 1; // Você pode buscar isso do 'config'
  
  bool _isAdmin = AdminService.isAdmin;

  // Diálogo de confirmação para o upload
  Future<void> _showUploadConfirmDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        bool isLoading = false;
        // Usamos um StatefulBuilder para atualizar o estado do diálogo
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Carregar Dados Iniciais'),
              content: Text(
                isLoading 
                ? 'Carregando... Por favor, aguarde.'
                : 'ATENÇÃO!\n\nIsso irá sobrescrever quaisquer times e jogadores com IDs correspondentes.\n\nUse apenas para a configuração inicial. Deseja continuar?',
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancelar'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                ),
                TextButton(
                  child: isLoading 
                        ? const CircularProgressIndicator() 
                        : const Text('Confirmar Carga'),
                  onPressed: isLoading ? null : () async {

                    setDialogState(() { isLoading = true; });

                    final uploader = DataUploaderService();
                    final String result = await uploader.uploadInitialData();

                    setDialogState(() { isLoading = false; });

                    if (mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(result), duration: const Duration(seconds: 5)),
                      );
                    }
                  },
                ),
              ],
            );
          }
        );
      },
    );
  }

  Future<void> _showAdminLoginDialog() async {
    final TextEditingController passwordController = TextEditingController();

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Acesso Admin'),
          content: TextField(
            controller: passwordController,
            obscureText: true, // Esconde a senha
            decoration: const InputDecoration(labelText: 'Senha'),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Entrar'),
              onPressed: () {
                // SENHA "SECRETA" - Mude isso para sua senha
                if (passwordController.text == 'admin123') {
                  setState(() {
                    _isAdmin = true; // Libera o modo admin
                  });
                  AdminService.isAdmin = true; // Seta o global
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Modo Admin ativado!')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Senha incorreta.')),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // 1. Título dinâmico
        title: Text('Jogos'),
        actions: [
          // 2. Botões de navegação de rodada
          IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            tooltip: 'Rodada Anterior',
            onPressed: () {
              // Evita rodadas negativas ou zero
              if (_selectedRound > 1) {
                setState(() {
                  _selectedRound--;
                });
              }
            },
          ),
          Text(
            'Rod. $_selectedRound', // Mostra a rodada atual entre as setas
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios),
            tooltip: 'Próxima Rodada',
            onPressed: () {
              // Você pode adicionar um limite máximo se souber o total de rodadas
              setState(() {
                _selectedRound++;
              });
            },
          ),
          
          // Espaçador para separar dos botões de admin
          const SizedBox(width: 10), 

          // Botões de admin existentes
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.upload_file),
              tooltip: 'Carregar Dados Iniciais (Admin)',
              onPressed: () {
                if (_isAdmin) {
                  _showUploadConfirmDialog(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Você deve estar logado como admin.')),
                  );
                }
              },
            ),
          
          IconButton(
            icon: Icon(_isAdmin ? Icons.lock_open : Icons.lock),
            onPressed: () {
              if (_isAdmin) {
                setState(() {
                  _isAdmin = false;
                });
                AdminService.isAdmin = false; 
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Modo Admin desativado.')),
                );
              } else {
                _showAdminLoginDialog();
              }
            },
          ),
        ],
      ),
      drawer: const AppDrawer(), // Adiciona o menu lateral
      body: StreamBuilder<QuerySnapshot>(
        // Busca os jogos da rodada selecionada
        stream: _firestore
            .collection('matches')
            .where('round', isEqualTo: _selectedRound)
            .orderBy('datetime')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Nenhum jogo encontrado para esta rodada.'));
          }

          final matches = snapshot.data!.docs;

          // --- 1. ENVOLVE TUDO EM UM SingleChildScrollView ---
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16.0), // Espaço extra no final
            child: Column(
              children: [
                
                // --- 2. A LISTA DE JOGOS (agora dentro do Column) ---
                ListView.builder(
                  // --- ESSENCIAL PARA LISTVIEW DENTRO DE COLUMN ---
                  shrinkWrap: true, 
                  physics: const NeverScrollableScrollPhysics(), 
                  // --- FIM DA PARTE ESSENCIAL ---
                  itemCount: matches.length,
                  itemBuilder: (context, index) {
                    final match = matches[index];
                    final data = match.data() as Map<String, dynamic>;

                    final String scoreHome = data['score_home']?.toString() ?? '-';
                    final String scoreAway = data['score_away']?.toString() ?? '-';

                    String formattedDate = 'Data a definir';
                    if (data['datetime'] != null && data['datetime'] is Timestamp) {
                      final DateTime date = (data['datetime'] as Timestamp).toDate();
                      formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(date);
                    } else if (data['datetime'] != null && data['datetime'] is String) {
                       try {
                         final DateTime date = DateTime.parse(data['datetime']);
                         formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(date);
                       } catch (e) { /* Mantém 'Data a definir' */ }
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0), // Ajuste a margem se necessário
                      child: ListTile(
                        leading: Image.network(data['team_home_shield'], width: 40, errorBuilder: (c, o, s) => const Icon(Icons.shield)),
                        title: Center(
                          child: Text(
                            '${data['team_home_name']} $scoreHome x $scoreAway ${data['team_away_name']}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        trailing: Image.network(data['team_away_shield'], width: 40, errorBuilder: (c, o, s) => const Icon(Icons.shield)),
                        subtitle: Center(child: Text(formattedDate)), 
                        onTap: () {
                          if (_isAdmin) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (ctx) => AdminMatchScreen(match: match),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Você precisa estar no modo admin para editar jogos.')),
                            );
                          }
                        },
                      ),
                    );
                  },
                ), // Fim do ListView.builder

                // --- 3. ÁREA DE PATROCINADORES (Tela Cheia) ---
                const SizedBox(height: 50), // Espaço antes dos banners
                
                // Título ainda pode ter padding lateral
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    'Patrocinadores',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 1),

                // --- COLOCA O ROTATOR DIRETAMENTE NO COLUMN ---
                // Sem Padding horizontal envolvendo ele
                const SponsorBannerRotator(), 
                // --- FIM DA ÁREA DE PATROCINADORES ---
              ],
            ),
          );
        },
      ),
    );
  }
}