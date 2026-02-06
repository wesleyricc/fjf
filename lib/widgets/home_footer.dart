import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HomeFooter extends StatelessWidget {
  // Parâmetro opcional para a versão
  final String? appVersion;

  const HomeFooter({
    super.key, 
    this.appVersion
  });

  final List<Map<String, dynamic>> _socialLinks = const [
    {'icon': FontAwesomeIcons.facebook, 'url': 'https://www.facebook.com/forcajovemfumacense', 'color': Colors.white},
    {'icon': FontAwesomeIcons.instagram, 'url': 'https://www.instagram.com/fjf.forcajovem', 'color': Colors.white},
    {'icon': FontAwesomeIcons.youtube, 'url': 'https://www.youtube.com/@forcajovemfumacense', 'color': Colors.white},
  ];

  Future<void> _launchURL(String urlString) async {
    if (urlString.isEmpty) return;
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Erro ao abrir: $urlString');
    }
  }

  Future<void> _openRegulation(BuildContext context) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('config').doc('app_settings').get();
      final url = doc.data()?['regulation_pdf_url'] as String?;
      if (url != null && url.isNotEmpty) {
        _launchURL(url);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Regulamento não disponível.')));
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF1A1A1A), // Fundo escuro moderno
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      child: Column(
        children: [
          // Título
          const Text(
            "CONECTE-SE CONOSCO",
            style: TextStyle(color: Colors.white70, letterSpacing: 1.5, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // Ícones Sociais
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _socialLinks.map((link) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: IconButton(
                  icon: FaIcon(link['icon'], color: link['color'], size: 28),
                  onPressed: () => _launchURL(link['url']),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Botão Regulamento
          OutlinedButton.icon(
            icon: const Icon(Icons.description_outlined, color: Colors.white),
            label: const Text('BAIXAR REGULAMENTO', style: TextStyle(color: Colors.white)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white54),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () => _openRegulation(context),
          ),
          
          const SizedBox(height: 30),
          const Divider(color: Colors.white24),
          const SizedBox(height: 10),
          
          // Copyright
          const Text(
            '© FJF 2026 - Todos os direitos reservados',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 4),
          const Text(
            'Desenvolvido por Wesley Ricardo',
            style: TextStyle(color: Colors.white24, fontSize: 10),
          ),

          // --- VERSÃO DO APP (Agora integrada) ---
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