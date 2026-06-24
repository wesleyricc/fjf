import 'package:cloud_firestore/cloud_firestore.dart';

class PhotoProduct {
  final String id;
  final String previewUrl; 
  final String highResUrl; 
  final double price;
  final String eventName;
  final DateTime takenAt;

  PhotoProduct({
    required this.id,
    required this.previewUrl,
    required this.highResUrl,
    required this.price,
    required this.eventName,
    required this.takenAt,
  });

  factory PhotoProduct.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    String rawOriginal = data['original_url'] ?? data['url'] ?? '';
    // 🚨 SEGURANÇA: Lê a prévia destruída. Se for uma foto antiga sem prévia, usa a original.
    String rawPreview = data['preview_url'] ?? rawOriginal;

    // Tratamento para Cloudinary (evitar erro de encoding sem extensão)
    if (rawOriginal.isNotEmpty && rawOriginal.contains('cloudinary.com')) {
      if (!rawOriginal.endsWith('.jpg') && !rawOriginal.endsWith('.png') && !rawOriginal.endsWith('.webp')) {
        rawOriginal = '$rawOriginal.jpg';
      }
    }
    if (rawPreview.isNotEmpty && rawPreview.contains('cloudinary.com')) {
      if (!rawPreview.endsWith('.jpg') && !rawPreview.endsWith('.png') && !rawPreview.endsWith('.webp')) {
        rawPreview = '$rawPreview.jpg';
      }
    }

    return PhotoProduct(
      id: doc.id,
      previewUrl: rawPreview, // 🔒 Agora a loja vai carregar a imagem já com marca e baixa resolução
      highResUrl: rawOriginal, // 🔓 Link original liberado apenas após a compra e enviado no email
      price: (data['price'] ?? 0.0).toDouble(),
      eventName: data['event_name'] ?? 'Evento Geral',
      takenAt: (data['taken_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhotoProduct && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}