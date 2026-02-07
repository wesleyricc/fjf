import 'package:flutter/material.dart';
import '../widgets/sponsor_banner_rotator.dart';

class AboutBoardScreen extends StatelessWidget {
  const AboutBoardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diretoria Atual'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 16.0),
            child: Text(
              "Conheça quem faz a FJF acontecer:",
              style: TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),

          // Presidente (Destaque)
          _buildBoardMemberCard(
            context,
            name: "Vitor Hugo Sartor Alano",
            role: "Presidente",
            isHighlight: true,
          ),
          
          // Vice
          _buildBoardMemberCard(
            context,
            name: "João Pedro Garcia",
            role: "Vice-Presidente",
            isHighlight: true,
          ),

          const Divider(height: 30),

          // Demais Membros
          _buildBoardMemberCard(context, name: "Mikael Tezza De Costa", role: "Tesoureiro"),
          _buildBoardMemberCard(context, name: "Ivan Gregório Graciano", role: "Secretário"),
          _buildBoardMemberCard(context, name: "Kauã Teixeira", role: "Diretor de Esportes"),
          _buildBoardMemberCard(context, name: "Wesley Ricardo de Souza", role: "Diretor Social"),
        ],
      ),
      bottomNavigationBar: const SponsorBannerRotator(),
    );
  }

  Widget _buildBoardMemberCard(BuildContext context, {
    required String name, 
    required String role, 
    bool isHighlight = false
  }) {
    return Card(
      elevation: isHighlight ? 4 : 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isHighlight 
            ? BorderSide(color: Theme.of(context).primaryColor.withOpacity(0.5), width: 1.5) 
            : BorderSide.none,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 25,
          backgroundColor: isHighlight ? Theme.of(context).primaryColor : Colors.grey[200],
          child: Icon(
            Icons.person, 
            color: isHighlight ? Colors.white : Colors.grey[600],
            size: 30,
          ),
        ),
        title: Text(
          name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isHighlight ? 18 : 16,
            color: Colors.black87,
          ),
        ),
        subtitle: Text(
          role.toUpperCase(),
          style: TextStyle(
            color: isHighlight ? Theme.of(context).primaryColor : Colors.grey[700],
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}