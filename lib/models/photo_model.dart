import 'package:cloud_firestore/cloud_firestore.dart';

class PhotoModel {
  final String id;
  final String thumbnailUrl; 
  final String highResUrl;
  final double price;
  final String eventName;
  final DateTime createdAt;

  PhotoModel({
    required this.id,
    required this.thumbnailUrl,
    required this.highResUrl,
    required this.price,
    required this.eventName,
    required this.createdAt,
  });

  factory PhotoModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // CORREÇÃO: Pega original_url e trata Cloudinary
    String rawUrl = data['original_url'] ?? data['url'] ?? '';
    
    if (rawUrl.isNotEmpty && rawUrl.contains('cloudinary.com')) {
      if (!rawUrl.endsWith('.jpg') && !rawUrl.endsWith('.png')) {
        rawUrl = '$rawUrl.jpg';
      }
    }

    return PhotoModel(
      id: doc.id,
      thumbnailUrl: rawUrl, // Usamos a mesma para thumb se não houver campo específico
      highResUrl: rawUrl,
      price: (data['price'] ?? 0.0).toDouble(),
      eventName: data['event_name'] ?? 'Evento FJF',
      createdAt: (data['taken_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}