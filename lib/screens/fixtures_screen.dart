// lib/screens/fixtures_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/app_drawer.dart';
import 'package:intl/intl.dart';
import 'admin_match_screen.dart';
import '../services/admin_service.dart';
import '../services/data_uploader_service.dart';
import '../widgets/sponsor_banner_rotator.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert'; // Para utf8
import '../services/admin_service.dart';
import 'match_stats_screen.dart';
import 'team_detail_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';

class FixturesScreen extends StatefulWidget {
  const FixturesScreen({super.key});

  @override
  State<FixturesScreen> createState() => _FixturesScreenState();
}

// Função para gerar o hash SHA-256 de uma string
String _hashPassword(String password) {
  final bytes = utf8.encode(password); // Converte para bytes UTF-8
  final digest = sha256.convert(bytes); // Calcula o hash
  return digest.toString(); // Retorna a representação hexadecimal
}

class _FixturesScreenState extends State<FixturesScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  int _selectedRound = 1; // Você pode buscar isso do 'config'
  
  bool _isAdmin = AdminService.isAdmin;

  // --- 2. ADICIONE A FUNÇÃO AUXILIAR DE NAVEGAÇÃO ---
  Future<void> _navigateToTeamDetail(BuildContext context, String teamId) async {
    // Mostra um indicador simples de loading
    ScaffoldMessenger.of(context).showSnackBar(
       const SnackBar(content: Text('Carregando dados da equipe...'), duration: Duration(seconds: 1)),
    );

    try {
      final teamDoc = await _firestore.collection('teams').doc(teamId).get();

      if (teamDoc.exists && mounted) { // Verifica se o doc existe E se a tela ainda está ativa
         Navigator.of(context).push(
           MaterialPageRoute(
             builder: (ctx) => TeamDetailScreen(teamDoc: teamDoc),
           ),
         );
      } else if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Não foi possível encontrar os dados da equipe ID: $teamId')),
         );
      }
    } catch (e) {
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Erro ao buscar equipe: ${e.toString()}')),
         );
       }
    }
  }
  // --- FIM DA FUNÇÃO AUXILIAR ---

  Future<void> _showChangeVideoIdDialog() async {
    final videoIdController = TextEditingController();
    bool isLoading = false;
    String currentVideoId = ''; // Para mostrar o ID atual

    // Busca o ID atual para preencher o campo
    try {
      final docSnap = await _firestore.collection('config').doc('app_settings').get();
      if (docSnap.exists) {
        currentVideoId = docSnap.get('live_video_id') ?? '';
        videoIdController.text = currentVideoId;
      }
    } catch (e) {
      debugPrint("Erro ao buscar ID de vídeo atual: $e");
      // Continua mesmo se não conseguir buscar o ID atual
    }

    if (!mounted) return; // Verifica se a tela ainda existe

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Alterar ID do Vídeo/Live'),
              content: TextField(
                controller: videoIdController,
                decoration: const InputDecoration(
                  labelText: 'ID do Vídeo do YouTube',
                  hintText: 'Ex: dQw4w9WgXcQ',
                ),
                enabled: !isLoading,
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: isLoading ? null : () async {
                    final newVideoId = videoIdController.text.trim(); // Remove espaços extras

                    if (newVideoId.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('O ID do vídeo não pode ser vazio.')));
                      return;
                    }
                    // Validação simples (IDs do YouTube geralmente têm 11 caracteres)
                    if (newVideoId.length < 10 || newVideoId.contains(' ')) {
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ID do vídeo parece inválido.')));
                       return;
                    }

                    setDialogState(() { isLoading = true; });

                    try {
                      // Atualiza no Firestore
                      await _firestore.collection('config').doc('app_settings').update({
                        'live_video_id': newVideoId
                      });

                      if(mounted) Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ID do vídeo atualizado com sucesso!')));

                    } catch (e) {
                       if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Erro ao atualizar ID: ${e.toString()}')),
                          );
                       }
                    } finally {
                       if (mounted) {
                         setDialogState(() { isLoading = false; });
                       }
                    }
                  },
                  child: isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }


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
    bool isLoading = false; // Estado para mostrar loading no diálogo

    return showDialog<void>(
      context: context,
      barrierDismissible: false, // Não fechar clicando fora
      builder: (BuildContext context) {
        return StatefulBuilder( // Para atualizar o estado do diálogo (loading)
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Acesso Admin'),
              content: TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Senha'),
                enabled: !isLoading, // Desabilita enquanto carrega
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancelar'),
                  onPressed: isLoading ? null : () => Navigator.of(context).pop(),
                ),
                TextButton(
                  // Mostra loading ou texto
                  child: isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Entrar'),
                  onPressed: isLoading ? null : () async {
                    final enteredPassword = passwordController.text;
                    if (enteredPassword.isEmpty) {
                       ScaffoldMessenger.of(context).showSnackBar(
                         const SnackBar(content: Text('Por favor, digite a senha.')),
                       );
                       return;
                    }

                    setDialogState(() { isLoading = true; }); // Inicia loading

                    try {
                      // 1. Calcula o hash da senha digitada
                      final enteredHash = _hashPassword(enteredPassword);

                      // 2. Busca o hash armazenado no Firestore
                      final docRef = _firestore.collection('config').doc('admin_credentials');
                      final docSnap = await docRef.get();

                      if (!docSnap.exists || !docSnap.data()!.containsKey('password_hash')) {
                         throw Exception('Configuração de senha admin não encontrada no Firestore.');
                      }
                      final storedHash = docSnap.get('password_hash');

                      // 3. Compara os hashes
                      if (enteredHash == storedHash) {
                        // Senha correta!
                        setState(() { _isAdmin = true; });
                        AdminService.isAdmin = true;
                        if (mounted) Navigator.of(context).pop(); // Fecha o diálogo
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Modo Admin ativado!')),
                        );
                      } else {
                        // Senha incorreta
                        throw Exception('Senha incorreta.');
                      }
                    } catch (e) {
                      // Mostra erro (senha incorreta ou problema no Firestore)
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Erro ao logar: ${e.toString().replaceFirst("Exception: ", "")}')),
                        );
                      }
                    } finally {
                      // Garante que o loading termine mesmo se der erro
                      if (mounted) {
                         setDialogState(() { isLoading = false; });
                      }
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
          
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.live_tv), // Ícone de TV
              tooltip: 'Alterar Vídeo Ao Vivo',
              onPressed: () {
                _showChangeVideoIdDialog(); // Chama a nova função
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
                        //leading: Image.network(data['team_home_shield'], width: 40, errorBuilder: (c, o, s) => const Icon(Icons.shield)),
                        // --- 3. ESCUDO CASA CLICÁVEL ---
                        leading: InkWell(
                          onTap: () {
                            final String homeTeamId = data['team_home_id'] ?? '';
                            if (homeTeamId.isNotEmpty) {
                              _navigateToTeamDetail(context, homeTeamId);
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(4.0), // Aumenta área de toque
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: CachedNetworkImage(
                                imageUrl: data['team_home_shield'] ?? '',
                                placeholder: (context, url) => const Center(child: Icon(Icons.shield, size: 30, color: Colors.grey)), // Placeholder simples
                                errorWidget: (context, url, error) => const Icon(Icons.shield, size: 40, color: Colors.grey),
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                        // --- FIM ESCUDO CASA ---
                        title: Center(
                          child: Text(
                            '${data['team_home_name'] ?? '?'} $scoreHome x $scoreAway ${data['team_away_name'] ?? '?'}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        //trailing: Image.network(data['team_away_shield'], width: 40, errorBuilder: (c, o, s) => const Icon(Icons.shield)),
                        subtitle: Center(child: Text(formattedDate)), 
                        // --- 4. ESCUDO FORA CLICÁVEL ---
                        trailing: InkWell(
                           onTap: () {
                             final String awayTeamId = data['team_away_id'] ?? '';
                             if (awayTeamId.isNotEmpty) {
                               _navigateToTeamDetail(context, awayTeamId);
                             }
                           },
                           child: Padding(
                             padding: const EdgeInsets.all(4.0), // Aumenta área de toque
                             child: SizedBox(
                                width: 40,
                                height: 40,
                                child: CachedNetworkImage(
                                  imageUrl: data['team_away_shield'] ?? '',
                                  placeholder: (context, url) => const Center(child: Icon(Icons.shield, size: 30, color: Colors.grey)),
                                  errorWidget: (context, url, error) => const Icon(Icons.shield, size: 40, color: Colors.grey),
                                  fit: BoxFit.contain,
                                ),
                             ),
                           ),
                        ),
                        // --- FIM ESCUDO FORA ---
                        onTap: () {

                          final gameStatus = data['status'] ?? 'pending';

                          if (_isAdmin) {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (ctx) => AdminMatchScreen(match: match),
                              ),
                            );
                          } else if (gameStatus == 'finished') {
                            // Não-Admin SÓ PODE ver stats de jogo FINALIZADO
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (ctx) => MatchStatsScreen(match: match), // <-- Vai para a nova tela
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('As estatísticas estarão disponíveis após o fim do jogo.')),
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