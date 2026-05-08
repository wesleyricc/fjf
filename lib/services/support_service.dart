import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class SupportService {
  // Configuração
  static const String _supportPhoneNumber = "5548996381626"; // Código País + DDD + Número

  /// Abre o WhatsApp com uma mensagem pré-formatada.
  /// Retorna uma string de erro se falhar, ou null se sucesso.
  Future<String?> sendBugReport({
    required String reportType,
    required String title,
    required String description,
  }) async {
    try {
      // 1. Limpa o número (remove caracteres não numéricos)
      final String cleanNumber = _supportPhoneNumber.replaceAll(RegExp(r'[^\d]'), '');
      
      // 2. Formata a mensagem
      final String message = 
          "*REPORT DE BUG/ERRO - FJF APP*\n\n"
          "*Tipo:* $reportType\n"
          "*Título:* $title\n"
          "*Descrição:* $description\n\n"
          "Enviado pelo App (v2.0.0).";

      // 3. Codifica para URL
      final String encodedMessage = Uri.encodeComponent(message);
      
      // 4. Cria URIs (Universal e Fallback)
      final Uri whatsappUrl = Uri.parse("https://api.whatsapp.com/send?phone=$cleanNumber&text=$encodedMessage");
      final Uri whatsappAppUrl = Uri.parse("whatsapp://send?phone=$cleanNumber&text=$encodedMessage");

      // 5. Tenta abrir
      // Primeiro tenta o esquema nativo (whatsapp://), se falhar tenta o link web (https://)
      if (await canLaunchUrl(whatsappAppUrl)) {
        await launchUrl(whatsappAppUrl, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(whatsappUrl)) {
        await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
      } else {
        // Fallback final: tenta lançar sem checar (necessário em alguns Androids 11+)
        await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
      }
      
      return null; // Sucesso
    } catch (e) {
      debugPrint("Erro ao abrir WhatsApp: $e");
      return "Não foi possível abrir o WhatsApp: $e";
    }
  }
}