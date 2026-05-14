import 'package:flutter/material.dart';
import 'package:nclaw/src/rust/api/types.dart';
import 'package:nclaw/services/sync_service.dart';
import 'package:nclaw/services/db_service.dart';

/// ChatScreen — minimal chat UI using FRB Rust-backed types.
class ChatScreen extends StatefulWidget {
  final String topic;
  const ChatScreen({required this.topic});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _syncService = SyncService();
  final _dbService = DbService();
  final _messageController = TextEditingController();
  List<Message> _messages = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    setState(() => _loading = true);
    try {
      final messages = await _dbService.queryByTopic(widget.topic);
      setState(() => _messages = messages);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.isEmpty) return;
    _messageController.clear();
    final msg = Message(
      id: 'msg-${DateTime.now().millisecondsSinceEpoch}',
      content: text,
      topic: widget.topic,
      timestamp: DateTime.now(),
      role: 'user',
    );
    await _dbService.storeMessage(msg);
    await _syncService.push([msg]);
    await _loadMessages();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ɳClaw — ${widget.topic}')),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      return ListTile(
                        title: Text(msg.content),
                        subtitle: Text(msg.role),
                        trailing: Text(msg.timestamp.toString().split('.')[0]),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(hintText: 'Type message...'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () => _sendMessage(_messageController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }
}
