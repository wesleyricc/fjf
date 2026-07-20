import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../models/fantasy_models.dart';
import '../../models/bolao_models.dart';

class ChatAreaWidget extends StatelessWidget {
  final TextEditingController chatController;
  final FocusNode chatFocusNode;
  final ScrollController chatScrollController;
  final Map<dynamic, dynamic>? replyingToMessage;
  final bool isChatOpen;
  final bool isChatEndingSoon;
  final Stream<DatabaseEvent> chatStream;
  final BolaoMatch match;
  final BolaoUser currentUser;
  
  final VoidCallback onCancelReply;
  final void Function(String) onSendMessage;
  final void Function(Map<dynamic, dynamic>) onReply;

  const ChatAreaWidget({
    super.key,
    required this.chatController,
    required this.chatFocusNode,
    required this.chatScrollController,
    this.replyingToMessage,
    required this.isChatOpen,
    required this.isChatEndingSoon,
    required this.chatStream,
    required this.match,
    required this.currentUser,
    required this.onCancelReply,
    required this.onSendMessage,
    required this.onReply,
  });


  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // CABEÇALHO DO CHAT (DIVISOR VISUAL)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          color: Colors.grey.shade300,
          child: const Row(
            children: [
              Icon(Icons.forum, color: Color(0xFF1B5E20), size: 16),
              SizedBox(width: 8),
              Text("RESENHA DA PARTIDA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1B5E20))),
            ],
          ),
        ),
        
        // MENSAGENS E ALERTAS DE STATUS (ALONGADO E ROLÁVEL)
        Container(
          height: 220, 
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade300))
          ),
          child: Column(
            children: [
              if (!isChatOpen)
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(8), color: Colors.orange.shade100,
                  child: const Text("O chat abre 15 min antes do jogo e fica liberado por 3 horas!", textAlign: TextAlign.center, style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 11)),
                )
              else if (isChatEndingSoon)
                Container(
                  width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12), color: Colors.red.shade100,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.timer_outlined, color: Colors.red.shade800, size: 16),
                      const SizedBox(width: 8),
                      Text("ATENÇÃO: Chat encerrará em menos de 5 min!", style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold, fontSize: 11)),
                    ],
                  ),
                ),
                
              Expanded(
                child: StreamBuilder<DatabaseEvent>(
                  stream: chatStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator(color: Color(0xFF1B5E20), strokeWidth: 2));
                    }
                    
                    List<Map<dynamic, dynamic>> messages = [];
                    if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                      final Map<dynamic, dynamic> map = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
                      messages = map.values.map((e) => e as Map<dynamic, dynamic>).toList();
                      messages.sort((a, b) => (b['timestamp'] ?? 0).compareTo(a['timestamp'] ?? 0));
                    }

                    if (messages.isEmpty) {
                      String emptyMsg = "Nenhuma mensagem. Puxe assunto!";
                      if (!isChatOpen) {
                        final now = DateTime.now();
                        final chatEnd = match.date.add(const Duration(minutes: 180));
                        
                        if (now.isAfter(chatEnd)) emptyMsg = "Chat encerrado.";
                        else if (now.isBefore(match.date.subtract(const Duration(minutes: 15)))) emptyMsg = "Chat não abriu.";
                        else emptyMsg = "Chat indisponível.";
                      }
                      return Center(child: Text(emptyMsg, style: const TextStyle(color: Colors.grey, fontSize: 12)));
                    }

                    return ListView.builder(
                      controller: chatScrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(12),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final bool isMe = msg['userId'] == currentUser.userId;
                        final int timestamp = msg['timestamp'] ?? 0;
                        final String timeStr = timestamp > 0 ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(timestamp)) : '';

                        return Align(
                          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: GestureDetector(
                            onLongPress: () {
                              onReply(msg);
                              chatFocusNode.requestFocus(); 
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
                                      child: msg['photoUrl'] == null || msg['photoUrl'].toString().isEmpty ? const Icon(Icons.person, size: 12) : null,
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
                                          
                                          if (!isMe)
                                            Padding(
                                              padding: const EdgeInsets.only(bottom: 2),
                                              child: Text(msg['userName'] ?? 'Desconhecido', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.indigo.shade800)),
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
                                      child: msg['photoUrl'] == null || msg['photoUrl'].toString().isEmpty ? const Icon(Icons.person, size: 12) : null,
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
            ],
          ),
        ),

        // BARRA DE DIGITAÇÃO E RESPOSTA
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, -2))]
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (replyingToMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border(left: BorderSide(color: const Color(0xFF1B5E20), width: 4))
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Respondendo a ${replyingToMessage!['userName']}", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: const Color(0xFF1B5E20))),
                            Text(replyingToMessage!['text'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                          ],
                        ),
                      ),
                      IconButton(icon: const Icon(Icons.close, size: 16), onPressed: onCancelReply, padding: EdgeInsets.zero, constraints: const BoxConstraints())
                    ],
                  ),
                ),

              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: chatController,
                      focusNode: chatFocusNode,
                      enabled: isChatOpen,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: isChatOpen ? 'Resenhar...' : 'Chat fechado',
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
                      onSubmitted: (_) => onSendMessage(chatController.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () {
                        if (isChatOpen && chatController.text.trim().isNotEmpty) {
                          onSendMessage(chatController.text);
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
