import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';




class ChatScreen extends StatefulWidget {
  final String passengerId;
  final String driverId;
  final String rideId;
  final String passengerName;
  
  const ChatScreen({
    Key? key,
    required this.passengerId,
    required this.driverId,
    required this.rideId,
    required this.passengerName,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = true;
  List<Map<String, dynamic>> _messages = [];
  late final RealtimeChannel _chatChannel;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = supabase.auth.currentUser?.id;
    _setupRealtimeSubscription();
    _loadMessages();
  }

  void _setupRealtimeSubscription() {
    _chatChannel = supabase.channel('messages');
    
    _chatChannel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'ride_id',
        value: widget.rideId,
      ),
      callback: (payload) {
        if (mounted) {
          setState(() {
            _messages.add(payload.newRecord);
          });
          _scrollToBottom();
        }
      },
    );
    
    _chatChannel.subscribe();
  }

  Future<void> _loadMessages() async {
    if (_currentUserId == null) return;
    
    try {
      // Fetch messages where:
      // 1. The ride_id matches the current ride
      // 2. The message is between the current user and the other party
      final messages = await supabase
          .from('messages')
          .select()
          .eq('ride_id', widget.rideId)
          .or('sender_id.eq.${_currentUserId},receiver_id.eq.${_currentUserId}')
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(messages);
          _isLoading = false;
        });
        _scrollToBottom();
        
        // Mark received messages as read
        _markMessagesAsRead();
      }
    } catch (e) {
      debugPrint('❌ Failed to load messages: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load messages')),
        );
      }
    }
  }

  Future<void> _sendMessage(String message) async {
    if (message.trim().isEmpty) return;
    if (_currentUserId == null) return;

    final receiverId = _currentUserId == widget.passengerId 
        ? widget.driverId 
        : widget.passengerId;

    try {
      await supabase.from('messages').insert({
        'ride_id': widget.rideId,
        'sender_id': _currentUserId,
        'receiver_id': receiverId,
        'message': message.trim(),
        'created_at': DateTime.now().toIso8601String(),
        'is_read': false,
      });

      _messageController.clear();
      
      // No need to reload messages as the realtime subscription will handle updates
    } catch (e) {
      debugPrint('❌ Failed to send message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send message')),
        );
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final isCurrentUser = message['sender_id'] == _currentUserId;
    return Container(
      margin: EdgeInsets.only(
        top: 8,
        bottom: 8,
        left: isCurrentUser ? 64 : 16,
        right: isCurrentUser ? 16 : 64,
      ),
      child: Row(
        mainAxisAlignment: isCurrentUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isCurrentUser ? const Color(0xFFE8F5E9) : Colors.grey[100],
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message['message'],
                  style: TextStyle(
                    fontSize: 14,
                    color: isCurrentUser ? const Color(0xFF2E7D32) : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(message['created_at']),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null) return '';
    final time = DateTime.parse(timestamp);
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFCFA72E),
        elevation: 0,
        title: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.grey[300],
                child: const Icon(FontAwesomeIcons.user, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Text(
                widget.passengerName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.close,
              color: Colors.black87,
            ),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return _buildMessageBubble(_messages[index]);
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.all(16),
                      suffixIcon: IconButton(
                        icon: const Icon(
                          FontAwesomeIcons.paperPlane,
                          color: Color(0xFFCFA72E),
                        ),
                        onPressed: () {
                          _sendMessage(_messageController.text);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _markMessagesAsRead() async {
    if (_currentUserId == null) return;
    
    try {
      // Get unread messages for the current user in this chat
      final unreadMessages = _messages.where((msg) => 
        msg['receiver_id'] == _currentUserId && 
        msg['is_read'] == false
      ).toList();

      if (unreadMessages.isNotEmpty) {
        // Update all unread messages to mark them as read
        final messageIds = unreadMessages.map((m) => m['id']).toList();
        await supabase
            .from('messages')
            .update({'is_read': true})
            .inFilter('id', messageIds);
      }
    } catch (e) {
      debugPrint('❌ Failed to mark messages as read: $e');
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _chatChannel.unsubscribe();
    super.dispose();
  }
}
