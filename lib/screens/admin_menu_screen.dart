// lib/screens/admin_menu_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import '../services/data_uploader_service.dart'; // Para o upload
import 'dart:convert'; // Para utf8
import 'package:crypto/crypto.dart';
import '../services/data_uploader_service.dart';
import 'disciplinary_rules_screen.dart';

class AdminMenuScreen extends StatefulWidget {
  const AdminMenuScreen({super.key});

  @override
  State<AdminMenuScreen> createState() => _AdminMenuScreenState();
}

class _AdminMenuScreenState extends State<AdminMenuScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- COPIE AS FUNÇÕES DE DIÁLOGO DA FIXTURESSCREEN PARA CÁ ---

  // Função para gerar o hash SHA-256 de uma string
  String _hashPassword(String password) {
    final bytes = utf8.encode(password); // Converte para bytes UTF-8
    final digest = sha256.convert(bytes); // Calcula o hash
    return digest.toString(); // Retorna a representação hexadecimal
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
                  onPressed: isLoading
                      ? null
                      : () async {
                          setDialogState(() {
                            isLoading = true;
                          });

                          final uploader = DataUploaderService();
                          final String result = await uploader
                              .uploadInitialData();

                          setDialogState(() {
                            isLoading = false;
                          });

                          if (mounted) {
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(result),
                                duration: const Duration(seconds: 5),
                              ),
                            );
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showChangePasswordDialog() async {
    // Controladores para os campos de texto
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isLoading = false; // Estado de carregamento do diálogo

    // Mostra o diálogo
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // Não fechar clicando fora
      builder: (dialogContext) { // Usar um contexto diferente para o diálogo
        return StatefulBuilder( // Permite atualizar o estado do diálogo (loading)
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Alterar Senha Admin'),
              content: SingleChildScrollView( // Caso a tela seja pequena e o teclado apareça
                child: Column(
                  mainAxisSize: MainAxisSize.min, // Encolhe para o conteúdo
                  children: [
                    TextField(
                      controller: currentPasswordController,
                      obscureText: true, // Esconde a senha
                      decoration: const InputDecoration(labelText: 'Senha Atual'),
                      enabled: !isLoading, // Desabilita enquanto carrega
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: newPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Nova Senha'),
                      enabled: !isLoading,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Confirmar Nova Senha'),
                      enabled: !isLoading,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.of(dialogContext).pop(), // Fecha o diálogo
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: isLoading ? null : () async {
                    // Pega os valores dos campos
                    final currentPassword = currentPasswordController.text;
                    final newPassword = newPasswordController.text;
                    final confirmPassword = confirmPasswordController.text;

                    // --- Validações ---
                    if (currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('Preencha todos os campos.')));
                      return; // Impede o envio
                    }
                    if (newPassword != confirmPassword) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('As novas senhas não coincidem.')));
                      return;
                    }
                     if (newPassword.length < 6) { // Regra de força mínima
                      ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('A nova senha deve ter pelo menos 6 caracteres.')));
                      return;
                    }
                    // --- Fim Validações ---

                    // Inicia o estado de carregamento
                    setDialogState(() { isLoading = true; });

                    try {
                      // 1. Verifica a senha atual
                      final currentHash = _hashPassword(currentPassword); // Usa a função _hashPassword da classe
                      final docRef = _firestore.collection('config').doc('admin_credentials');
                      final docSnap = await docRef.get();

                      // Verifica se o documento e o campo existem
                      if (!docSnap.exists || !docSnap.data()!.containsKey('password_hash')) {
                         throw Exception('Configuração de senha admin não encontrada.');
                      }
                      final storedHash = docSnap.get('password_hash');

                      // Compara o hash digitado com o armazenado
                      if (currentHash != storedHash) {
                        throw Exception('Senha atual incorreta.');
                      }

                      // 2. Calcula o hash da nova senha
                      final newHash = _hashPassword(newPassword);

                      // 3. Atualiza o hash no Firestore
                      await docRef.update({'password_hash': newHash});

                      // Fecha o diálogo ANTES de mostrar o SnackBar de sucesso
                      if (Navigator.of(dialogContext).canPop()) {
                         Navigator.of(dialogContext).pop();
                      }
                      // Mostra mensagem de sucesso (usando o context principal se o dialogContext não for mais válido)
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Senha alterada com sucesso!')));

                    } catch (e) {
                      // Mostra mensagem de erro
                       if (Navigator.of(dialogContext).canPop()) { // Usa dialogContext para o SnackBar de erro
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text('Erro: ${e.toString().replaceFirst("Exception: ", "")}')),
                          );
                       }
                    } finally {
                       // Garante que o estado de carregamento termine
                       // Verifica se o diálogo ainda está montado antes de chamar setDialogState
                       // (Embora em caso de sucesso ele já tenha sido fechado)
                       if (Navigator.of(dialogContext).canPop()){
                          setDialogState(() { isLoading = false; });
                       }
                    }
                  },
                  // Exibe o indicador de carregamento ou o texto do botão
                  child: isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Alterar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showChangeVideoIdDialog() async {
    final videoIdController = TextEditingController();
    bool isLoading = false;
    String currentVideoId = ''; // Para mostrar o ID atual

    // Busca o ID atual para preencher o campo
    try {
      final docSnap = await _firestore
          .collection('config')
          .doc('app_settings')
          .get();
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
                  onPressed: isLoading
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          final newVideoId = videoIdController.text
                              .trim(); // Remove espaços extras

                          if (newVideoId.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'O ID do vídeo não pode ser vazio.',
                                ),
                              ),
                            );
                            return;
                          }
                          // Validação simples (IDs do YouTube geralmente têm 11 caracteres)
                          if (newVideoId.length < 10 ||
                              newVideoId.contains(' ')) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('ID do vídeo parece inválido.'),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            isLoading = true;
                          });

                          try {
                            // Atualiza no Firestore
                            await _firestore
                                .collection('config')
                                .doc('app_settings')
                                .update({'live_video_id': newVideoId});

                            if (mounted) Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'ID do vídeo atualizado com sucesso!',
                                ),
                              ),
                            );
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Erro ao atualizar ID: ${e.toString()}',
                                  ),
                                ),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setDialogState(() {
                                isLoading = false;
                              });
                            }
                          }
                        },
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Salvar'),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Menu Administrativo')),
      // drawer: const AppDrawer(), // Opcional: manter o drawer aqui?
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          ListTile(
            leading: const Icon(Icons.live_tv),
            title: const Text('Alterar Vídeo Ao Vivo'),
            subtitle: const Text('Muda o ID do vídeo na tela inicial'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _showChangeVideoIdDialog, // Chama a função movida
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.upload_file, color: Colors.orange),
            title: const Text('Carregar Dados Iniciais'),
            subtitle: const Text(
              'IMPORTANTE: Apaga e recarrega Times, Jogadores e Jogos!',
            ),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () =>
                _showUploadConfirmDialog(context), // Chama a função movida
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Alterar Senha Admin'),
            subtitle: const Text('Define uma nova senha de administrador'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: _showChangePasswordDialog, // Chama a função movida
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.rule_folder), // Ícone de regras
            title: const Text('Regras Disciplinares'),
            subtitle: const Text('Define limites de cartões para suspensão'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (ctx) => const DisciplinaryRulesScreen()),
              );
            },
          ),
          const Divider(),

          // Adicione mais opções administrativas aqui, se necessário
        ],
      ),
    );
  }
}
