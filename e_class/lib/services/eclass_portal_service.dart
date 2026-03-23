import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html_parser;
import 'package:path_provider/path_provider.dart';

class EclassLoginResult {
  const EclassLoginResult({
    required this.ok,
    required this.fullName,
    required this.studentId,
    required this.ownerEmail,
    required this.note,
  });

  final bool ok;
  final String fullName;
  final String studentId;
  final String ownerEmail;
  final String note;
}

class EclassCourse {
  const EclassCourse({required this.title, required this.url});

  final String title;
  final String url;
}

class EclassAssignment {
  const EclassAssignment({
    required this.title,
    required this.url,
    required this.meta,
    required this.weekLabel,
  });

  final String title;
  final String url;
  final String meta;
  final String weekLabel;
}

class EclassFileLink {
  const EclassFileLink({required this.name, required this.url});

  final String name;
  final String url;
}

class EclassPortalService {
  EclassPortalService();

  final HttpClient _client = HttpClient();
  final Map<String, String> _cookieJar = <String, String>{};

  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;

  static final Uri _loginPageUri = Uri.parse(
    'https://eclass.inha.ac.kr/login.php',
  );
  static final Uri _myPageUri = Uri.parse('https://eclass.inha.ac.kr/my/');
  static final Uri _rootPageUri = Uri.parse('https://eclass.inha.ac.kr/');
  static final Uri _myCoursePageUri = Uri.parse(
    'https://eclass.inha.ac.kr/local/ubion/user/',
  );

  Future<EclassLoginResult> login({
    required String username,
    required String password,
  }) async {
    _client.connectionTimeout = const Duration(seconds: 25);
    _client.userAgent = 'Mozilla/5.0 (Android) Eclass Inha App';
    _cookieJar.clear();

    final loginPage = await _getText(_loginPageUri);
    final loginForm = _parseLoginForm(loginPage.body);
    if (loginForm == null) {
      return const EclassLoginResult(
        ok: false,
        fullName: '',
        studentId: '',
        ownerEmail: '',
        note: 'Login form not found',
      );
    }

    final formBody = <String, String>{
      ...loginForm.hiddenFields,
      'username': username,
      'password': password,
      'loginbutton': 'Log in',
      'rememberusername': '1',
    };

    final loginResponse = await _postForm(
      loginForm.actionUri,
      formBody,
      referer: _loginPageUri,
    );

    final loginError = _extractLoginError(loginResponse.body);
    if (loginError.isNotEmpty) {
      _isAuthenticated = false;
      return EclassLoginResult(
        ok: false,
        fullName: '',
        studentId: username,
        ownerEmail: '',
        note: loginError,
      );
    }

    final myResponse = await _getText(_rootPageUri);
    final myHtml = myResponse.body;
    final loginStillVisible =
        myHtml.contains('name="username"') &&
        myHtml.contains('name="password"');
    if (loginStillVisible) {
      _isAuthenticated = false;
      return EclassLoginResult(
        ok: false,
        fullName: '',
        studentId: username,
        ownerEmail: '',
        note: 'Still on login page (HTTP ${myResponse.statusCode})',
      );
    }

    final fullName = _extractFullName(myHtml);
    var studentId = _extractStudentId(myHtml, fallback: username);
    var ownerEmail = '';

    final profileUri = _extractProfileEditUri(myHtml);
    var resolvedName = fullName;
    if (profileUri != null) {
      final profile = await _getText(profileUri);
      final pName = _extractProfileName(profile.body);
      final pId = _extractStudentId(profile.body, fallback: studentId);
      final pEmail = _extractProfileEmail(profile.body);
      if (pName.isNotEmpty) {
        resolvedName = pName;
      }
      studentId = pId;
      ownerEmail = pEmail;
    }

    _isAuthenticated = true;
    return EclassLoginResult(
      ok: true,
      fullName: _normalizePersonName(resolvedName),
      studentId: studentId,
      ownerEmail: ownerEmail,
      note: '',
    );
  }

  Future<List<EclassAssignment>> fetchCourseAssignments(
    EclassCourse course,
  ) async {
    // 1. Get structured content (Assignments+Materials) with proper Week info from main page
    final structure = await fetchCourseContentFromMainPage(course.url);

    // 2. Get Assignment Metadata (Due dates) from assignment index
    final assignmentDetails = await fetchAssignmentsForCourse(course.url);
    final detailsMap = {for (var e in assignmentDetails) e.url: e.meta};

    final result = <EclassAssignment>[];
    final seen = <String>{};

    // Add structured items first (they have definitive Week info)
    for (final item in structure) {
      if (!seen.add(item.url)) continue;

      var meta = item.meta;
      if (detailsMap.containsKey(item.url)) {
        final details = detailsMap[item.url]!;
        // If we have detailed meta, prefer it over generic "Assignment" label
        // but try to keep it clean.
        meta = details.isNotEmpty ? details : meta;
      }

      result.add(
        EclassAssignment(
          title: item.title,
          url: item.url,
          meta: meta,
          weekLabel: item.weekLabel,
        ),
      );
    }

    // Add unmatched assignments (orphans) that weren't on the main page logic
    for (final item in assignmentDetails) {
      if (!seen.contains(item.url)) {
        seen.add(item.url);
        result.add(item);
      }
    }

    return result;
  }

  Future<List<EclassCourse>> fetchCourses() async {
    final result = <EclassCourse>[];
    final seen = <String>{};

    final sources = <Uri>[_myCoursePageUri, _rootPageUri, _myPageUri];
    for (final source in sources) {
      final page = await _getText(source);
      final doc = html_parser.parse(page.body);

      for (final a in doc.querySelectorAll('a[href]')) {
        final href = (a.attributes['href'] ?? '').trim();
        if (!href.contains('/course/view.php?id=')) continue;

        final url = _absoluteUrl(href);
        if (seen.contains(url)) continue;

        final title = _normalizeWhitespace(a.text);
        if (title.isEmpty) continue;

        seen.add(url);
        result.add(EclassCourse(title: title, url: url));
      }

      if (result.isNotEmpty) {
        break;
      }
    }

    return result;
  }

  Future<List<EclassAssignment>> fetchAssignmentsForCourse(
    String courseUrl,
  ) async {
    final result = <EclassAssignment>[];
    final seen = <String>{};

    final courseUri = Uri.parse(courseUrl);
    final courseId = courseUri.queryParameters['id'] ?? '';

    if (courseId.isNotEmpty) {
      final indexUri = Uri.parse(
        'https://eclass.inha.ac.kr/mod/assign/index.php?id=$courseId',
      );
      final indexPage = await _getText(indexUri);
      final indexDoc = html_parser.parse(indexPage.body);

      for (final row in indexDoc.querySelectorAll('table tbody tr')) {
        final a = row.querySelector('a[href*="/mod/assign/view.php?id="]');
        if (a == null) continue;

        final href = (a.attributes['href'] ?? '').trim();
        if (href.isEmpty) continue;

        final url = _absoluteUrl(href);
        if (!seen.add(url)) continue;

        final title = _normalizeWhitespace(a.text);
        if (title.isEmpty) continue;

        final cells = row
            .querySelectorAll('td')
            .map((td) => _normalizeWhitespace(td.text))
            .where((v) => v.isNotEmpty)
            .toList();

        final week = cells.isNotEmpty ? cells.first : '';
        final due = cells.length >= 3 ? cells[2] : '';
        final submission = cells.length >= 4 ? cells[3] : '';
        final grade = cells.length >= 5 ? cells[4] : '';

        final parts = <String>[];
        if (week.isNotEmpty) parts.add(week);
        if (due.isNotEmpty) parts.add('Due: $due');
        if (submission.isNotEmpty) parts.add('Submission: $submission');
        if (grade.isNotEmpty) parts.add('Grade: $grade');

        result.add(
          EclassAssignment(
            title: title,
            url: url,
            meta: parts.join(' | '),
            weekLabel: week,
          ),
        );
      }
    }

    if (result.isNotEmpty) return result;

    final page = await _getText(courseUri);
    final doc = html_parser.parse(page.body);

    for (final a in doc.querySelectorAll('a[href]')) {
      final href = (a.attributes['href'] ?? '').trim();
      if (!href.contains('/mod/assign/view.php?id=')) continue;

      final url = _absoluteUrl(href);
      if (!seen.add(url)) continue;

      final title = _normalizeWhitespace(a.text);
      if (title.isEmpty) continue;

      final parent = a.parent?.text ?? '';
      final meta = _normalizeWhitespace(parent.replaceAll(a.text, ''));
      result.add(
        EclassAssignment(title: title, url: url, meta: meta, weekLabel: ''),
      );
    }

    return result;
  }

  Future<List<EclassAssignment>> fetchCourseContentFromMainPage(
    String courseUrl,
  ) async {
    final page = await _getText(Uri.parse(courseUrl));
    final doc = html_parser.parse(page.body);

    final result = <EclassAssignment>[];
    final seen = <String>{};

    final sections = doc.querySelectorAll(
      'li[id^="section-"], li.section, section',
    );
    for (final section in sections) {
      final headerText = _normalizeWhitespace(
        section
                .querySelector(
                  'h3.sectionname, .sectionname, .course-section-header h3',
                )
                ?.text ??
            '',
      );
      final sectionText = _normalizeWhitespace(section.text);
      final weekSource = headerText.isNotEmpty ? headerText : sectionText;

      var weekNum = '';
      final match1 = RegExp(
        r'(\d+)\s*week',
        caseSensitive: false,
      ).firstMatch(weekSource);
      if (match1 != null) {
        weekNum = match1.group(1) ?? '';
      } else {
        final match2 = RegExp(
          r'week\s*(\d+)',
          caseSensitive: false,
        ).firstMatch(weekSource);
        if (match2 != null) {
          weekNum = match2.group(1) ?? '';
        }
      }

      final weekLabel = weekNum.isNotEmpty ? 'Week $weekNum' : '';

      for (final a in section.querySelectorAll('a[href]')) {
        final href = (a.attributes['href'] ?? '').trim();
        if (href.isEmpty) continue;

        final isMaterial =
            href.contains('/mod/resource/view.php') ||
            href.contains('/mod/folder/view.php') ||
            href.contains('/mod/url/view.php') ||
            href.contains('/pluginfile.php/') ||
            href.contains('/mod/assign/view.php') ||
            href.contains('/mod/ubfile/view.php');

        if (!isMaterial) continue;

        final url = _absoluteUrl(href);
        if (!seen.add(url)) continue;

        final title = _normalizeWhitespace(a.text);
        if (title.isEmpty) continue;

        var type = 'Material';
        if (href.contains('/mod/assign/view.php')) type = 'Assignment';
        if (href.contains('/mod/folder/view.php')) type = 'Folder';
        if (href.contains('/mod/ubfile/view.php')) type = 'File';
        if (href.contains('/mod/resource/view.php')) type = 'File';

        final item = EclassAssignment(
          title: title,
          url: url,
          meta: type,
          weekLabel: weekLabel,
        );
        result.add(item);

        // Expand folder entries into direct file items so presentations/docs are visible immediately.
        if (href.contains('/mod/folder/view.php')) {
          final folderFiles = await fetchAssignmentFiles(url);
          for (final file in folderFiles) {
            if (!seen.add(file.url)) continue;
            result.add(
              EclassAssignment(
                title: file.name,
                url: file.url,
                meta: 'File in folder',
                weekLabel: weekLabel,
              ),
            );
          }
        }
      }
    }

    return result;
  }

  Future<List<EclassFileLink>> fetchAssignmentFiles(
    String assignmentUrl,
  ) async {
    final page = await _getText(Uri.parse(assignmentUrl));

    // If the response is not HTML, it's likely a direct file download.
    final contentType = (page.headers[HttpHeaders.contentTypeHeader] ?? '')
        .toLowerCase();
    final isHtml =
        contentType.contains('text/html') ||
        contentType.contains('application/xhtml');

    if (!isHtml && page.statusCode == 200) {
      final url = page.finalUri?.toString() ?? assignmentUrl;
      var name = 'File';

      // If disposition is present, extract filename
      final disposition = page.headers['content-disposition'];
      if (disposition != null) {
        final match = RegExp(
          r'filename="?([^";]+)"?',
          caseSensitive: false,
        ).firstMatch(disposition);
        if (match != null) {
          name = match.group(1) ?? 'File';
        }
      } else {
        // Fallback to URL path
        final uri = Uri.parse(url);
        if (uri.pathSegments.isNotEmpty) {
          name = Uri.decodeComponent(uri.pathSegments.last);
        }
      }

      return [EclassFileLink(name: name, url: url)];
    }

    final doc = html_parser.parse(page.body);

    final files = <EclassFileLink>[];
    final seen = <String>{};

    for (final a in doc.querySelectorAll('a[href]')) {
      final href = (a.attributes['href'] ?? '').trim();
      if (href.isEmpty) continue;

      final match =
          href.contains('/pluginfile.php/') ||
          href.contains('/mod/resource/view.php') ||
          href.contains('/mod/folder/view.php') ||
          href.contains('/mod/url/view.php') ||
          href.contains('/mod/ubfile/');
      if (!match) continue;

      final url = _absoluteUrl(href);
      if (!seen.add(url)) continue;

      final normalizedName = _normalizeWhitespace(a.text);
      final name = normalizedName.isEmpty
          ? 'File ${files.length + 1}'
          : normalizedName;
      files.add(EclassFileLink(name: name, url: url));
    }

    return files;
  }

  Future<String> downloadFile({
    required String fileUrl,
    String? preferredName,
    String? refererUrl,
    String? targetDirectory,
  }) async {
    final referer = (refererUrl ?? '').trim().isNotEmpty
        ? Uri.parse(refererUrl!)
        : null;
    final response = await _sendWithRedirects(
      method: 'GET',
      uri: Uri.parse(fileUrl),
      referer: referer,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Download failed: HTTP ${response.statusCode}');
    }

    final textBody = response.body.toLowerCase();
    final looksLikeHtml =
        textBody.contains('<html') ||
        textBody.contains('<!doctype html') ||
        textBody.contains('name="username"');
    if (looksLikeHtml) {
      throw Exception(
        'Download failed: server returned an HTML page instead of a file',
      );
    }

    final fallbackName = Uri.parse(fileUrl).pathSegments.isNotEmpty
        ? Uri.decodeComponent(Uri.parse(fileUrl).pathSegments.last)
        : 'download.bin';
    final fileName = _sanitizeFileName(
      _normalizeWhitespace(preferredName ?? '').isNotEmpty
          ? preferredName!
          : fallbackName,
    );

    final targetDirs = <Directory>[];

    if (targetDirectory != null) {
      targetDirs.add(Directory(targetDirectory));
    } else {
      if (Platform.isAndroid) {
        // Prefer the shared Downloads folder visible to the user.
        targetDirs.add(Directory('/storage/emulated/0/Download'));
      }

      final platformDownloads = await getDownloadsDirectory();
      if (platformDownloads != null) {
        targetDirs.add(platformDownloads);
      }

      final docsDir = await getApplicationDocumentsDirectory();
      targetDirs.add(
        Directory('${docsDir.path}${Platform.pathSeparator}eclass_downloads'),
      );
    }

    Object? lastError;
    for (final dir in targetDirs) {
      try {
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }

        final filePath = '${dir.path}${Platform.pathSeparator}$fileName';
        final file = File(filePath);
        await file.writeAsBytes(response.bytes, flush: true);
        if (file.existsSync() && file.lengthSync() > 0) {
          return file.path;
        }
      } catch (e) {
        lastError = e;
      }
    }

    throw Exception(
      'Download failed: could not write file to Downloads or app storage${lastError != null ? ' ($lastError)' : ''}',
    );
  }

  Future<_PortalResponse> _getText(Uri uri) {
    return _sendWithRedirects(method: 'GET', uri: uri);
  }

  Future<_PortalResponse> _postForm(
    Uri uri,
    Map<String, String> formBody, {
    Uri? referer,
  }) {
    final body = formBody.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');

    return _sendWithRedirects(
      method: 'POST',
      uri: uri,
      body: body,
      contentType: 'application/x-www-form-urlencoded',
      referer: referer,
    );
  }

  Future<_PortalResponse> _sendWithRedirects({
    required String method,
    required Uri uri,
    Uri? referer,
    String? body,
    String? contentType,
  }) async {
    var currentMethod = method;
    var currentUri = uri;
    var currentBody = body;
    Uri? currentReferer = referer;

    for (var i = 0; i < 8; i += 1) {
      final request = currentMethod == 'POST'
          ? await _client.postUrl(currentUri)
          : await _client.getUrl(currentUri);

      request.followRedirects = false;
      _applyCommonHeaders(request, uri: currentUri, referer: currentReferer);

      if (currentMethod == 'POST' && currentBody != null) {
        if (contentType != null) {
          request.headers.set(HttpHeaders.contentTypeHeader, contentType);
        }
        request.add(utf8.encode(currentBody));
      }

      final response = await request.close();
      _saveCookies(response);

      final bytes = await response.fold<List<int>>(
        <int>[],
        (p, e) => p..addAll(e),
      );

      if (response.isRedirect ||
          response.statusCode == HttpStatus.movedTemporarily ||
          response.statusCode == HttpStatus.movedPermanently ||
          response.statusCode == HttpStatus.seeOther ||
          response.statusCode == HttpStatus.temporaryRedirect ||
          response.statusCode == HttpStatus.permanentRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null || location.isEmpty) {
          return _PortalResponse(statusCode: response.statusCode, bytes: bytes);
        }

        currentReferer = currentUri;
        currentUri = currentUri.resolve(location);

        if (response.statusCode != HttpStatus.temporaryRedirect &&
            response.statusCode != HttpStatus.permanentRedirect) {
          currentMethod = 'GET';
          currentBody = null;
        }
        continue;
      }

      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name.toLowerCase()] = values.join(', ');
      });

      return _PortalResponse(
        statusCode: response.statusCode,
        bytes: bytes,
        headers: responseHeaders,
        finalUri: currentUri,
      );
    }

    return const _PortalResponse(statusCode: 599, bytes: <int>[]);
  }

  void _saveCookies(HttpClientResponse response) {
    for (final cookie in response.cookies) {
      _cookieJar[cookie.name] = cookie.value;
    }
  }

  void _applyCommonHeaders(
    HttpClientRequest request, {
    required Uri uri,
    Uri? referer,
  }) {
    request.headers.set(
      HttpHeaders.acceptHeader,
      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    );
    request.headers.set(HttpHeaders.acceptLanguageHeader, 'en-US,en;q=0.9');
    request.headers.set('Origin', '${uri.scheme}://${uri.host}');

    if (referer != null) {
      request.headers.set(HttpHeaders.refererHeader, referer.toString());
    }

    if (_cookieJar.isNotEmpty) {
      final cookieHeader = _cookieJar.entries
          .map((e) => '${e.key}=${e.value}')
          .join('; ');
      request.headers.set(HttpHeaders.cookieHeader, cookieHeader);
    }
  }

  _LoginFormInfo? _parseLoginForm(String html) {
    final doc = html_parser.parse(html);
    final form =
        doc.querySelector('form.mform.form-login') ?? doc.querySelector('form');
    if (form == null) return null;

    final actionRaw = (form.attributes['action'] ?? '').trim();
    if (actionRaw.isEmpty) return null;

    final hidden = <String, String>{};
    for (final input in form.querySelectorAll('input[type="hidden"]')) {
      final name = (input.attributes['name'] ?? '').trim();
      if (name.isEmpty) continue;
      hidden[name] = input.attributes['value'] ?? '';
    }

    return _LoginFormInfo(
      actionUri: Uri.parse(_absoluteUrl(actionRaw)),
      hiddenFields: hidden,
    );
  }

  String _extractLoginError(String html) {
    final doc = html_parser.parse(html);
    const selectors = <String>[
      '.alert-danger',
      '.loginerrors',
      '.errormessage',
      '[data-region="login-errors"]',
    ];

    for (final s in selectors) {
      final text = _normalizeWhitespace(doc.querySelector(s)?.text ?? '');
      if (text.isNotEmpty) return text;
    }

    final lowered = html.toLowerCase();
    if (lowered.contains('invalid login')) return 'Invalid login';
    if (lowered.contains('incorrect')) return 'Incorrect credentials';
    return '';
  }

  String _extractFullName(String html) {
    final doc = html_parser.parse(html);
    const selectors = <String>[
      '.usertext',
      '.usermenu .login',
      '.page-header-headings h1',
      '.fullname',
      '[data-userfullname]',
    ];

    for (final s in selectors) {
      final value = _normalizeWhitespace(doc.querySelector(s)?.text ?? '');
      if (value.isNotEmpty && !_looksLikeNoise(value)) {
        return value;
      }
    }

    return '';
  }

  Uri? _extractProfileEditUri(String html) {
    final doc = html_parser.parse(html);
    for (final a in doc.querySelectorAll('a[href]')) {
      final href = (a.attributes['href'] ?? '').trim();
      final text = _normalizeWhitespace(a.text).toLowerCase();
      if (href.contains('/user/edit.php') ||
          href.contains('/user/user_edit.php')) {
        return Uri.parse(_absoluteUrl(href));
      }
      if (text.contains('update profile') && href.isNotEmpty) {
        return Uri.parse(_absoluteUrl(href));
      }
    }
    return null;
  }

  String _extractProfileName(String html) {
    final doc = html_parser.parse(html);
    final first = _normalizeWhitespace(
      doc.querySelector('input[name="firstname"]')?.attributes['value'] ?? '',
    );
    final last = _normalizeWhitespace(
      doc.querySelector('input[name="lastname"]')?.attributes['value'] ?? '',
    );

    if (first.isNotEmpty &&
        last.isNotEmpty &&
        first.toLowerCase() == last.toLowerCase()) {
      return first;
    }

    final combined = _normalizePersonName('$first $last');
    if (combined.isNotEmpty) return combined;

    final h2 = _normalizeWhitespace(doc.querySelector('h2')?.text ?? '');
    if (!_looksLikeNoise(h2)) return h2;

    return '';
  }

  String _extractProfileEmail(String html) {
    final doc = html_parser.parse(html);
    final direct = _normalizeWhitespace(
      doc.querySelector('input[name="email"]')?.attributes['value'] ?? '',
    );
    if (direct.isNotEmpty) return direct;

    final mailTo =
        doc.querySelector('a[href^="mailto:"]')?.attributes['href'] ?? '';
    if (mailTo.toLowerCase().startsWith('mailto:')) {
      final value = _normalizeWhitespace(mailTo.substring(7));
      if (value.isNotEmpty) return value;
    }

    return '';
  }

  String _extractStudentId(String html, {required String fallback}) {
    final direct = RegExp(r'\bU\d{7}\b').firstMatch(html);
    if (direct != null) return direct.group(0) ?? fallback;

    final generic = RegExp(r'\b\d{8,10}\b').firstMatch(html);
    if (generic != null) return generic.group(0) ?? fallback;

    return fallback;
  }

  String _normalizeWhitespace(String value) {
    return value
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _normalizePersonName(String value) {
    final normalized = _normalizeWhitespace(value);
    if (normalized.isEmpty) return '';

    final words = normalized.split(' ');
    if (words.length.isEven && words.length >= 2) {
      final half = words.length ~/ 2;
      final left = words.take(half).join(' ');
      final right = words.skip(half).join(' ');
      if (left.toLowerCase() == right.toLowerCase()) return left;
    }

    return normalized;
  }

  bool _looksLikeNoise(String value) {
    final lower = value.toLowerCase();
    return lower.contains('login') || lower.contains('cybercampus');
  }

  String _absoluteUrl(String href) {
    if (href.startsWith('http://') || href.startsWith('https://')) return href;
    if (href.startsWith('/')) return 'https://eclass.inha.ac.kr$href';
    return 'https://eclass.inha.ac.kr/$href';
  }

  String _sanitizeFileName(String value) {
    return value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  void dispose() {
    _client.close(force: true);
  }
}

class _LoginFormInfo {
  const _LoginFormInfo({required this.actionUri, required this.hiddenFields});

  final Uri actionUri;
  final Map<String, String> hiddenFields;
}

class _PortalResponse {
  const _PortalResponse({
    required this.statusCode,
    required this.bytes,
    this.headers = const {},
    this.finalUri,
  });

  final int statusCode;
  final List<int> bytes;
  final Map<String, String> headers;
  final Uri? finalUri;

  String get body => utf8.decode(bytes, allowMalformed: true);
}
