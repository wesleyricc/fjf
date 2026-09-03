import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../services/fantasy_auth_service.dart';

class LiveStreamChatWidget extends StatefulWidget {
  const LiveStreamChatWidget({super.key});

  @override
  State<LiveStreamChatWidget> createState() => _LiveStreamChatWidgetState();
}

class _LiveStreamChatWidgetState extends State<LiveStreamChatWidget> {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  
  Map<dynamic, dynamic>? _replyingToMessage;

  late String _chatNode;
  late Stream<DatabaseEvent> _chatStream;

  @override
  void initState() {
    super.initState();
    // O nó de chat muda todos os dias, gerando um "reset" a cada 24 horas.
    final String dateStr = DateFormat('yyyy_MM_dd').format(DateTime.now());
    _chatNode = 'live_chats/chat_$dateStr';
    
    // Escuta apenas as últimas 100 mensagens para não pesar
    _chatStream = FirebaseDatabase.instance
        .ref(_chatNode)
        .orderByChild('timestamp')
        .limitToLast(100)
        .onValue;
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final text = _chatController.text.trim();
    if (text.isEmpty || text.length > 200) return;

    final payload = {
      'userId': user.uid,
      'userName': user.displayName ?? 'Torcedor',
      'photoUrl': user.photoURL ?? '',
      'text': text,
      'timestamp': ServerValue.timestamp,
    };

    if (_replyingToMessage != null) {
      payload['replyToUserName'] = _replyingToMessage!['userName'];
      payload['replyToText'] = _replyingToMessage!['text'];
    }

    FirebaseDatabase.instance.ref(_chatNode).push().set(payload);
    
    _chatController.clear();
    setState(() {
      _replyingToMessage = null;
    });
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0.0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final bool isLoggedIn = user != null;

    return Column(
      children: [
        // CABEÇALHO DO CHAT
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          color: Colors.grey.shade300,
          child: const Row(
            children: [
              Icon(Icons.forum, color: Color(0xFF1B5E20), size: 16),
              SizedBox(width: 8),
              Text("CHAT AO VIVO", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1B5E20))),
            ],
          ),
        ),
        
        // MENSAGENS
        Expanded(
          child: Container(
            color: Colors.white,
            child: StreamBuilder<DatabaseEvent>(
              stream: _chatStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(color: Colors.red, strokeWidth: 2));
                }
                
                List<Map<dynamic, dynamic>> messages = [];
                if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                  final Map<dynamic, dynamic> map = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
                  messages = map.values.map((e) => e as Map<dynamic, dynamic>).toList();
                  // Ordena do mais recente para o mais antigo (reverse: true no ListView)
                  messages.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
                }

                if (messages.isEmpty) {
                  return const Center(
                    child: Text("O chat foi reiniciado hoje. Mande a primeira mensagem!", style: TextStyle(color: Colors.grey, fontSize: 12)),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final bool isMe = isLoggedIn && msg['userId'] == user.uid;
                    final int timestamp = msg['timestamp'] ?? 0;
                    final String timeStr = timestamp > 0 ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(timestamp)) : '';

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: GestureDetector(
                        onLongPress: () {
                          setState(() {
                            _replyingToMessage = msg;
                          });
                          _focusNode.requestFocus();
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (!isMe)
                                CircleAvatar(
                                  radius: 10, backgroundColor: Colors.grey[300],
                                  backgroundImage: msg['photoUrl'] != null && msg['photoUrl'].toString().isNotEmpty ? CachedNetworkImageProvider(msg['photoUrl']) : null,
                                  child: msg['photoUrl'] == null || msg['photoUrl'].toString().isEmpty ? const Icon(Icons.person, size: 12, color: Colors.black54) : null,
                                ),
                              if (!isMe) const SizedBox(width: 6),
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isMe ? const Color(0xFF1B5E20) : Colors.grey.shade100,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(12),
                                      topRight: const Radius.circular(12),
                                      bottomLeft: Radius.circular(isMe ? 12 : 0),
                                      bottomRight: Radius.circular(isMe ? 0 : 12),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (msg['replyToText'] != null)
                                        Container(
                                          margin: const EdgeInsets.only(bottom: 4),
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: isMe ? Colors.green.shade900.withOpacity(0.3) : Colors.grey.shade300,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(msg['replyToUserName'] ?? 'Alguém', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: isMe ? Colors.green.shade200 : Colors.indigo.shade700)),
                                              const SizedBox(height: 2),
                                              Text(msg['replyToText'], maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: isMe ? Colors.white70 : Colors.black87, fontStyle: FontStyle.italic)),
                                            ],
                                          ),
                                        ),
                                      
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 2),
                                        child: Text(msg['userName'] ?? 'Torcedor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: isMe ? Colors.green.shade300 : Colors.indigo.shade800)),
                                      ),
                                    Text(msg['text'] ?? '', style: TextStyle(fontSize: 13, color: isMe ? Colors.white : Colors.black87)),
                                    
                                    const SizedBox(height: 2),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Text(timeStr, style: TextStyle(fontSize: 8, color: isMe ? Colors.white70 : Colors.grey.shade600)),
                                    )
                                  ],
                                ),
                              ),
                            ),
                            if (isMe) const SizedBox(width: 6),
                            if (isMe)
                              CircleAvatar(
                                radius: 10, backgroundColor: Colors.grey[300],
                                backgroundImage: msg['photoUrl'] != null && msg['photoUrl'].toString().isNotEmpty ? CachedNetworkImageProvider(msg['photoUrl']) : null,
                                child: msg['photoUrl'] == null || msg['photoUrl'].toString().isEmpty ? const Icon(Icons.person, size: 12, color: Colors.black54) : null,
                              ),
                          ],
                        ),
                      ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),

        // BARRA DE DIGITAÇÃO
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, -2))]
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_replyingToMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: const Border(left: BorderSide(color: Color(0xFF1B5E20), width: 4))
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Respondendo a ${_replyingToMessage!['userName']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Color(0xFF1B5E20))),
                            Text(_replyingToMessage!['text'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16), 
                        onPressed: () {
                          setState(() {
                            _replyingToMessage = null;
                          });
                        }, 
                        padding: EdgeInsets.zero, 
                        constraints: const BoxConstraints()
                      )
                    ],
                  ),
                ),
              Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: isLoggedIn 
                ? TextField(
                    controller: _chatController,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: 4,
                    style: const TextStyle(fontSize: 13, color: Colors.black),
                    decoration: InputDecoration(
                      hintText: 'Mande sua mensagem...',
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      filled: true,
                      fillColor: Colors.grey.shade200,
                      isDense: true,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  )
                : OutlinedButton.icon(
                    icon: const Icon(Icons.login, size: 16),
                    label: const Text('Fazer Login para Participar', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1B5E20),
                      side: const BorderSide(color: Color(0xFF1B5E20)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () async {
                      final authService = Provider.of<FantasyAuthService>(context, listen: false);
                      await authService.signInWithGoogle();
                      setState(() {}); // Força recarregamento da tela para exibir o input
                    },
                  ),
              ),
              if (isLoggedIn) const SizedBox(width: 8),
              if (isLoggedIn)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () {
                      if (_chatController.text.trim().isNotEmpty) {
                        _sendMessage();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Color(0xFF1B5E20),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send, color: Colors.white, size: 16),
                    ),
                  ),
                ),
            ],
          ),
          ],
        ),
        ),
      ],
    );
  }
}
