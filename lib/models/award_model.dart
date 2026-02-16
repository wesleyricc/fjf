import 'package:cloud_firestore/cloud_firestore.dart';

class Award {
  final String id;
  final String title;       // Ex: "Melhor Jogador", "Melhor Goleiro"
  final String winnerName;  // Ex: "João Silva"
  final String? subtitle;   // Ex: "Time A" ou "Técnico"
  final String? imageUrl;   // Foto do vencedor ou escudo
  final String category;    // 'player', 'team', 'staff'
  final int order;          // Para ordenação na tela

  Award({
    required this.id,
    required this.title,
    required this.winnerName,
    this.subtitle,
    this.imageUrl,
    required this.category,
    required this.order,
  });

  factory Award.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Award(
      id: doc.id,
      title: data['title'] ?? 'Prêmio',
      winnerName: data['winner_name'] ?? 'Vencedor',
      subtitle: data['subtitle'],
      imageUrl: data['image_url'],
      category: data['category'] ?? 'player',
      order: data['order'] ?? 99,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'winner_name': winnerName,
      'subtitle': subtitle,
      'image_url': imageUrl,
      'category': category,
      'order': order,
    };
  }
}