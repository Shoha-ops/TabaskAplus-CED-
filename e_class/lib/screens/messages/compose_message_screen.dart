import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:e_class/models/student_model.dart';
import 'package:e_class/screens/messages/conversation_screen.dart';
import 'package:e_class/services/database_service.dart';
import 'package:e_class/services/search_helper.dart';
import 'package:e_class/widgets/user_avatar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ComposeMessageScreen extends StatefulWidget {
  final String? initialRecipientId;
  final String? initialRecipientName;
  final bool isChat;

  const ComposeMessageScreen({
    super.key,
    this.initialRecipientId,
    this.initialRecipientName,
    this.isChat = false,
  });

  @override
  State<ComposeMessageScreen> createState() => _ComposeMessageScreenState();
}

class _ComposeMessageScreenState extends State<ComposeMessageScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  String _query = '';
  String? _selectedRecipientId;
  String? _selectedRecipientName;
  bool _sending = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _selectedRecipientId = widget.initialRecipientId;
    _selectedRecipientName = widget.initialRecipientName;
    _searchController.text = widget.initialRecipientName ?? '';
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  String _threadIdFor(String firstUid, String secondUid) {
    final ids = [firstUid, secondUid]..sort();
    return '${ids[0]}__${ids[1]}';
  }

  bool _matchesSearch(StudentModel student, String query) {
    final tokens = SearchHelper.tokenize(query);
    if (tokens.isEmpty) return true;

    final fields = [
      SearchHelper.normalize(student.fullName),
      SearchHelper.normalize(student.studentId),
      SearchHelper.normalize(student.group),
      SearchHelper.normalize(student.email),
      SearchHelper.compact(student.studentId),
      SearchHelper.compact(student.group),
    ];

    return tokens.every(
      (token) => fields.any(
        (field) => field.startsWith(token) || field.contains(token),
      ),
    );
  }

  int _searchScore(StudentModel student, String query) {
    final normalizedQuery = SearchHelper.normalize(query);
    final compactQuery = SearchHelper.compact(query);
    final fullName = SearchHelper.normalize(student.fullName);
    final studentId = SearchHelper.normalize(student.studentId);
    final group = SearchHelper.normalize(student.group);

    if (normalizedQuery.isEmpty) return 10;
    if (studentId == normalizedQuery || group == normalizedQuery) return 0;
    if (SearchHelper.compact(studentId) == compactQuery ||
        SearchHelper.compact(group) == compactQuery) {
      return 1;
    }
    if (fullName == normalizedQuery) return 2;
    if (fullName.startsWith(normalizedQuery)) return 3;
    if (studentId.startsWith(normalizedQuery) || group.startsWith(normalizedQuery)) {
      return 4;
    }
    if (fullName.contains(normalizedQuery)) return 5;
    return 6;
  }

  void _onQueryChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      setState(() {
        _query = value.trim();
        if (_selectedRecipientName == value.trim()) return;
        _selectedRecipientId = null;
        _selectedRecipientName = null;
      });
    });
  }

  List<StudentModel> _visibleStudents(List<QueryDocumentSnapshot> docs, String currentUserId) {
    final students = docs
        .where((doc) => doc.id != currentUserId)
        .map(StudentModel.fromFirestore)
        .where((student) => _matchesSearch(student, _query))
        .toList()
      ..sort((a, b) {
        final scoreCompare = _searchScore(a, _query).compareTo(_searchScore(b, _query));
        if (scoreCompare != 0) return scoreCompare;
        if (a.group != b.group) return a.group.compareTo(b.group);
        return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
      });

    return students;
  }

  Future<void> _openChat(StudentModel student, User currentUser) async {
    final threadId = _threadIdFor(currentUser.uid, student.uid);
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ConversationScreen(
          threadId: threadId,
          recipientId: student.uid,
          recipientName: student.fullName,
          channel: 'chat',
        ),
      ),
    );
  }

  Future<void> _sendMail(User currentUser) async {
    if (!_formKey.currentState!.validate() || _selectedRecipientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a recipient first')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      await DatabaseService(user: currentUser).sendEmail(
        recipientUid: _selectedRecipientId!,
        subject: _subjectController.text.trim(),
        message: _messageController.text.trim(),
        channel: 'mail',
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send mail: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _buildStudentTile(
    BuildContext context,
    StudentModel student, {
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = [
      if (student.group.isNotEmpty) student.group,
      if (student.studentId.isNotEmpty) student.studentId,
    ].join(' • ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            UserAvatar(
              avatarId: student.avatarId,
              profilePicBase64: student.profilePicBase64,
              profilePicUrl: student.profilePicUrl,
              displayName: student.fullName,
              radius: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<User?>(context);
    final scheme = Theme.of(context).colorScheme;

    if (user == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(
          widget.isChat ? 'New Message' : 'New Mail',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(
                bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
              ),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                hintText: widget.isChat
                    ? 'Search by name, group or student ID'
                    : 'Recipient',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          _onQueryChanged('');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final students = _visibleStudents(snapshot.data!.docs, user.uid);

                if (widget.isChat) {
                  if (students.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 56,
                              color: scheme.outline,
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'No chats found',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Try another name, group or student ID.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: students.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      indent: 76,
                      color: scheme.outlineVariant.withValues(alpha: 0.2),
                    ),
                    itemBuilder: (context, index) {
                      final student = students[index];
                      return _buildStudentTile(
                        context,
                        student,
                        onTap: () => _openChat(student, user),
                      );
                    },
                  );
                }

                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        if (_selectedRecipientName == null) ...[
                          Expanded(
                            child: students.isEmpty
                                ? Center(
                                    child: Text(
                                      'No matching students found.',
                                      style: TextStyle(color: scheme.onSurfaceVariant),
                                    ),
                                  )
                                : Card(
                                    margin: EdgeInsets.zero,
                                    child: ListView.separated(
                                      itemCount: students.length,
                                      separatorBuilder: (context, index) => Divider(
                                        height: 1,
                                        indent: 76,
                                        color: scheme.outlineVariant.withValues(alpha: 0.2),
                                      ),
                                      itemBuilder: (context, index) {
                                        final student = students[index];
                                        return _buildStudentTile(
                                          context,
                                          student,
                                          onTap: () {
                                            setState(() {
                                              _selectedRecipientId = student.uid;
                                              _selectedRecipientName = student.fullName;
                                              _searchController.text = student.fullName;
                                            });
                                          },
                                        );
                                      },
                                    ),
                                  ),
                          ),
                        ] else ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.person_outline_rounded),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _selectedRecipientName!,
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _selectedRecipientId = null;
                                      _selectedRecipientName = null;
                                      _searchController.clear();
                                      _query = '';
                                    });
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _subjectController,
                            decoration: const InputDecoration(labelText: 'Subject'),
                            validator: (val) =>
                                val == null || val.trim().isEmpty ? 'Required' : null,
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _messageController,
                              maxLines: null,
                              expands: true,
                              textAlignVertical: TextAlignVertical.top,
                              decoration: const InputDecoration(
                                hintText: 'Write your message',
                                alignLabelWithHint: true,
                              ),
                              validator: (val) =>
                                  val == null || val.trim().isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _sending ? null : () => _sendMail(user),
                              icon: const Icon(Icons.send_rounded),
                              label: const Text('Send mail'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
