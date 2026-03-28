import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:e_class/services/database_service.dart';
import 'package:e_class/widgets/user_avatar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

enum _PendingMessageStatus { sending, sent, failed }

class _ReplyPreviewData {
  const _ReplyPreviewData({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.messageType,
  });

  final String messageId;
  final String senderId;
  final String senderName;
  final String text;
  final String messageType;

  factory _ReplyPreviewData.fromMap(Map<String, dynamic> data) {
    return _ReplyPreviewData(
      messageId: (data['replyToMessageId'] as String?)?.trim() ?? '',
      senderId: (data['replyToSenderId'] as String?)?.trim() ?? '',
      senderName: (data['replyToSenderName'] as String?)?.trim() ?? '',
      text: (data['replyToText'] as String?)?.trim() ?? '',
      messageType: (data['replyToMessageType'] as String?)?.trim().isNotEmpty == true
          ? (data['replyToMessageType'] as String).trim()
          : 'text',
    );
  }

  bool get isValid => messageId.isNotEmpty && text.isNotEmpty;

  Map<String, dynamic> toMap() => {
        'messageId': messageId,
        'senderId': senderId,
        'senderName': senderName,
        'text': text,
        'messageType': messageType,
      };
}

class _PendingMessage {
  const _PendingMessage({
    required this.clientMessageId,
    required this.senderId,
    required this.senderName,
    required this.message,
    required this.createdAtClient,
    required this.status,
    this.replyPreview,
  });

  final String clientMessageId;
  final String senderId;
  final String senderName;
  final String message;
  final Timestamp createdAtClient;
  final _PendingMessageStatus status;
  final _ReplyPreviewData? replyPreview;

  _PendingMessage copyWith({
    _PendingMessageStatus? status,
  }) {
    return _PendingMessage(
      clientMessageId: clientMessageId,
      senderId: senderId,
      senderName: senderName,
      message: message,
      createdAtClient: createdAtClient,
      status: status ?? this.status,
      replyPreview: replyPreview,
    );
  }
}

class _ChatMessageItem {
  const _ChatMessageItem({
    required this.key,
    required this.senderId,
    required this.senderName,
    required this.message,
    required this.createdAt,
    required this.createdAtClient,
    required this.isMine,
    required this.isEdited,
    required this.isReadByRecipient,
    required this.messageType,
    required this.reactions,
    this.documentId,
    this.clientMessageId,
    this.replyPreview,
    this.pendingStatus,
  });

  final String key;
  final String senderId;
  final String senderName;
  final String message;
  final DateTime createdAt;
  final Timestamp createdAtClient;
  final bool isMine;
  final bool isEdited;
  final bool isReadByRecipient;
  final String messageType;
  final Map<String, List<String>> reactions;
  final String? documentId;
  final String? clientMessageId;
  final _ReplyPreviewData? replyPreview;
  final _PendingMessageStatus? pendingStatus;

  bool get isPending => pendingStatus != null;

  factory _ChatMessageItem.fromDoc(
    QueryDocumentSnapshot doc,
    String currentUserId,
  ) {
    final data = doc.data() as Map<String, dynamic>;
    final replyPreview = _ReplyPreviewData.fromMap(data);
    final rawReactions = data['reactions'];
    final reactions = <String, List<String>>{};
    if (rawReactions is Map) {
      for (final entry in rawReactions.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is List) {
          reactions[key] = value.map((item) => item.toString()).toList();
        }
      }
    }

    final createdAtClient =
        (data['createdAtClient'] as Timestamp?) ??
        (data['createdAt'] as Timestamp?) ??
        Timestamp.now();

    return _ChatMessageItem(
      key: doc.id,
      documentId: doc.id,
      clientMessageId: (data['clientMessageId'] as String?)?.trim(),
      senderId: (data['senderId'] as String?)?.trim() ?? '',
      senderName: (data['senderName'] as String?)?.trim().isNotEmpty == true
          ? (data['senderName'] as String).trim()
          : ((data['otherUserName'] as String?)?.trim() ?? 'Unknown'),
      message: (data['message'] as String?) ?? '',
      createdAt: createdAtClient.toDate().toLocal(),
      createdAtClient: createdAtClient,
      isMine: (data['senderId'] as String?)?.trim() == currentUserId,
      isEdited: data['isEdited'] == true,
      isReadByRecipient: data['isReadByRecipient'] == true,
      messageType: (data['messageType'] as String?)?.trim().isNotEmpty == true
          ? (data['messageType'] as String).trim()
          : 'text',
      reactions: reactions,
      replyPreview: replyPreview.isValid ? replyPreview : null,
      pendingStatus: null,
    );
  }

  factory _ChatMessageItem.fromPending(
    _PendingMessage pending,
    String currentUserId,
  ) {
    return _ChatMessageItem(
      key: pending.clientMessageId,
      clientMessageId: pending.clientMessageId,
      senderId: pending.senderId,
      senderName: pending.senderName,
      message: pending.message,
      createdAt: pending.createdAtClient.toDate().toLocal(),
      createdAtClient: pending.createdAtClient,
      isMine: pending.senderId == currentUserId,
      isEdited: false,
      isReadByRecipient: false,
      messageType: 'text',
      reactions: const <String, List<String>>{},
      replyPreview: pending.replyPreview,
      pendingStatus: pending.status,
    );
  }
}

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
  static const Color _telegramBlue = Color(0xFF5682A3);
  static const Color _telegramBlueDark = Color(0xFF3B70A2);
  static const Color _telegramGreen = Color(0xFFDCF8C6);

  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _sending = false;
  bool _markingRead = false;
  bool _initialScrollDone = false;
  bool _hasComposerText = false;
  bool _isSearching = false;
  int _lastMessageCount = 0;

  String? _editingMessageId;
  Timestamp? _editingCreatedAtClient;
  _ReplyPreviewData? _replyTarget;

  List<_PendingMessage> _pendingMessages = const <_PendingMessage>[];
  String _searchQuery = '';

  bool _isDarkMode(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  Color _chatHeaderColor(BuildContext context) =>
      _isDarkMode(context) ? const Color(0xFF1D2C3A) : _telegramBlue;

  Color _chatCanvasColor(BuildContext context) =>
      _isDarkMode(context) ? const Color(0xFF0E1621) : const Color(0xFFE5DDD5);

  Color _incomingBubbleColor(BuildContext context) =>
      _isDarkMode(context) ? const Color(0xFF182533) : Colors.white;

  Color _outgoingBubbleColor(BuildContext context) =>
      _isDarkMode(context) ? const Color(0xFF2B5278) : _telegramGreen;

  Color _incomingTextColor(BuildContext context) =>
      _isDarkMode(context) ? const Color(0xFFF5F7FA) : const Color(0xFF1F2328);

  Color _outgoingTextColor(BuildContext context) =>
      _isDarkMode(context) ? Colors.white : const Color(0xFF1F2328);

  Color _mutedTextColor(BuildContext context) =>
      _isDarkMode(context) ? const Color(0xFF8A9BA8) : const Color(0xFF6B7C88);

  Color _composerColor(BuildContext context) =>
      _isDarkMode(context) ? const Color(0xFF17212B) : Colors.white;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_handleComposerChanged);
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _messageController.removeListener(_handleComposerChanged);
    _searchController.removeListener(_handleSearchChanged);
    _messageController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleComposerChanged() {
    final hasText = _messageController.text.trim().isNotEmpty;
    if (_hasComposerText != hasText && mounted) {
      setState(() {
        _hasComposerText = hasText;
      });
    }
  }

  void _handleSearchChanged() {
    final next = _searchController.text.trim().toLowerCase();
    if (_searchQuery != next && mounted) {
      setState(() {
        _searchQuery = next;
      });
    }
  }

  String _fallbackThreadId(String firstUid, String secondUid) {
    final ids = [firstUid, secondUid]..sort();
    return '${ids[0]}__${ids[1]}';
  }

  Timestamp? _effectiveTimestamp(Map<String, dynamic> data) {
    return (data['createdAtClient'] as Timestamp?) ??
        (data['createdAt'] as Timestamp?);
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

  String _formatDayDivider(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${date.day} ${_monthName(date.month)}';
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

  String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
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

  Widget _buildHeaderAvatar(
    Map<String, dynamic>? profile,
    String displayName,
  ) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: _buildAvatar(profile, displayName),
    );
  }

  List<QueryDocumentSnapshot> _threadDocsForSnapshot(
    QuerySnapshot snapshot,
    User user,
  ) {
    return snapshot.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final threadId = (data['threadId'] as String?)?.trim();
      final channel =
          ((data['channel'] as String?)?.trim().isNotEmpty == true)
              ? (data['channel'] as String).trim()
              : 'mail';
      if (channel != widget.channel) return false;
      if (threadId != null && threadId.isNotEmpty) {
        return threadId == widget.threadId;
      }

      final senderId = (data['senderId'] as String?)?.trim() ?? '';
      final recipientId = (data['recipientId'] as String?)?.trim() ?? '';
      if (senderId.isEmpty) return false;
      final otherUserId = senderId == user.uid ? recipientId : senderId;
      if (otherUserId.isEmpty) return false;
      return _fallbackThreadId(user.uid, otherUserId) == widget.threadId;
    }).cast<QueryDocumentSnapshot>().toList()
      ..sort((a, b) {
        final aTime = _effectiveTimestamp(a.data() as Map<String, dynamic>);
        final bTime = _effectiveTimestamp(b.data() as Map<String, dynamic>);
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return aTime.compareTo(bTime);
      });
  }

  void _reconcilePendingMessages(
    List<QueryDocumentSnapshot> threadDocs,
    String currentUserId,
  ) {
    if (_pendingMessages.isEmpty) return;
    final remoteKeys = threadDocs
        .map((doc) => doc.data() as Map<String, dynamic>)
        .where((data) => (data['senderId'] as String?)?.trim() == currentUserId)
        .map((data) {
          final createdAtClient = data['createdAtClient'] as Timestamp?;
          final clientMessageId = (data['clientMessageId'] as String?)?.trim() ?? '';
          return (
            createdAtMs: createdAtClient?.millisecondsSinceEpoch ?? -1,
            clientMessageId: clientMessageId,
          );
        })
        .toList(growable: false);

    final nextPending = _pendingMessages.where((pending) {
      return !remoteKeys.any(
        (remote) =>
            remote.createdAtMs == pending.createdAtClient.millisecondsSinceEpoch ||
            (remote.clientMessageId.isNotEmpty &&
                remote.clientMessageId == pending.clientMessageId),
      );
    }).toList(growable: false);

    if (nextPending.length != _pendingMessages.length && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _pendingMessages = nextPending;
        });
      });
    }
  }

  List<_ChatMessageItem> _buildItems(
    List<QueryDocumentSnapshot> threadDocs,
    String currentUserId,
  ) {
    final items = <_ChatMessageItem>[
      ...threadDocs.map((doc) => _ChatMessageItem.fromDoc(doc, currentUserId)),
      ..._pendingMessages.map(
        (pending) => _ChatMessageItem.fromPending(pending, currentUserId),
      ),
    ];

    items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return items;
  }

  List<_ChatMessageItem> _filterItems(List<_ChatMessageItem> items) {
    if (_searchQuery.isEmpty) return items;
    return items.where((item) {
      final haystack = [
        item.message,
        item.senderName,
        item.replyPreview?.text ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(_searchQuery);
    }).toList(growable: false);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isSameSender(_ChatMessageItem? a, _ChatMessageItem? b) {
    if (a == null || b == null) return false;
    return a.senderId == b.senderId && _isSameDay(a.createdAt, b.createdAt);
  }
  void _setReplyTarget(_ChatMessageItem item) {
    setState(() {
      _editingMessageId = null;
      _editingCreatedAtClient = null;
      _replyTarget = _ReplyPreviewData(
        messageId: item.documentId ?? item.clientMessageId ?? '',
        senderId: item.senderId,
        senderName: item.isMine ? 'You' : item.senderName,
        text: item.message,
        messageType: item.messageType,
      );
    });
  }

  void _clearReplyTarget() {
    if (_replyTarget == null) return;
    setState(() {
      _replyTarget = null;
    });
  }

  void _startEditing(_ChatMessageItem item) {
    if (item.documentId == null) return;
    setState(() {
      _replyTarget = null;
      _editingMessageId = item.documentId;
      _editingCreatedAtClient = item.createdAtClient;
      _messageController.text = item.message;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: _messageController.text.length),
      );
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

  Future<void> _handleSendOrUpdate() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;

    final user = Provider.of<User?>(context, listen: false);
    if (user == null) return;

    setState(() => _sending = true);

    try {
      if (_editingMessageId != null && _editingCreatedAtClient != null) {
        await DatabaseService(user: user).updateEmailMessage(
          messageId: _editingMessageId!,
          newText: text,
          recipientId: widget.recipientId,
          createdAtClient: _editingCreatedAtClient!,
        );
        _stopEditing();
      } else {
        final createdAtClient = Timestamp.now();
        final clientMessageId =
            'local_${user.uid}_${createdAtClient.millisecondsSinceEpoch}';
        final pending = _PendingMessage(
          clientMessageId: clientMessageId,
          senderId: user.uid,
          senderName: user.displayName?.trim().isNotEmpty == true
              ? user.displayName!.trim()
              : 'You',
          message: text,
          createdAtClient: createdAtClient,
          status: _PendingMessageStatus.sending,
          replyPreview: _replyTarget,
        );

        setState(() {
          _pendingMessages = [..._pendingMessages, pending];
          _messageController.clear();
          _replyTarget = null;
        });

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
          createdAtClient: createdAtClient,
          clientMessageId: clientMessageId,
          replyPreview: pending.replyPreview?.toMap(),
        );

        if (!mounted) return;
        setState(() {
          _pendingMessages = _pendingMessages
              .map(
                (item) => item.clientMessageId == clientMessageId
                    ? item.copyWith(status: _PendingMessageStatus.sent)
                    : item,
              )
              .toList(growable: false);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pendingMessages = _pendingMessages
            .map(
              (item) => item.status == _PendingMessageStatus.sending
                  ? item.copyWith(status: _PendingMessageStatus.failed)
                  : item,
            )
            .toList(growable: false);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Message failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _toggleReaction(_ChatMessageItem item, String emoji) async {
    final user = Provider.of<User?>(context, listen: false);
    if (user == null || item.documentId == null) return;

    await DatabaseService(user: user).toggleMessageReaction(
      messageId: item.documentId!,
      recipientId: widget.recipientId,
      emoji: emoji,
      createdAtClient: item.createdAtClient,
    );
  }

  String _replySenderLabel(_ReplyPreviewData preview, User? user) {
    if (user != null && preview.senderId == user.uid) {
      return 'You';
    }
    if (preview.senderName.isNotEmpty) return preview.senderName;
    return 'Message';
  }

  Widget _buildReplyPreview(
    _ReplyPreviewData preview,
    Color accent,
    Color textColor,
    Color muted,
    User? user,
  ) {
    final senderLabel = _replySenderLabel(preview, user);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 34,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  senderLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  preview.text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: muted == textColor
                        ? textColor.withValues(alpha: 0.88)
                        : muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReactionRow(_ChatMessageItem item, User? user) {
    final accent = item.isMine
        ? (_isDarkMode(context) ? const Color(0xFF7BD6FF) : _telegramBlueDark)
        : (_isDarkMode(context)
            ? const Color(0xFF8FB4D8)
            : const Color(0xFF5A6C7D));

    final entries = item.reactions.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));

    return Padding(
      padding: EdgeInsets.only(
        top: 4,
        left: item.isMine ? 0 : 8,
        right: item.isMine ? 8 : 0,
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: item.isMine ? WrapAlignment.end : WrapAlignment.start,
        children: entries.map((entry) {
          final reacted = user != null && entry.value.contains(user.uid);
          return GestureDetector(
            onTap: () => _toggleReaction(item, entry.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: reacted
                    ? accent.withValues(alpha: 0.18)
                    : Colors.white.withValues(
                        alpha: _isDarkMode(context) ? 0.08 : 0.76,
                      ),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: reacted
                      ? accent.withValues(alpha: 0.35)
                      : Colors.black.withValues(alpha: 0.05),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(entry.key, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 4),
                  Text(
                    '${entry.value.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: reacted ? accent : _mutedTextColor(context),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
  IconData _statusIconForItem(_ChatMessageItem item) {
    if (item.pendingStatus == _PendingMessageStatus.sending) {
      return Icons.schedule_rounded;
    }
    if (item.pendingStatus == _PendingMessageStatus.failed) {
      return Icons.error_outline_rounded;
    }
    if (item.pendingStatus == _PendingMessageStatus.sent) {
      return Icons.done_rounded;
    }
    return item.isReadByRecipient ? Icons.done_all_rounded : Icons.done_rounded;
  }

  Color _statusColorForItem(_ChatMessageItem item) {
    if (item.pendingStatus == _PendingMessageStatus.failed) {
      return const Color(0xFFFFB4AB);
    }
    if (item.isReadByRecipient) {
      return const Color(0xFF4FC3F7);
    }
    return Colors.white.withValues(alpha: 0.78);
  }

  Widget _buildMessageBubble(
    _ChatMessageItem item,
    User? user, {
    required bool joinsPrevious,
    required bool joinsNext,
  }) {
    final bubbleColor = item.isMine
        ? _outgoingBubbleColor(context)
        : _incomingBubbleColor(context);
    final textColor = item.isMine
        ? _outgoingTextColor(context)
        : _incomingTextColor(context);
    final muted = item.isMine
        ? textColor.withValues(alpha: 0.62)
        : _mutedTextColor(context);
    final replyAccent = item.isMine
        ? (_isDarkMode(context) ? const Color(0xFF9DE5FF) : _telegramBlueDark)
        : (_isDarkMode(context) ? const Color(0xFF7DB1E0) : _telegramBlueDark);

    final radius = BorderRadius.only(
      topLeft: Radius.circular(item.isMine ? 18 : (joinsPrevious ? 8 : 18)),
      topRight: Radius.circular(item.isMine ? (joinsPrevious ? 8 : 18) : 18),
      bottomLeft: Radius.circular(item.isMine ? 18 : (joinsNext ? 6 : 18)),
      bottomRight: Radius.circular(item.isMine ? (joinsNext ? 6 : 18) : 18),
    );

    final showTail = !joinsNext;

    Widget bubbleBody = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.78,
      ),
      margin: EdgeInsets.only(
        top: joinsPrevious ? 1 : 8,
        bottom: item.reactions.isEmpty ? (joinsNext ? 1 : 6) : 2,
      ),
      child: Column(
        crossAxisAlignment:
            item.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: radius,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: _isDarkMode(context) ? 0.08 : 0.05,
                      ),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.replyPreview != null)
                        _buildReplyPreview(
                          item.replyPreview!,
                          replyAccent,
                          textColor,
                          muted,
                          user,
                        ),
                      Text(
                        item.message,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.3,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          if (item.isEdited) ...[
                            Text(
                              'edited',
                              style: TextStyle(
                                fontSize: 10,
                                color: muted,
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            _formatTime(item.createdAt),
                            style: TextStyle(
                              fontSize: 10,
                              color: muted,
                            ),
                          ),
                          if (item.isMine) ...[
                            const SizedBox(width: 4),
                            Icon(
                              _statusIconForItem(item),
                              size: 14,
                              color: _statusColorForItem(item),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (showTail)
                Positioned(
                  bottom: 0,
                  left: item.isMine ? null : -6,
                  right: item.isMine ? -6 : null,
                  child: CustomPaint(
                    size: const Size(12, 12),
                    painter: _BubbleTailPainter(
                      color: bubbleColor,
                      isMine: item.isMine,
                    ),
                  ),
                ),
            ],
          ),
          if (item.reactions.isNotEmpty) _buildReactionRow(item, user),
        ],
      ),
    );

    bubbleBody = _SwipeReplyWrapper(
      isMine: item.isMine,
      accentColor: replyAccent,
      onReply: () => _setReplyTarget(item),
      child: bubbleBody,
    );

    return GestureDetector(
      onLongPress: () => _showMessageOptions(item, user),
      child: Align(
        alignment: item.isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: bubbleBody,
      ),
    );
  }

  void _showMessageOptions(_ChatMessageItem item, User? user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _composerColor(context),
      showDragHandle: true,
      builder: (context) {
        final reactions = const ['👍', '❤️', '😂', '😮', '😢', '🔥'];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: reactions.map((emoji) {
                    final reacted = user != null &&
                        (item.reactions[emoji]?.contains(user.uid) ?? false);
                    return GestureDetector(
                      onTap: () async {
                        Navigator.pop(context);
                        await _toggleReaction(item, emoji);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: reacted
                              ? _chatHeaderColor(context).withValues(alpha: 0.16)
                              : Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(emoji, style: const TextStyle(fontSize: 22)),
                      ),
                    );
                  }).toList(growable: false),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(context);
                  _setReplyTarget(item);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_all_rounded),
                title: const Text('Copy'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: item.message));
                  Navigator.pop(context);
                },
              ),
              if (item.isMine && !item.isPending)
                ListTile(
                  leading: const Icon(Icons.edit_rounded),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(context);
                    _startEditing(item);
                  },
                ),
              if (item.isMine && !item.isPending)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                  title: const Text(
                    'Unsend',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    if (user == null || item.documentId == null) return;
                    await DatabaseService(user: user).deleteEmailMessage(
                      messageId: item.documentId!,
                      recipientId: widget.recipientId,
                      createdAtClient: item.createdAtClient,
                    );
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
  Widget _buildComposer() {
    final composerColor = _composerColor(context);
    final muted = _mutedTextColor(context);
    final canSend = _hasComposerText || _editingMessageId != null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyTarget != null || _editingMessageId != null)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: composerColor,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: _isDarkMode(context) ? 0.18 : 0.05,
                      ),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 34,
                      decoration: BoxDecoration(
                        color: _chatHeaderColor(context),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _editingMessageId != null
                                ? 'Edit message'
                                : 'Reply to ${_replySenderLabel(_replyTarget!, Provider.of<User?>(context, listen: false))}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: _chatHeaderColor(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _editingMessageId != null
                                ? 'Update the message text below'
                                : _replyTarget!.text,
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
                      onPressed: () {
                        if (_editingMessageId != null) {
                          _stopEditing();
                        } else {
                          _clearReplyTarget();
                        }
                      },
                      icon: Icon(Icons.close_rounded, color: muted),
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
                      color: composerColor,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: _isDarkMode(context) ? 0.18 : 0.05,
                          ),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        IconButton(
                          onPressed: () {},
                          icon: Icon(Icons.attach_file_rounded, color: muted),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            minLines: 1,
                            maxLines: 6,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: 'Message',
                              hintStyle: TextStyle(color: muted),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () {},
                          icon: Icon(
                            Icons.sentiment_satisfied_alt_rounded,
                            color: muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) => ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                  child: Container(
                    key: ValueKey<bool>(canSend),
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: _chatHeaderColor(context),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: canSend
                          ? (_sending ? null : _handleSendOrUpdate)
                          : () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Voice messages UI is ready. Recording can be added next.',
                                  ),
                                ),
                              );
                            },
                      icon: Icon(
                        canSend ? Icons.send_rounded : Icons.mic_rounded,
                        color: Colors.white,
                      ),
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

  void _toggleSearchMode() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
      }
    });
  }

  void _showChatMenu() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text('View profile'),
              onTap: () {
                Navigator.pop(context);
                UserAvatar.showViewer(
                  context,
                  displayName: widget.recipientName,
                );
              },
            ),
            if (_replyTarget != null || _editingMessageId != null)
              ListTile(
                leading: const Icon(Icons.clear_all_rounded),
                title: const Text('Clear current draft action'),
                onTap: () {
                  Navigator.pop(context);
                  if (_editingMessageId != null) {
                    _stopEditing();
                  } else {
                    _clearReplyTarget();
                  }
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<User?>(context);
    final header = _chatHeaderColor(context);
    final canvas = _chatCanvasColor(context);
    final muted = _mutedTextColor(context);

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
            if (_isSearching) {
              return TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: const InputDecoration(
                  hintText: 'Search messages',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
              );
            }
            return GestureDetector(
              onTap: () => UserAvatar.showViewer(
                context,
                avatarId: (profile?['avatarId'] as String?)?.trim(),
                profilePicBase64: (profile?['profilePicBase64'] as String?)?.trim(),
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Row(
                          children: [
                            if (widget.channel == 'chat') ...[
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF7CFC8B),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                widget.channel == 'chat'
                                    ? 'online'
                                    : ((widget.threadSubject ?? '').trim().isNotEmpty
                                        ? widget.threadSubject!.trim()
                                        : 'Course mail'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          IconButton(
            onPressed: _toggleSearchMode,
            icon: Icon(
              _isSearching ? Icons.close_rounded : Icons.search_rounded,
            ),
          ),
          IconButton(
            onPressed: _showChatMenu,
            icon: const Icon(Icons.more_vert_rounded),
          ),
        ],
      ),
      body: user == null
          ? const SizedBox.shrink()
          : Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: canvas),
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

                          final threadDocs = _threadDocsForSnapshot(snapshot.data!, user);
                          unawaited(_markThreadAsRead(user, threadDocs));
                          _reconcilePendingMessages(threadDocs, user.uid);
                          final items = _filterItems(
                            _buildItems(threadDocs, user.uid),
                          );
                          _scheduleScrollToBottom(items.length);

                          if (items.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 28),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.chat_bubble_outline_rounded,
                                      color: muted,
                                      size: 44,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Start the conversation',
                                      style: TextStyle(
                                        color: _incomingTextColor(context),
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Messages sent here will appear in real time.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: muted),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          return ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              final previous = index > 0 ? items[index - 1] : null;
                              final next = index < items.length - 1 ? items[index + 1] : null;
                              final showDayDivider = previous == null ||
                                  !_isSameDay(previous.createdAt, item.createdAt);

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
                                              : Colors.white.withValues(alpha: 0.76),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          _formatDayDivider(item.createdAt),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: muted,
                                          ),
                                        ),
                                      ),
                                    ),
                                  _buildMessageBubble(
                                    item,
                                    user,
                                    joinsPrevious: _isSameSender(previous, item),
                                    joinsNext: _isSameSender(item, next),
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

class _SwipeReplyWrapper extends StatefulWidget {
  const _SwipeReplyWrapper({
    required this.child,
    required this.onReply,
    required this.isMine,
    required this.accentColor,
  });

  final Widget child;
  final VoidCallback onReply;
  final bool isMine;
  final Color accentColor;

  @override
  State<_SwipeReplyWrapper> createState() => _SwipeReplyWrapperState();
}

class _SwipeReplyWrapperState extends State<_SwipeReplyWrapper> {
  double _offset = 0;
  bool _didTrigger = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        final next = (_offset + details.delta.dx).clamp(0.0, 52.0);
        setState(() {
          _offset = next;
        });
      },
      onHorizontalDragEnd: (_) {
        if (_offset > 34 && !_didTrigger) {
          _didTrigger = true;
          HapticFeedback.mediumImpact();
          widget.onReply();
        }
        setState(() {
          _offset = 0;
          _didTrigger = false;
        });
      },
      onHorizontalDragCancel: () {
        setState(() {
          _offset = 0;
          _didTrigger = false;
        });
      },
      child: Stack(
        alignment: widget.isMine ? Alignment.centerRight : Alignment.centerLeft,
        children: [
          Positioned(
            left: widget.isMine ? null : 4,
            right: widget.isMine ? 4 : null,
            child: Opacity(
              opacity: (_offset / 40).clamp(0, 1),
              child: Icon(
                Icons.reply_rounded,
                color: widget.accentColor,
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(_offset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter({
    required this.color,
    required this.isMine,
  });

  final Color color;
  final bool isMine;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();

    if (isMine) {
      path.moveTo(0, size.height);
      path.quadraticBezierTo(
        size.width * 0.4,
        size.height * 0.86,
        size.width,
        0,
      );
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(size.width, size.height);
      path.quadraticBezierTo(
        size.width * 0.6,
        size.height * 0.86,
        0,
        0,
      );
      path.lineTo(0, size.height);
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.isMine != isMine;
  }
}

class _ChatBackdropPainter extends CustomPainter {
  const _ChatBackdropPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = (isDark ? Colors.white : const Color(0xFFB0BEC5)).withValues(
        alpha: isDark ? 0.03 : 0.08,
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    final fillPaint = Paint()
      ..color = (isDark ? Colors.white : const Color(0xFFD7E1E7)).withValues(
        alpha: isDark ? 0.02 : 0.06,
      )
      ..style = PaintingStyle.fill;

    final circles = <Offset>[
      Offset(size.width * 0.15, size.height * 0.18),
      Offset(size.width * 0.82, size.height * 0.24),
      Offset(size.width * 0.22, size.height * 0.64),
      Offset(size.width * 0.76, size.height * 0.78),
    ];
    for (final center in circles) {
      canvas.drawCircle(center, 14, fillPaint);
      canvas.drawCircle(center, 24, strokePaint);
    }

    final lines = <Path>[
      Path()
        ..moveTo(size.width * 0.08, size.height * 0.12)
        ..quadraticBezierTo(
          size.width * 0.22,
          size.height * 0.04,
          size.width * 0.36,
          size.height * 0.14,
        ),
      Path()
        ..moveTo(size.width * 0.60, size.height * 0.10)
        ..quadraticBezierTo(
          size.width * 0.72,
          size.height * 0.02,
          size.width * 0.88,
          size.height * 0.13,
        ),
      Path()
        ..moveTo(size.width * 0.10, size.height * 0.54)
        ..quadraticBezierTo(
          size.width * 0.18,
          size.height * 0.44,
          size.width * 0.30,
          size.height * 0.55,
        ),
      Path()
        ..moveTo(size.width * 0.65, size.height * 0.62)
        ..quadraticBezierTo(
          size.width * 0.78,
          size.height * 0.52,
          size.width * 0.90,
          size.height * 0.64,
        ),
    ];

    for (final path in lines) {
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChatBackdropPainter oldDelegate) {
    return oldDelegate.isDark != isDark;
  }
}
