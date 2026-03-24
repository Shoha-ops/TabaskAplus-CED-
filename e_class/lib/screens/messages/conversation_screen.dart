import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:e_class/services/database_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:e_class/widgets/user_avatar.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.threadId,
    required this.recipientId,
    required this.recipientName,
    this.threadSubject,
    this.channel = 'mail',
  });

  final String threadId;
  final String recipientId;
  final String recipientName;
  final String? threadSubject;
  final String channel;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  static const Color _telegramBlue = Color(0xFF5AA9E6);
  static const Color _telegramBlueDark = Color(0xFF3B8EDB);
  static const Color _telegramCanvas = Color(0xFFDDEAF5);
  static const Color _telegramIncoming = Color(0xFFFFFFFF);
  static const Color _telegramMuted = Color(0xFF70859A);

  bool _isDarkMode(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  Color _chatCanvasColor(BuildContext context) =>
      _isDarkMode(context) ? const Color(0xFF0E1621) : _telegramCanvas;

  Color _chatHeaderColor(BuildContext context) =>
      _isDarkMode(context) ? const Color(0xFF1F6AA5) : _telegramBlue;

  Color _chatAccentColor(BuildContext context) =>
      _isDarkMode(context) ? const Color(0xFF6AB3F3) : _telegramBlueDark;

  Color _chatOutgoingBubbleColor(BuildContext context) =>
      _isDarkMode(context) ? const Color(0xFF2B5278) : _telegramBlue;

  Color _chatIncomingBubbleColor(BuildContext context) =>
      _isDarkMode(context) ? const Color(0xFF182533) : _telegramIncoming;

  Color _chatMutedColor(BuildContext context) =>
      _isDarkMode(context) ? const Color(0xFF8C9FB3) : _telegramMuted;

  Color _chatPrimaryTextColor(BuildContext context) =>
      _isDarkMode(context) ? const Color(0xFFF5F7FA) : const Color(0xFF203040);

  Color _chatComposerFillColor(BuildContext context) =>
      _isDarkMode(context) ? const Color(0xFF17212B) : Colors.white;

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _sending = false;
  bool _markingRead = false;
  bool _initialScrollDone = false;
  int _lastMessageCount = 0;

  // Editing state
  String? _editingMessageId;
  Timestamp? _editingCreatedAtClient;

  String _fallbackThreadId(String firstUid, String secondUid) {
    final ids = [firstUid, secondUid]..sort();
    return '${ids[0]}__${ids[1]}';
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _markThreadAsRead(
    User user,
    List<QueryDocumentSnapshot> threadDocs,
  ) async {
    if (_markingRead) return;

    final unreadDocs = threadDocs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return (data['type'] == 'received') && (data['isUnread'] == true);
    }).toList();
    if (unreadDocs.isEmpty) return;

    _markingRead = true;
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in unreadDocs) {
        batch.update(doc.reference, {'isUnread': false});
      }
      await batch.commit();

      for (final doc in unreadDocs) {
        final data = doc.data() as Map<String, dynamic>;
        final senderId = (data['senderId'] as String?)?.trim() ?? '';
        final createdAtClient = data['createdAtClient'] as Timestamp?;
        if (senderId.isEmpty || createdAtClient == null) continue;

        try {
          final senderCopySnapshot = await FirebaseFirestore.instance
              .collection('users')
              .doc(senderId)
              .collection('emails')
              .where('recipientId', isEqualTo: user.uid)
              .where('createdAtClient', isEqualTo: createdAtClient)
              .limit(1)
              .get();

          for (final senderDoc in senderCopySnapshot.docs) {
            await senderDoc.reference.update({'isReadByRecipient': true});
          }
        } catch (_) {
          // Keep local read state even if sender copy sync fails.
        }
      }
    } finally {
      if (mounted) _markingRead = false;
    }
  }

  bool _isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isSameSender(DocumentSnapshot? a, DocumentSnapshot? b) {
    if (a == null || b == null) return false;
    final aData = a.data() as Map<String, dynamic>;
    final bData = b.data() as Map<String, dynamic>;
    final aSender = (aData['senderId'] as String?)?.trim() ?? '';
    final bSender = (bData['senderId'] as String?)?.trim() ?? '';
    if (aSender.isEmpty || bSender.isEmpty || aSender != bSender) return false;
    final aTime = _effectiveTimestamp(aData)?.toDate();
    final bTime = _effectiveTimestamp(bData)?.toDate();
    return _isSameDay(aTime, bTime);
  }

  String _formatDayDivider(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate().toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${date.day} ${_monthName(date.month)}';
  }

  void _scheduleScrollToBottom(int messageCount) {
    final shouldAnimate = _initialScrollDone && messageCount > _lastMessageCount;
    _lastMessageCount = messageCount;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (!_initialScrollDone) {
        _scrollController.jumpTo(target);
        _initialScrollDone = true;
        return;
      }
      if (shouldAnimate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSendOrUpdate() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;

    final user = Provider.of<User?>(context, listen: false);
    if (user == null) return;

    setState(() => _sending = true);

    try {
      if (_editingMessageId != null) {
        // Update existing message
        await DatabaseService(user: user).updateEmailMessage(
          messageId: _editingMessageId!,
          newText: text,
          recipientId: widget.recipientId,
          createdAtClient: _editingCreatedAtClient!,
        );
        _stopEditing();
      } else {
        // Send new message
        final subject = widget.channel == 'chat'
            ? ''
            : (widget.threadSubject ?? '').trim().isNotEmpty
            ? widget.threadSubject!.trim()
            : 'Conversation';

        await DatabaseService(user: user).sendEmail(
          recipientUid: widget.recipientId,
          subject: subject,
          message: text,
          channel: widget.channel,
        );
        _messageController.clear();
        // Scroll to bottom after sending
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Operation failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  void _startEditing(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    setState(() {
      _editingMessageId = doc.id;
      _editingCreatedAtClient = data['createdAtClient'] as Timestamp?;
      _messageController.text = (data['message'] as String?) ?? '';
    });
  }

  void _stopEditing() {
    setState(() {
      _editingMessageId = null;
      _editingCreatedAtClient = null;
      _messageController.clear();
    });
    FocusScope.of(context).unfocus();
  }

  String _formatTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final date = timestamp.toDate().toLocal();
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _monthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  Widget _buildAvatar(Map<String, dynamic>? profile, String fallbackName) {
    return UserAvatar(
      avatarId: (profile?['avatarId'] as String?)?.trim(),
      profilePicBase64: (profile?['profilePicBase64'] as String?)?.trim(),
      profilePicUrl: (profile?['profilePicUrl'] as String?)?.trim(),
      displayName: fallbackName,
      radius: 20,
    );
  }

  Timestamp? _effectiveTimestamp(Map<String, dynamic> data) {
    return (data['createdAtClient'] as Timestamp?) ??
        (data['createdAt'] as Timestamp?);
  }

  String _headerStatusLabel() {
    if (widget.channel == 'chat') return 'Personal chat';
    final subject = (widget.threadSubject ?? '').trim();
    if (subject.isNotEmpty) return subject;
    return 'Course mail';
  }

  Widget _buildHeaderAvatar(
    Map<String, dynamic>? profile,
    String displayName,
  ) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: _buildAvatar(profile, displayName),
    );
  }

  Widget _buildMessageBubble(
    DocumentSnapshot doc,
    bool isMine,
    bool joinsPrevious,
    bool joinsNext,
  ) {
    final outgoingBubble = _chatOutgoingBubbleColor(context);
    final incomingBubble = _chatIncomingBubbleColor(context);
    final muted = _chatMutedColor(context);
    final primaryText = _chatPrimaryTextColor(context);
    final data = doc.data() as Map<String, dynamic>;
    final message = (data['message'] as String?) ?? '';
    final isEdited = data['isEdited'] == true;
    final timestamp = _effectiveTimestamp(data);
    final timeStr = _formatTime(timestamp);
    final isReadByRecipient = data['isReadByRecipient'] == true;
    final radius = BorderRadius.only(
      topLeft: Radius.circular(isMine ? 18 : (joinsPrevious ? 8 : 18)),
      topRight: Radius.circular(isMine ? (joinsPrevious ? 8 : 18) : 18),
      bottomLeft: Radius.circular(isMine ? 18 : (joinsNext ? 8 : 18)),
      bottomRight: Radius.circular(isMine ? (joinsNext ? 8 : 18) : 18),
    );

    return GestureDetector(
      onLongPress: () => _showMessageOptions(doc, isMine, message),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          margin: EdgeInsets.only(
            bottom: joinsNext ? 2 : 8,
            top: joinsPrevious ? 2 : 8,
          ),
          decoration: BoxDecoration(
            color: isMine ? outgoingBubble : incomingBubble,
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    color: isMine ? Colors.white : primaryText,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    if (isEdited) ...[
                      Icon(
                        Icons.edit,
                        size: 10,
                        color: isMine
                            ? Colors.white.withValues(alpha: 0.72)
                            : muted,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        timeStr,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: isMine
                              ? Colors.white.withValues(alpha: 0.72)
                              : muted,
                        ),
                      ),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 4),
                      Icon(
                        isReadByRecipient
                            ? Icons.done_all_rounded
                            : Icons.done_rounded,
                        size: 12,
                        color: isReadByRecipient
                            ? const Color(0xFF8FE3FF)
                            : Colors.white.withValues(alpha: 0.72),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    final accent = _chatAccentColor(context);
    final composerFill = _chatComposerFillColor(context);
    final muted = _chatMutedColor(context);

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_editingMessageId != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: composerFill,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: _isDarkMode(context) ? 0.18 : 0.06,
                      ),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.edit_rounded, color: accent, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Editing message',
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Your changes will update the sent message.',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: muted),
                      onPressed: _stopEditing,
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: composerFill,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: _isDarkMode(context) ? 0.16 : 0.04,
                          ),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          onPressed: null,
                          icon: Icon(
                            Icons.attach_file_rounded,
                            color: muted,
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            minLines: 1,
                            maxLines: 5,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: widget.channel == 'chat'
                                  ? 'Message'
                                  : 'Reply',
                              hintStyle: TextStyle(color: muted),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 2,
                                vertical: 14,
                              ),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: null,
                          icon: Icon(
                            Icons.mic_none_rounded,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.28),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: IconButton(
                    onPressed: _sending ? null : _handleSendOrUpdate,
                    icon: Icon(
                      _editingMessageId != null
                          ? Icons.check_rounded
                          : Icons.send_rounded,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showMessageOptions(DocumentSnapshot doc, bool isMine, String text) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: text));
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Message copied')));
              },
            ),
            if (isMine)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(context);
                  _startEditing(doc);
                },
              ),
            if (isMine)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.deepOrange),
                title: const Text(
                  'Unsend',
                  style: TextStyle(color: Colors.deepOrange),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final user = Provider.of<User?>(context, listen: false);
                  if (user == null) return;

                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Unsend Message?'),
                      content: const Text(
                        'This will remove the message for both you and the recipient.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          child: const Text('Unsend'),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    final data = doc.data() as Map<String, dynamic>;
                    await DatabaseService(user: user).deleteEmailMessage(
                      messageId: doc.id,
                      recipientId: widget.recipientId,
                      createdAtClient: data['createdAtClient'] as Timestamp?,
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<User?>(context);
    final canvas = _chatCanvasColor(context);
    final header = _chatHeaderColor(context);
    final muted = _chatMutedColor(context);

    return Scaffold(
      backgroundColor: canvas,
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: header,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: StreamBuilder<DocumentSnapshot>(
          stream: widget.recipientId.isNotEmpty
              ? FirebaseFirestore.instance
                    .collection('users')
                    .doc(widget.recipientId)
                    .snapshots()
              : const Stream.empty(),
          builder: (context, snapshot) {
            final profile = snapshot.data?.data() as Map<String, dynamic>?;
            return GestureDetector(
              onTap: () => UserAvatar.showViewer(
                context,
                avatarId: (profile?['avatarId'] as String?)?.trim(),
                profilePicBase64: (profile?['profilePicBase64'] as String?)
                    ?.trim(),
                profilePicUrl: (profile?['profilePicUrl'] as String?)?.trim(),
                displayName: widget.recipientName,
              ),
              child: Row(
                children: [
                  _buildHeaderAvatar(profile, widget.recipientName),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.recipientName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          widget.channel == 'chat'
                              ? 'last seen recently'
                              : _headerStatusLabel(),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      body: user == null
          ? const SizedBox.shrink()
          : Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: _isDarkMode(context)
                            ? const [Color(0xFF0E1621), Color(0xFF101A26)]
                            : const [Color(0xFFDDEAF5), Color(0xFFE9F2FA)],
                      ),
                    ),
                    child: CustomPaint(
                      painter: _ChatBackdropPainter(isDark: _isDarkMode(context)),
                    ),
                  ),
                ),
                Column(
                  children: [
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: DatabaseService(user: user).emailMessages,
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          final threadDocs =
                              snapshot.data!.docs.where((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                final threadId = (data['threadId'] as String?)
                                    ?.trim();
                                final channel =
                                    ((data['channel'] as String?)
                                            ?.trim()
                                            .isNotEmpty ==
                                        true)
                                    ? (data['channel'] as String).trim()
                                    : 'mail';
                                if (channel != widget.channel) return false;
                                if (threadId != null && threadId.isNotEmpty) {
                                  return threadId == widget.threadId;
                                }
                                final senderId =
                                    (data['senderId'] as String?)?.trim() ?? '';
                                final recipientId =
                                    (data['recipientId'] as String?)?.trim() ?? '';
                                if (senderId.isEmpty) return false;
                                final otherUserId = senderId == user.uid
                                    ? recipientId
                                    : senderId;
                                if (otherUserId.isEmpty) return false;
                                return _fallbackThreadId(user.uid, otherUserId) ==
                                    widget.threadId;
                              }).toList()..sort((a, b) {
                                final aTime = _effectiveTimestamp(
                                  a.data() as Map<String, dynamic>,
                                );
                                final bTime = _effectiveTimestamp(
                                  b.data() as Map<String, dynamic>,
                                );
                                if (aTime == null && bTime == null) return 0;
                                if (aTime == null) return 1;
                                if (bTime == null) return -1;
                                return aTime.compareTo(bTime);
                              });

                          unawaited(_markThreadAsRead(user, threadDocs));
                          _scheduleScrollToBottom(threadDocs.length);

                          if (threadDocs.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 28),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      widget.channel == 'chat'
                                          ? Icons.chat_bubble_outline_rounded
                                          : Icons.mail_outline_rounded,
                                      color: Colors.white.withValues(alpha: 0.9),
                                      size: 44,
                                    ),
                                    const SizedBox(height: 18),
                                    Text(
                                      widget.channel == 'chat'
                                          ? 'Start the conversation'
                                          : 'No replies yet',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.95),
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      widget.channel == 'chat'
                                          ? 'Send the first message to begin chatting here.'
                                          : 'Write a reply below to continue this thread.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.78),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          return ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
                            itemCount: threadDocs.length,
                            itemBuilder: (context, index) {
                              final doc = threadDocs[index];
                              final data = doc.data() as Map<String, dynamic>;
                              final isMine = data['senderId'] == user.uid;
                              final previous = index > 0 ? threadDocs[index - 1] : null;
                              final next = index < threadDocs.length - 1
                                  ? threadDocs[index + 1]
                                  : null;
                              final timestamp = _effectiveTimestamp(data);
                              final previousTimestamp = previous == null
                                  ? null
                                  : _effectiveTimestamp(
                                      previous.data() as Map<String, dynamic>,
                                    );
                              final showDayDivider =
                                  previousTimestamp == null ||
                                  !_isSameDay(
                                    previousTimestamp.toDate(),
                                    timestamp?.toDate(),
                                  );

                              return Column(
                                children: [
                                  if (showDayDivider)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _isDarkMode(context)
                                              ? Colors.black.withValues(alpha: 0.28)
                                              : const Color(0xFFE7F0F8),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          _formatDayDivider(timestamp),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: muted,
                                          ),
                                        ),
                                      ),
                                    ),
                                  _buildMessageBubble(
                                    doc,
                                    isMine,
                                    _isSameSender(previous, doc),
                                    _isSameSender(doc, next),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ),
                    _buildComposer(),
                  ],
                ),
              ],
            ),
    );
  }
}

class _ChatBackdropPainter extends CustomPainter {
  const _ChatBackdropPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = (isDark ? Colors.white : const Color(0xFF9EBAD3)).withValues(
        alpha: isDark ? 0.03 : 0.10,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final fillPaint = Paint()
      ..color = (isDark ? Colors.white : const Color(0xFFC8DCEC)).withValues(
        alpha: isDark ? 0.02 : 0.08,
      )
      ..style = PaintingStyle.fill;

    final paths = <Path>[
      Path()
        ..moveTo(size.width * 0.08, size.height * 0.16)
        ..quadraticBezierTo(
          size.width * 0.18,
          size.height * 0.08,
          size.width * 0.30,
          size.height * 0.17,
        ),
      Path()
        ..moveTo(size.width * 0.62, size.height * 0.12)
        ..quadraticBezierTo(
          size.width * 0.73,
          size.height * 0.03,
          size.width * 0.86,
          size.height * 0.14,
        ),
      Path()
        ..moveTo(size.width * 0.12, size.height * 0.56)
        ..quadraticBezierTo(
          size.width * 0.20,
          size.height * 0.45,
          size.width * 0.32,
          size.height * 0.54,
        ),
      Path()
        ..moveTo(size.width * 0.68, size.height * 0.66)
        ..quadraticBezierTo(
          size.width * 0.79,
          size.height * 0.56,
          size.width * 0.90,
          size.height * 0.65,
        ),
    ];

    for (final path in paths) {
      canvas.drawPath(path, strokePaint);
    }

    final circles = <Offset>[
      Offset(size.width * 0.22, size.height * 0.28),
      Offset(size.width * 0.82, size.height * 0.34),
      Offset(size.width * 0.18, size.height * 0.78),
      Offset(size.width * 0.74, size.height * 0.84),
    ];

    for (final center in circles) {
      canvas.drawCircle(center, 14, fillPaint);
      canvas.drawCircle(center, 22, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChatBackdropPainter oldDelegate) {
    return oldDelegate.isDark != isDark;
  }
}
