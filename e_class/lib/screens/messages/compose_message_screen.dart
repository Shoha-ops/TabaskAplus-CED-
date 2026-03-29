import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:e_class/models/courses/course.dart';
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

class _SelectedRecipient {
  final String id;
  final String name;

  const _SelectedRecipient({required this.id, required this.name});
}

class _RecipientSearchItem {
  const _RecipientSearchItem({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.searchText,
    required this.profilePicUrl,
    this.avatarId,
    this.profilePicBase64,
  });

  final String id;
  final String name;
  final String subtitle;
  final String searchText;
  final String profilePicUrl;
  final String? avatarId;
  final String? profilePicBase64;
}

class _ComposeMessageScreenState extends State<ComposeMessageScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _toController = TextEditingController();
  final TextEditingController _ccController = TextEditingController();
  final TextEditingController _bccController = TextEditingController();
  final TextEditingController _coAuthorController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _chatSearchController = TextEditingController();

  String _toQuery = '';
  String _ccQuery = '';
  String _bccQuery = '';
  String _coAuthorQuery = '';
  String _chatQuery = '';

  final List<_SelectedRecipient> _toRecipients = [];
  final List<_SelectedRecipient> _ccRecipients = [];
  final List<_SelectedRecipient> _bccRecipients = [];
  final List<_SelectedRecipient> _coAuthorRecipients = [];

  bool _sending = false;

  Timer? _toDebounce;
  Timer? _ccDebounce;
  Timer? _bccDebounce;
  Timer? _coAuthorDebounce;
  Timer? _chatDebounce;

  @override
  void initState() {
    super.initState();
    final initialId = widget.initialRecipientId?.trim() ?? '';
    final initialName = widget.initialRecipientName?.trim() ?? '';
    if (initialId.isNotEmpty && initialName.isNotEmpty) {
      _toRecipients.add(_SelectedRecipient(id: initialId, name: initialName));
    }
  }

  @override
  void dispose() {
    _toDebounce?.cancel();
    _ccDebounce?.cancel();
    _bccDebounce?.cancel();
    _coAuthorDebounce?.cancel();
    _chatDebounce?.cancel();
    _toController.dispose();
    _ccController.dispose();
    _bccController.dispose();
    _coAuthorController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    _chatSearchController.dispose();
    super.dispose();
  }

  String _threadIdFor(String firstUid, String secondUid) {
    final ids = [firstUid, secondUid]..sort();
    return '${ids[0]}__${ids[1]}';
  }

  bool _matchesSearchText(String searchText, String query) {
    final tokens = SearchHelper.tokenize(query);
    if (tokens.isEmpty) return true;

    final fields = [
      SearchHelper.normalize(searchText),
      SearchHelper.compact(searchText),
    ];

    return tokens.every(
      (token) => fields.any(
        (field) => field.startsWith(token) || field.contains(token),
      ),
    );
  }

  int _searchScore(_RecipientSearchItem item, String query) {
    final normalizedQuery = SearchHelper.normalize(query);
    final compactQuery = SearchHelper.compact(query);
    final fullName = SearchHelper.normalize(item.name);
    final searchable = SearchHelper.normalize(item.searchText);
    final compactSearchable = SearchHelper.compact(item.searchText);

    if (normalizedQuery.isEmpty) return 10;
    if (searchable == normalizedQuery || compactSearchable == compactQuery) {
      return 1;
    }
    if (fullName == normalizedQuery) return 2;
    if (fullName.startsWith(normalizedQuery)) return 3;
    if (searchable.startsWith(normalizedQuery)) {
      return 4;
    }
    if (fullName.contains(normalizedQuery)) return 5;
    return 6;
  }

  void _onQueryChanged(String value, String field) {
    void updateState(void Function() updater) {
      if (!mounted) return;
      setState(updater);
    }

    switch (field) {
      case 'to':
        _toDebounce?.cancel();
        _toDebounce = Timer(const Duration(milliseconds: 120), () {
          updateState(() => _toQuery = value.trim());
        });
        break;
      case 'cc':
        _ccDebounce?.cancel();
        _ccDebounce = Timer(const Duration(milliseconds: 120), () {
          updateState(() => _ccQuery = value.trim());
        });
        break;
      case 'bcc':
        _bccDebounce?.cancel();
        _bccDebounce = Timer(const Duration(milliseconds: 120), () {
          updateState(() => _bccQuery = value.trim());
        });
        break;
      case 'co':
        _coAuthorDebounce?.cancel();
        _coAuthorDebounce = Timer(const Duration(milliseconds: 120), () {
          updateState(() => _coAuthorQuery = value.trim());
        });
        break;
      case 'chat':
        _chatDebounce?.cancel();
        _chatDebounce = Timer(const Duration(milliseconds: 120), () {
          updateState(() => _chatQuery = value.trim());
        });
        break;
      default:
        break;
    }
  }

  bool _isSelectedInAnyList(String id) {
    return _toRecipients.any((recipient) => recipient.id == id) ||
        _ccRecipients.any((recipient) => recipient.id == id) ||
        _bccRecipients.any((recipient) => recipient.id == id) ||
        _coAuthorRecipients.any((recipient) => recipient.id == id);
  }

  void _addRecipient(
    _RecipientSearchItem recipient,
    List<_SelectedRecipient> target,
    TextEditingController controller,
    void Function(String) clearQuery,
  ) {
    if (_isSelectedInAnyList(recipient.id)) return;
    setState(() {
      target.add(_SelectedRecipient(id: recipient.id, name: recipient.name));
      controller.clear();
      clearQuery('');
    });
  }

  void _removeRecipient(String id) {
    setState(() {
      _toRecipients.removeWhere((recipient) => recipient.id == id);
      _ccRecipients.removeWhere((recipient) => recipient.id == id);
      _bccRecipients.removeWhere((recipient) => recipient.id == id);
      _coAuthorRecipients.removeWhere((recipient) => recipient.id == id);
    });
  }

  void _clearCompose() {
    setState(() {
      _toRecipients.clear();
      _ccRecipients.clear();
      _bccRecipients.clear();
      _coAuthorRecipients.clear();
      _toController.clear();
      _ccController.clear();
      _bccController.clear();
      _coAuthorController.clear();
      _subjectController.clear();
      _messageController.clear();
      _toQuery = '';
      _ccQuery = '';
      _bccQuery = '';
      _coAuthorQuery = '';
    });
  }

  Future<void> _confirmDiscard() async {
    final shouldDiscard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard draft?'),
        content: const Text('Your changes will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (shouldDiscard == true) {
      _clearCompose();
    }
  }

  List<_RecipientSearchItem> _visibleRecipients(
    List<QueryDocumentSnapshot> userDocs,
    List<QueryDocumentSnapshot> staffDocs,
    String currentUserId,
    String query,
  ) {
    final students = userDocs
        .where((doc) => doc.id != currentUserId)
        .map(StudentModel.fromFirestore)
        .map(
          (student) => _RecipientSearchItem(
            id: student.uid,
            name: student.fullName,
            subtitle: [
              if (student.group.isNotEmpty) student.group,
              if (student.studentId.isNotEmpty) student.studentId,
            ].join(' - '),
            searchText:
                '${student.fullName} ${student.studentId} ${student.group} ${student.email}',
            profilePicUrl: student.profilePicUrl ?? '',
            avatarId: student.avatarId,
            profilePicBase64: student.profilePicBase64,
          ),
        );

    final staff = staffDocs
        .map(Staff.fromFirestore)
        .map(
          (member) => _RecipientSearchItem(
            id: member.id,
            name: member.name,
            subtitle: [
              member.role,
              if (member.officeHours.isNotEmpty)
                '${member.officeHours.first.day} ${member.officeHours.first.time}',
            ].join(' - '),
            searchText:
                '${member.name} ${member.role} ${member.officeHours.map((hour) => '${hour.day} ${hour.time} ${hour.location}').join(' ')}',
            profilePicUrl: member.avatarUrl,
          ),
        );

    final recipients =
        [
            ...students,
            ...staff,
          ].where((item) => _matchesSearchText(item.searchText, query)).toList()
          ..sort((a, b) {
            final scoreCompare = _searchScore(
              a,
              query,
            ).compareTo(_searchScore(b, query));
            if (scoreCompare != 0) return scoreCompare;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });

    return recipients;
  }

  Future<void> _openChat(
    _RecipientSearchItem recipient,
    User currentUser,
  ) async {
    final threadId = _threadIdFor(currentUser.uid, recipient.id);
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ConversationScreen(
          threadId: threadId,
          recipientId: recipient.id,
          recipientName: recipient.name,
          channel: 'chat',
        ),
      ),
    );
  }

  Future<void> _sendMail(User currentUser) async {
    if (!_formKey.currentState!.validate() || _toRecipients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose at least one recipient')),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      final service = DatabaseService(user: currentUser);
      final subject = _subjectController.text.trim();
      final message = _messageController.text.trim();
      final recipients = <_SelectedRecipient>[
        ..._toRecipients,
        ..._ccRecipients,
        ..._bccRecipients,
        ..._coAuthorRecipients,
      ];

      await Future.wait(
        recipients.map(
          (recipient) => service.sendEmail(
            recipientUid: recipient.id,
            subject: subject,
            message: message,
            channel: 'mail',
          ),
        ),
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not send mail: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _buildRecipientTile(
    BuildContext context,
    _RecipientSearchItem recipient, {
    required VoidCallback onTap,
    bool isSelected = false,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            UserAvatar(
              avatarId: recipient.avatarId,
              profilePicBase64: recipient.profilePicBase64,
              profilePicUrl: recipient.profilePicUrl,
              displayName: recipient.name,
              radius: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipient.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (recipient.subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        recipient.subtitle,
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
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.check_circle_rounded,
                  color: scheme.primary,
                  size: 22,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecipientResults(
    List<_RecipientSearchItem> results, {
    required bool Function(String id) isSelected,
    required void Function(_RecipientSearchItem recipient) onSelect,
  }) {
    if (results.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 140,
      child: Card(
        margin: EdgeInsets.zero,
        child: ListView.separated(
          itemCount: results.length,
          separatorBuilder: (context, index) => Divider(
            height: 1,
            indent: 76,
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
          itemBuilder: (context, index) {
            final recipient = results[index];
            final selected = isSelected(recipient.id);
            return _buildRecipientTile(
              context,
              recipient,
              isSelected: selected,
              onTap: () {
                if (!selected) {
                  onSelect(recipient);
                } else {
                  _removeRecipient(recipient.id);
                }
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildInlineField({
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    required String hintText,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 280),
      child: IntrinsicWidth(
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hintText,
            isDense: true,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedRecipientTag(
    _SelectedRecipient recipient,
    ColorScheme scheme,
  ) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                recipient.name,
                softWrap: true,
                style: TextStyle(color: scheme.onPrimaryContainer),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _removeRecipient(recipient.id),
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressRow(
    ColorScheme scheme, {
    required String label,
    required List<_SelectedRecipient> selected,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    required String hintText,
    Widget? trailing,
  }) {
    final chipWidgets = selected
        .map((recipient) => _buildSelectedRecipientTag(recipient, scheme))
        .toList(growable: false);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...chipWidgets,
                _buildInlineField(
                  controller: controller,
                  onChanged: onChanged,
                  hintText: hintText,
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      ),
    );
  }

  Widget _buildResultsSection(
    List<_RecipientSearchItem> results, {
    required String query,
    required bool Function(String id) isSelected,
    required void Function(_RecipientSearchItem recipient) onSelect,
  }) {
    if (query.isEmpty) return const SizedBox.shrink();
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'No matches found.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _buildRecipientResults(
        results,
        isSelected: isSelected,
        onSelect: onSelect,
      ),
    );
  }

  Widget _buildMailComposer(
    BuildContext context,
    User user,
    List<QueryDocumentSnapshot> userDocs,
    List<QueryDocumentSnapshot> staffDocs,
  ) {
    final scheme = Theme.of(context).colorScheme;

    final toResults = _visibleRecipients(
      userDocs,
      staffDocs,
      user.uid,
      _toQuery,
    );
    final ccResults = _visibleRecipients(
      userDocs,
      staffDocs,
      user.uid,
      _ccQuery,
    );
    final bccResults = _visibleRecipients(
      userDocs,
      staffDocs,
      user.uid,
      _bccQuery,
    );
    final coAuthorResults = _visibleRecipients(
      userDocs,
      staffDocs,
      user.uid,
      _coAuthorQuery,
    );

    final hasRecipients = _toRecipients.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 48,
                    child: Text(
                      'From',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      user.email ?? 'Unknown sender',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildAddressRow(
              scheme,
              label: 'To',
              selected: _toRecipients,
              controller: _toController,
              onChanged: (value) => _onQueryChanged(value, 'to'),
              hintText: 'Add recipients',
            ),
            _buildResultsSection(
              toResults,
              query: _toQuery,
              isSelected: (id) => _toRecipients.any((item) => item.id == id),
              onSelect: (recipient) => _addRecipient(
                recipient,
                _toRecipients,
                _toController,
                (value) => _toQuery = value,
              ),
            ),
            const SizedBox(height: 12),
            _buildAddressRow(
              scheme,
              label: 'Cc',
              selected: _ccRecipients,
              controller: _ccController,
              onChanged: (value) => _onQueryChanged(value, 'cc'),
              hintText: 'Add Cc',
            ),
            _buildResultsSection(
              ccResults,
              query: _ccQuery,
              isSelected: (id) => _ccRecipients.any((item) => item.id == id),
              onSelect: (recipient) => _addRecipient(
                recipient,
                _ccRecipients,
                _ccController,
                (value) => _ccQuery = value,
              ),
            ),
            const SizedBox(height: 12),
            _buildAddressRow(
              scheme,
              label: 'Bcc',
              selected: _bccRecipients,
              controller: _bccController,
              onChanged: (value) => _onQueryChanged(value, 'bcc'),
              hintText: 'Add Bcc',
            ),
            _buildResultsSection(
              bccResults,
              query: _bccQuery,
              isSelected: (id) => _bccRecipients.any((item) => item.id == id),
              onSelect: (recipient) => _addRecipient(
                recipient,
                _bccRecipients,
                _bccController,
                (value) => _bccQuery = value,
              ),
            ),
            const SizedBox(height: 12),
            _buildAddressRow(
              scheme,
              label: 'Co',
              selected: _coAuthorRecipients,
              controller: _coAuthorController,
              onChanged: (value) => _onQueryChanged(value, 'co'),
              hintText: 'Add co-authors',
            ),
            _buildResultsSection(
              coAuthorResults,
              query: _coAuthorQuery,
              isSelected: (id) =>
                  _coAuthorRecipients.any((item) => item.id == id),
              onSelect: (recipient) => _addRecipient(
                recipient,
                _coAuthorRecipients,
                _coAuthorController,
                (value) => _coAuthorQuery = value,
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
            Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Attach',
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Attachments are not available yet.',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.attach_file_rounded),
                      ),
                      IconButton(
                        tooltip: 'Bold',
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Formatting coming soon.'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.format_bold_rounded),
                      ),
                      IconButton(
                        tooltip: 'Italic',
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Formatting coming soon.'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.format_italic_rounded),
                      ),
                      IconButton(
                        tooltip: 'Underline',
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Formatting coming soon.'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.format_underline_rounded),
                      ),
                      IconButton(
                        tooltip: 'Link',
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Links coming soon.')),
                          );
                        },
                        icon: const Icon(Icons.link_rounded),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _confirmDiscard,
                        child: const Text('Discard'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 240,
                    child: TextFormField(
                      controller: _messageController,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        hintText: 'Write your message',
                        border: InputBorder.none,
                      ),
                      validator: (val) =>
                          val == null || val.trim().isEmpty ? 'Required' : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _sending || !hasRecipients
                    ? null
                    : () => _sendMail(user),
                icon: const Icon(Icons.send_rounded),
                label: const Text('Send mail'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatComposer(
    BuildContext context,
    User user,
    List<QueryDocumentSnapshot> userDocs,
    List<QueryDocumentSnapshot> staffDocs,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final recipients = _visibleRecipients(
      userDocs,
      staffDocs,
      user.uid,
      _chatQuery,
    );

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border(
              bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
          ),
          child: TextField(
            controller: _chatSearchController,
            onChanged: (value) => _onQueryChanged(value, 'chat'),
            decoration: const InputDecoration(
              hintText: 'Search by name, role, group or student ID',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        ),
        Expanded(
          child: recipients.isEmpty
              ? Center(
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
                          'Try another name, role, group or student ID.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: recipients.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    indent: 76,
                    color: scheme.outlineVariant.withValues(alpha: 0.2),
                  ),
                  itemBuilder: (context, index) {
                    final recipient = recipients[index];
                    return _buildRecipientTile(
                      context,
                      recipient,
                      onTap: () => _openChat(recipient, user),
                    );
                  },
                ),
        ),
      ],
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
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').snapshots(),
        builder: (context, usersSnapshot) {
          if (!usersSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('staff').snapshots(),
            builder: (context, staffSnapshot) {
              if (!staffSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final userDocs = usersSnapshot.data!.docs;
              final staffDocs = staffSnapshot.data!.docs;
              if (widget.isChat) {
                return _buildChatComposer(context, user, userDocs, staffDocs);
              }

              return _buildMailComposer(context, user, userDocs, staffDocs);
            },
          );
        },
      ),
    );
  }
}
