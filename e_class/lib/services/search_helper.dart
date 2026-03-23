class SearchHelper {
  static String normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String compact(String value) {
    return normalize(value).replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static List<String> tokenize(String value) {
    return normalize(
      value,
    ).split(RegExp(r'[^a-z0-9]+')).where((part) => part.isNotEmpty).toList();
  }

  static List<String> buildSearchKeywords({
    required String fullName,
    required String firstName,
    required String lastName,
    required String studentId,
    required String group,
    required String email,
  }) {
    final keywords = <String>{};

    void addPrefixes(String raw) {
      final normalized = normalize(raw);
      if (normalized.isEmpty) return;

      for (var i = 1; i <= normalized.length; i++) {
        keywords.add(normalized.substring(0, i));
      }

      final compacted = compact(raw);
      if (compacted.isNotEmpty && compacted != normalized) {
        for (var i = 1; i <= compacted.length; i++) {
          keywords.add(compacted.substring(0, i));
        }
      }

      for (final token in tokenize(raw)) {
        for (var i = 1; i <= token.length; i++) {
          keywords.add(token.substring(0, i));
        }
      }
    }

    for (final value in [
      fullName,
      firstName,
      lastName,
      studentId,
      group,
      email,
    ]) {
      addPrefixes(value);
    }

    return keywords.toList()..sort();
  }

  static String queryToken(String query) {
    final normalized = normalize(query);
    if (normalized.isEmpty) return '';

    final tokens = tokenize(query);
    final compacted = compact(query);
    if (!normalized.contains(' ') &&
        (normalized.contains('-') || normalized.contains('@')) &&
        compacted.isNotEmpty) {
      return normalized;
    }

    if (tokens.isEmpty) return compacted;
    tokens.sort((a, b) => b.length.compareTo(a.length));
    return tokens.first;
  }
}
