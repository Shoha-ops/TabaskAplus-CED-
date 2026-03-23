import 'dart:async';

import 'package:e_class/models/student_model.dart';
import 'package:flutter/material.dart';
import 'package:e_class/services/database_service.dart';
import 'package:e_class/services/search_helper.dart';
import 'package:e_class/widgets/user_avatar.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  final TextEditingController _recipientController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  String? _selectedRecipientId;
  List<StudentModel> _searchResults = [];
  bool _searching = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    if (widget.initialRecipientName != null) {
      _recipientController.text = widget.initialRecipientName!;
      _selectedRecipientId = widget.initialRecipientId;
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _recipientController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  bool _matchesSearch(StudentModel student, String query) {
    final tokens = SearchHelper.tokenize(query);
    if (tokens.isEmpty) return false;

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

    if (studentId == normalizedQuery || group == normalizedQuery) return 0;
    if (SearchHelper.compact(studentId) == compactQuery ||
        SearchHelper.compact(group) == compactQuery) {
      return 1;
    }
    if (fullName == normalizedQuery) return 2;
    if (studentId.startsWith(normalizedQuery) ||
        group.startsWith(normalizedQuery)) {
      return 3;
    }
    if (fullName.startsWith(normalizedQuery)) return 4;
    if (fullName.contains(normalizedQuery)) return 5;
    return 6;
  }

  Future<void> _searchRecipients(String query) async {
    if (query.isEmpty) {
      setState(() {
        _selectedRecipientId = null;
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _selectedRecipientId = null;
      _searching = true;
    });

    try {
      final user = Provider.of<User?>(context, listen: false);
      final docs = await DatabaseService(user: user).searchRecipients(query);
      final results =
          docs
              .map(StudentModel.fromFirestore)
              .where((student) => _matchesSearch(student, query))
              .toList()
            ..sort((a, b) {
              final scoreCompare = _searchScore(
                a,
                query,
              ).compareTo(_searchScore(b, query));
              if (scoreCompare != 0) return scoreCompare;
              return a.fullName.toLowerCase().compareTo(
                b.fullName.toLowerCase(),
              );
            });

      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _searching = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error searching: $e')));
    }
  }

  void _onRecipientChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 250),
      () => _searchRecipients(value.trim()),
    );
  }

  Future<void> _sendMessage() async {
    if (!_formKey.currentState!.validate() || _selectedRecipientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a recipient')),
      );
      return;
    }

    try {
      final user = Provider.of<User?>(context, listen: false);
      if (user != null) {
        await DatabaseService(user: user).sendEmail(
          recipientUid: _selectedRecipientId!,
          subject: widget.isChat ? '' : _subjectController.text,
          message: _messageController.text,
          channel: widget.isChat ? 'chat' : 'mail',
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Message sent')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error sending message: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.isChat ? 'New Chat' : 'New Mail')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _recipientController,
                decoration: InputDecoration(
                  labelText: 'To',
                  hintText: 'Name, student ID or group',
                  suffixIcon: _searching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                ),
                onChanged: _onRecipientChanged,
                validator: (val) => val!.isEmpty ? 'Required' : null,
              ),
              if (_selectedRecipientId == null &&
                  _recipientController.text.trim().isNotEmpty &&
                  !_searching &&
                  _searchResults.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'No matching students or groups found',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              if (_searchResults.isNotEmpty && _selectedRecipientId == null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: Card(
                    margin: const EdgeInsets.only(top: 8),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final student = _searchResults[index];
                        final subtitleParts = <String>[
                          if (student.studentId.isNotEmpty) student.studentId,
                          if (student.group.isNotEmpty) student.group,
                        ];
                        return ListTile(
                          dense: true,
                          leading: UserAvatar(
                            avatarId: student.avatarId,
                            profilePicBase64: student.profilePicBase64,
                            profilePicUrl: student.profilePicUrl,
                            displayName: student.fullName,
                          ),
                          title: Text(student.fullName),
                          subtitle: Text(subtitleParts.join(' - ')),
                          trailing: Text(
                            'Select',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onTap: () {
                            setState(() {
                              _selectedRecipientId = student.uid;
                              _recipientController.text = student.fullName;
                              _searchResults = [];
                            });
                          },
                        );
                      },
                    ),
                  ),
                ),
              if (!widget.isChat) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _subjectController,
                  decoration: const InputDecoration(labelText: 'Subject'),
                  validator: (val) => val!.isEmpty ? 'Required' : null,
                ),
              ],
              const SizedBox(height: 16),
              Expanded(
                child: TextFormField(
                  controller: _messageController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) => val!.isEmpty ? 'Required' : null,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _sendMessage,
                icon: const Icon(Icons.send),
                label: const Text('Send'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
