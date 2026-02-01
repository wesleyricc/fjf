import 'package:cloud_firestore/cloud_firestore.dart';

class PhotoProduct {
  final String id;
  final String previewUrl; // Usaremos a original_url tratada
  final String highResUrl; // A mesma, para download
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

    // 1. TENTA PEGAR A URL CORRETA BASEADA NA SUA IMAGEM DO BANCO
    String rawUrl = data['original_url'] ?? data['url'] ?? '';

    // 2. CORREÇÃO PARA CLOUDINARY (Evita EncodingError)
    // Se a URL vem do Cloudinary sem extensão, o Flutter Web às vezes falha ao detectar o tipo.
    // Forçamos .jpg se não houver extensão.
    if (rawUrl.isNotEmpty && rawUrl.contains('cloudinary.com')) {
      if (!rawUrl.endsWith('.jpg') && !rawUrl.endsWith('.png') && !rawUrl.endsWith('.webp')) {
        rawUrl = '$rawUrl.jpg';
      }
    }

    return PhotoProduct(
      id: doc.id,
      // Como seu banco só tem 'original_url', usamos ela para o preview também.
      previewUrl: rawUrl, 
      highResUrl: rawUrl, 
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