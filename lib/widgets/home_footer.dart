import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart'; // Necessário
import '../services/championship_service.dart'; // Necessário

class HomeFooter extends StatelessWidget {
  final String? appVersion;

  const HomeFooter({
    super.key, 
    this.appVersion
  });

  Future<void> _launchURL(String urlString) async {
    if (urlString.isEmpty) return;
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Erro ao abrir: $urlString');
    }
  }

  Future<void> _openRegulation(BuildContext context) async {
    try {
      // 1. Obtém o ID da temporada atual do Provider
      final seasonId = Provider.of<ChampionshipService>(context, listen: false).currentSeasonId;
      
      if (seasonId.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhuma temporada selecionada.')));
        }
        return;
      }

      // 2. Busca na subcoleção 'settings' da temporada específica
      // Caminho: championships > {seasonId} > settings > {primeiro_doc} > regulation_pdf_url
      final querySnapshot = await FirebaseFirestore.instance
          .collection('championships')
          .doc(seasonId)
          .collection('settings')
          .limit(1) 
          .get();

      String? url;
      if (querySnapshot.docs.isNotEmpty) {
        url = querySnapshot.docs.first.data()['regulation_pdf_url'] as String?;
      }

      if (url != null && url.isNotEmpty) {
        _launchURL(url);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Regulamento não disponível para esta temporada.')));
        }
      }
    } catch (e) {
      debugPrint("Erro ao buscar regulamento: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A1A), // Fundo escuro moderno
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      child: Column(
        children: [
          // Título
          const Text(
            "CONECTE-SE CONOSCO",
            style: TextStyle(color: Colors.white70, letterSpacing: 1.2, fontSize: 11, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          // Ícones Sociais Nativos (Material) - À prova de adblockers e compatíveis com a web
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: IconButton(
                  icon: const Icon(Icons.facebook, color: Colors.white, size: 26),
                  onPressed: () => _launchURL('https://www.facebook.com/forcajovemfumacense'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: IconButton(
                  icon: const Icon(Icons.photo_camera, color: Colors.white, size: 24), // Representando o Instagram
                  onPressed: () => _launchURL('https://www.instagram.com/fjf.forcajovem'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: IconButton(
                  icon: const Icon(Icons.smart_display, color: Colors.white, size: 26), // Representando o YouTube
                  onPressed: () => _launchURL('https://www.youtube.com/@forcajovemfumacense'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Botão Regulamento
          OutlinedButton.icon(
            icon: const Icon(Icons.description_outlined, color: Colors.white, size: 18),
            label: const Text('BAIXAR REGULAMENTO', style: TextStyle(color: Colors.white, fontSize: 11)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white54),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            onPressed: () => _openRegulation(context),
          ),
          
          const SizedBox(height: 16),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 12),
          
          // Copyright
          const Text(
            '© FJF 2026 - Todos os direitos reservados',
            style: TextStyle(color: Colors.white38, fontSize: 10),
          ),
          const SizedBox(height: 2),
          const Text(
            'Desenvolvido por Wesley Ricardo',
            style: TextStyle(color: Colors.white24, fontSize: 9),
          ),

          // --- VERSÃO DO APP ---
          if (appVersion != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'v$appVersion',
                style: const TextStyle(color: Colors.white12, fontSize: 9, fontFamily: 'monospace'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}