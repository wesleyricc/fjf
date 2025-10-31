// lib/screens/admin_media_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/firestore_service.dart';
import 'edit_media_screen.dart';

class AdminMediaScreen extends StatefulWidget {
  const AdminMediaScreen({super.key});

  @override
  State<AdminMediaScreen> createState() => _AdminMediaScreenState();
}

class _AdminMediaScreenState extends State<AdminMediaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirestoreService _firestoreService = FirestoreService();

  // Diálogo de confirmação para exclusão
  Future<void> _showDeleteMediaDialog(DocumentSnapshot doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Mídia?'),
        content: const Text('Tem certeza que deseja excluir este item de mídia? A imagem no Storage também será deletada.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Excluir', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final result = await _firestoreService.deleteMediaItem(doc);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gerenciar Mídias'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('media_feed')
            .orderBy('order', descending: true) // Ordena pela ordem
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Nenhuma mídia cadastrada.'));
          }

          final mediaItems = snapshot.data!.docs;

          return ListView.builder(
            itemCount: mediaItems.length,
            itemBuilder: (context, index) {
              final doc = mediaItems[index];
              final data = doc.data() as Map<String, dynamic>;
              final String imageUrl = data['imageUrl'] ?? '';

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: ListTile(
                  leading: SizedBox(
                    width: 60,
                    height: 50,
                    child: imageUrl.isEmpty
                      ? const Icon(Icons.newspaper, color: Colors.grey)
                      : CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          errorWidget: (c,u,e) => const Icon(Icons.broken_image, color: Colors.red),
                        ),
                  ),
                  title: Text(data['title'] ?? 'Sem Título'),
                  subtitle: Text('Ordem: ${data['order']}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.edit, color: Theme.of(context).primaryColor),
                        tooltip: 'Editar',
                        onPressed: () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (ctx) => EditMediaScreen(mediaDoc: doc),
                          ));
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        tooltip: 'Excluir',
                        onPressed: () => _showDeleteMediaDialog(doc),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Navega para a tela de edição em modo 'Criar' (doc = null)
          Navigator.of(context).push(MaterialPageRoute(
            builder: (ctx) => const EditMediaScreen(mediaDoc: null),
          ));
        },
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        tooltip: 'Adicionar Nova Mídia',
        child: const Icon(Icons.add),
      ),
    );
  }
}