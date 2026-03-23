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
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _sending = false;
  bool _markingRead = false;

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
    } finally {
      if (mounted) _markingRead = false;
    }
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
            0,
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

    // Always convert to local time of the device viewing the message
    // This is the standard behavior for chat apps
    final date = timestamp.toDate().toLocal();
    final now = DateTime.now();

    // Check if today
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }

    // Check if this year
    if (date.year == now.year) {
      final month = _monthName(date.month);
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');
      return '$month ${date.day}, $hour:$minute';
    }

    // Older
    final month = _monthName(date.month);
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$month ${date.day} ${date.year}, $hour:$minute';
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

  Widget _buildMessageBubble(
    DocumentSnapshot doc,
    bool isMine,
    ColorScheme colorScheme,
  ) {
    final data = doc.data() as Map<String, dynamic>;
    final message = (data['message'] as String?) ?? '';
    final isEdited = data['isEdited'] == true;
    final timestamp = _effectiveTimestamp(data);
    final timeStr = _formatTime(timestamp);

    return GestureDetector(
      onLongPress: () => _showMessageOptions(doc, isMine, message),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          margin: const EdgeInsets.only(bottom: 4, top: 4),
          decoration: BoxDecoration(
            color: isMine
                ? colorScheme.primary
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: isMine
                  ? const Radius.circular(18)
                  : const Radius.circular(4),
              bottomRight: isMine
                  ? const Radius.circular(4)
                  : const Radius.circular(18),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                child: Text(
                  message,
                  style: TextStyle(
                    color: isMine
                        ? colorScheme.onPrimary
                        : colorScheme.onSurface,
                    fontSize: 16,
                  ),
                ),
              ),
              Positioned(
                bottom: 6,
                right: 10,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isEdited)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.edit,
                          size: 10,
                          color: isMine
                              ? colorScheme.onPrimary.withValues(alpha: 0.7)
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 10,
                        color: isMine
                            ? colorScheme.onPrimary.withValues(alpha: 0.7)
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
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
                  _buildAvatar(profile, widget.recipientName),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.recipientName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.channel == 'mail' &&
                            (widget.threadSubject ?? '').trim().isNotEmpty)
                          Text(
                            widget.threadSubject!.trim(),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
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
          : Column(
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

                            // Check channel
                            final channel =
                                ((data['channel'] as String?)
                                        ?.trim()
                                        .isNotEmpty ==
                                    true)
                                ? (data['channel'] as String).trim()
                                : 'mail';
                            if (channel != widget.channel) return false;

                            // Direct match
                            if (threadId != null && threadId.isNotEmpty) {
                              return threadId == widget.threadId;
                            }

                            // Fallback logic
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
                            // Sort descending for reverse ListView
                            final aTime = _effectiveTimestamp(
                              a.data() as Map<String, dynamic>,
                            );
                            final bTime = _effectiveTimestamp(
                              b.data() as Map<String, dynamic>,
                            );
                            if (aTime == null && bTime == null) return 0;
                            if (aTime == null) return -1;
                            if (bTime == null) return 1;
                            return bTime.compareTo(aTime);
                          });

                      unawaited(_markThreadAsRead(user, threadDocs));

                      if (threadDocs.isEmpty) {
                        return Center(
                          child: Text(
                            'No messages here yet.',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        itemCount: threadDocs.length,
                        itemBuilder: (context, index) {
                          final doc = threadDocs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final isMine = data['senderId'] == user.uid;
                          return _buildMessageBubble(doc, isMine, colorScheme);
                        },
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      border: Border(
                        top: BorderSide(color: colorScheme.outlineVariant),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_editingMessageId != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer.withValues(
                                alpha: 0.5,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.edit,
                                  size: 16,
                                  color: colorScheme.onSecondaryContainer,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Editing message',
                                    style: TextStyle(
                                      color: colorScheme.onSecondaryContainer,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.close,
                                    size: 20,
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                  onPressed: _stopEditing,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _messageController,
                                minLines: 1,
                                maxLines: 5,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  hintText: 'Message',
                                  filled: true,
                                  fillColor: colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.5),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              onPressed: _sending ? null : _handleSendOrUpdate,
                              icon: Icon(
                                _editingMessageId != null
                                    ? Icons.check
                                    : Icons.send_rounded,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
