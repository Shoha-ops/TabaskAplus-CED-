import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:e_class/services/database_service.dart';
import 'package:http/http.dart' as http;

class StudyHelperService {
  StudyHelperService(this._db);

  final DatabaseService _db;

  static const String _model = 'qwen2.5:7b';

  Future<void> processMessage(String text) async {
    final prompt = await _buildPrompt(text);

    try {
      final response = await _generate(prompt);
      await _db.sendMessage(response, isBot: true);
    } catch (_) {
      await _db.sendMessage(
        'The helper is temporarily unavailable. Please try again a bit later.',
        isBot: true,
      );
    }
  }

  Future<String> _generate(String prompt) async {
    Object? lastError;

    for (final uri in _candidateUris()) {
      try {
        final response = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'model': _model,
                'prompt': prompt,
                'stream': false,
                'options': {
                  'temperature': 0.7,
                  'num_predict': 300,
                },
              }),
            )
            .timeout(const Duration(seconds: 60));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final text = (data['response'] as String?)?.trim() ?? '';
          if (text.isNotEmpty) return text;
        } else {
          lastError = 'HTTP ${response.statusCode}: ${response.body}';
        }
      } catch (error) {
        lastError = error;
      }
    }

    throw Exception('Request failed: $lastError');
  }

  List<Uri> _candidateUris() {
    if (Platform.isAndroid) {
      return [
        Uri.parse('http://10.0.2.2:11434/api/generate'),
        Uri.parse('http://127.0.0.1:11434/api/generate'),
      ];
    }

    return [
      Uri.parse('http://127.0.0.1:11434/api/generate'),
      Uri.parse('http://localhost:11434/api/generate'),
    ];
  }

  Future<String> _buildPrompt(String userMessage) async {
    final profile = await _loadProfile();
    final fullName = _resolveName(profile);
    final studentId = (profile?['studentId'] as String?)?.trim() ?? '';
    final faculty = (profile?['faculty'] as String?)?.trim() ?? '';
    final gpa = profile?['gpa']?.toString() ?? '';

    final context = <String>[
      'You are the built-in study helper inside a university student app.',
      'Answer naturally and helpfully.',
      'If profile data is missing, say that the app has no such data yet.',
      'Keep answers concise unless the user asks for detail.',
      if (fullName.isNotEmpty) 'Student name: $fullName',
      if (studentId.isNotEmpty) 'Student ID: $studentId',
      if (faculty.isNotEmpty) 'Faculty: $faculty',
      if (gpa.isNotEmpty) 'GPA: $gpa',
    ].join('\n');

    return '$context\n\nUser question: $userMessage';
  }

  Future<Map<String, dynamic>?> _loadProfile() async {
    try {
      final snapshot = await _db.userData.first;
      return snapshot.data() as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  String _resolveName(Map<String, dynamic>? data) {
    if (data == null) return '';

    final fullName = (data['fullName'] as String?)?.trim() ?? '';
    if (fullName.isNotEmpty) return fullName;

    final firstName = (data['firstName'] as String?)?.trim() ?? '';
    final lastName = (data['lastName'] as String?)?.trim() ?? '';
    final combined = '$firstName $lastName'.trim();
    if (combined.isNotEmpty) return combined;

    final name = (data['name'] as String?)?.trim() ?? '';
    if (name.isNotEmpty) return name;

    return (data['email'] as String?)?.trim() ?? '';
  }
}
