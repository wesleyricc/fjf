// lib/screens/report_bug_screen.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart'; // Import necessário para abrir o WhatsApp
import '../widgets/app_drawer.dart';
import '../widgets/sponsor_banner_rotator.dart';

class ReportBugScreen extends StatefulWidget {
  const ReportBugScreen({super.key});

  @override
  State<ReportBugScreen> createState() => _ReportBugScreenState();
}

class _ReportBugScreenState extends State<ReportBugScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // --- CONFIGURAÇÃO ---
  // Coloque aqui o número do WhatsApp com o código do país e DDD (sem o +)
  // Exemplo: 55 (Brasil) + 48 (DDD) + 999999999
  final String supportNumber = "5548996381626"; 
  // --------------------

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _reportType = 'Erro de Estatística'; 
  bool _isSending = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _sendReportToWhatsApp() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() { _isSending = true; });

    try {
      // 1. Formatar a mensagem
      final String cleanNumber = supportNumber.replaceAll(RegExp(r'[^\d]'), '');
      final String message = 
          "*REPORT DE BUG/ERRO - FJF APP*\n\n"
          "*Tipo:* $_reportType\n"
          "*Título:* ${_titleController.text}\n"
          "*Descrição:* ${_descriptionController.text}\n\n"
          "Enviado pelo App.";

      // 2. Codificar a mensagem para URL (tratar espaços, acentos, quebras de linha)
      final String encodedMessage = Uri.encodeComponent(message);
      
      // 3. Criar a URL do WhatsApp
      final Uri whatsappUrl = Uri.parse("https://api.whatsapp.com/send?phone=$cleanNumber&text=$encodedMessage");

      // 4. Tentar abrir o WhatsApp
      if (await canLaunchUrl(whatsappUrl)) {
        await launchUrl(
          whatsappUrl,
          mode: LaunchMode.externalApplication,
        );
        
        // Limpa o formulário após o envio bem-sucedido (opcional)
        if (mounted) {
          _titleController.clear();
          _descriptionController.clear();
          setState(() { _reportType = 'Erro de Estatística'; });
        }
      }  else {
        // Fallback: Tenta lançar sem verificar o canLaunchUrl (às vezes necessário no Android 11+)
        await launchUrl(
          whatsappUrl,
          mode: LaunchMode.externalApplication,
        );
      }

    } catch (e) {
      debugPrint("Erro ao abrir WhatsApp: $e");
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
       
            SnackBar(content: Text('Não foi possível abrir o WhatsApp: $e')),
          );
      }
    } finally {
       if (mounted) setState(() { _isSending = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportar via WhatsApp'),
      ),
      drawer: const AppDrawer(),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.chat_outlined, size: 60, color: Colors.green),
              const SizedBox(height: 16),
              Text(
                'Encontrou um problema? Preencha abaixo e envie diretamente para nosso suporte no WhatsApp.',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              DropdownButtonFormField<String>(
                value: _reportType,
                decoration: const InputDecoration(
                  labelText: 'Tipo de Report',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Erro de Estatística',
                    child: Text('Erro de Estatística (Ex: Placar errado)'),
                  ),
                  DropdownMenuItem(
                    value: 'Bug Visual/Funcional',
                    child: Text('Bug no App (Ex: Botão não funciona)'),
                  ),
                  DropdownMenuItem(
                    value: 'Outro',
                    child: Text('Outro Assunto'),
                  ),
                ],
                onChanged: _isSending ? null : (value) {
                  if (value != null) {
                    setState(() { _reportType = value; });
                  }
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Assunto Resumido',
                  hintText: 'Ex: Placar jogo X vs Y',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.isEmpty) ? 'Obrigatório.' : null,
                enabled: !_isSending,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Detalhes',
                  hintText: 'Descreva o que está errado...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 6,
                validator: (value) => (value == null || value.isEmpty) ? 'Obrigatório.' : null,
                enabled: !_isSending,
              ),
              const SizedBox(height: 32),

              ElevatedButton.icon(
                icon: _isSending
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send),
                label: Text(_isSending ? 'Abrindo WhatsApp...' : 'Enviar para o WhatsApp'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, // Cor do WhatsApp
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                onPressed: _isSending ? null : _sendReportToWhatsApp,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const SponsorBannerRotator(),
    );
  }
}