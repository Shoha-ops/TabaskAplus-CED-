import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:e_class/models/courses/course.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CoursesService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _staffCacheKey = 'courses_staff_cache_v1';
  static bool _staffDiskCacheLoaded = false;
  static final Map<String, Staff> _staffMemoryCache = {};
  static final Map<String, Map<String, dynamic>> _staffDiskCache = {};
  static Future<void>? _staffCacheLoadFuture;

  static Map<String, dynamic> _serializeStaff(Staff staff) {
    return {
      'id': staff.id,
      'name': staff.name,
      'avatarUrl': staff.avatarUrl,
      'role': staff.role,
      'assistantId': staff.assistantId,
      'officeHours': staff.officeHours
          .map(
            (hour) => {
              'day': hour.day,
              'time': hour.time,
              'location': hour.location,
            },
          )
          .toList(),
    };
  }

  static Staff? _deserializeStaff(String id, Map<String, dynamic> data) {
    final name = (data['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return null;

    final avatarUrl = (data['avatarUrl'] as String?)?.trim() ?? '';
    final role = (data['role'] as String?)?.trim().isNotEmpty == true
        ? (data['role'] as String).trim()
        : 'Professor';
    final assistantId = (data['assistantId'] as String?)?.trim() ?? '';
    final officeHoursRaw = data['officeHours'];
    final officeHours = <OfficeHour>[];
    if (officeHoursRaw is List) {
      for (final item in officeHoursRaw) {
        if (item is Map<String, dynamic>) {
          officeHours.add(OfficeHour.fromMap(item));
        } else if (item is Map) {
          officeHours.add(
            OfficeHour.fromMap(
              item.map((key, value) => MapEntry(key.toString(), value)),
            ),
          );
        }
      }
    }

    return Staff(
      id: id,
      name: name,
      avatarUrl: avatarUrl,
      role: role,
      assistantId: assistantId,
      officeHours: officeHours,
    );
  }

  static Future<void> _ensureStaffCacheLoaded() {
    if (_staffDiskCacheLoaded) {
      return Future.value();
    }
    _staffCacheLoadFuture ??= _loadStaffCacheFromDisk();
    return _staffCacheLoadFuture!;
  }

  static Future<void> _loadStaffCacheFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_staffCacheKey);
      if (raw == null || raw.isEmpty) {
        _staffDiskCacheLoaded = true;
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        _staffDiskCacheLoaded = true;
        return;
      }

      decoded.forEach((id, value) {
        if (value is! Map<String, dynamic>) return;
        _staffDiskCache[id] = value;
        final staff = _deserializeStaff(id, value);
        if (staff != null) {
          _staffMemoryCache[id] = staff;
        }
      });
    } catch (_) {
      // Ignore malformed cache and continue with network.
    } finally {
      _staffDiskCacheLoaded = true;
    }
  }

  static Future<void> _persistStaffCacheToDisk() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_staffCacheKey, jsonEncode(_staffDiskCache));
  }

  static Future<void> _saveStaffToCache(Staff staff) async {
    _staffMemoryCache[staff.id] = staff;
    _staffDiskCache[staff.id] = _serializeStaff(staff);
    await _persistStaffCacheToDisk();
  }

  Future<Staff?> _fetchStaffFromNetwork(String id) async {
    final doc = await _db.collection('staff').doc(id).get();
    if (!doc.exists || doc.data() == null) {
      return null;
    }
    final staff = Staff.fromFirestore(doc);
    await _saveStaffToCache(staff);
    return staff;
  }

  // Courses
  Stream<List<Course>> getCourses([String? semester]) {
    return _db.collection('subjects').snapshots().map((snapshot) {
      final courses = snapshot.docs
          .map((doc) => _courseFromSubjectDoc(doc))
          .where((course) {
            if (semester == null || semester.trim().isEmpty) {
              return true;
            }
            return _normalizeSemesterLabel(course.semester) ==
                _normalizeSemesterLabel(semester);
          })
          .toList();
      courses.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
      return courses;
    });
  }

  Future<Course> getCourse(String id) async {
    final doc = await _db.collection('subjects').doc(id).get();
    return _courseFromSubjectDoc(doc);
  }

  // Weeks
  Stream<List<Week>> getWeeks() {
    return _db.collection('weeks').orderBy('number').snapshots().map((
      snapshot,
    ) {
      return snapshot.docs.map((doc) => Week.fromFirestore(doc)).toList();
    });
  }

  Future<Week?> getCurrentWeek() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final snapshot = await _db.collection('weeks').get();

    final weeks = <Week>[];
    for (final doc in snapshot.docs) {
      try {
        final week = Week.fromFirestore(doc);
        if (week.number > 0) {
          weeks.add(week);
        }
      } catch (_) {
        // Skip malformed week documents instead of breaking current week detection.
      }
    }

    weeks.sort((a, b) => a.number.compareTo(b.number));

    for (final week in weeks) {
      final startDay = DateTime(
        week.startDate.year,
        week.startDate.month,
        week.startDate.day,
      );
      final endDay = DateTime(
        week.endDate.year,
        week.endDate.month,
        week.endDate.day,
      );
      final isAfterStart = !today.isBefore(startDay);
      final isBeforeEnd = !today.isAfter(endDay);
      if (isAfterStart && isBeforeEnd) {
        return week;
      }
    }

    return null;
  }

  // Staff
  Future<Staff?> getStaff(String id) async {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) {
      return null;
    }

    await _ensureStaffCacheLoaded();

    final memoryCached = _staffMemoryCache[normalizedId];
    if (memoryCached != null) {
      return memoryCached;
    }

    final diskCachedRaw = _staffDiskCache[normalizedId];
    if (diskCachedRaw != null) {
      final diskStaff = _deserializeStaff(normalizedId, diskCachedRaw);
      if (diskStaff != null) {
        _staffMemoryCache[normalizedId] = diskStaff;
        return diskStaff;
      }
    }

    return _fetchStaffFromNetwork(normalizedId);
  }

  // Announcements
  Stream<List<Announcement>> getAnnouncements(String courseId, int weekNumber) {
    return _db.collection('subjects').snapshots().map((snapshot) {
      DocumentSnapshot<Map<String, dynamic>>? matched;

      for (final doc in snapshot.docs) {
        if (_courseFromSubjectDoc(doc).id == courseId) {
          matched = doc;
          break;
        }
      }

      if (matched == null || matched.data() == null) {
        return const <Announcement>[];
      }

      final data = matched.data()!;
      final raw = data['announcements'];
      if (raw is! List) {
        return const <Announcement>[];
      }

      final items = <Announcement>[];
      for (var i = 0; i < raw.length; i += 1) {
        final item = raw[i];
        if (item is! Map) continue;

        final map = item.map((key, value) => MapEntry(key.toString(), value));
        final itemId = (map['id'] ?? '${matched.id}_$i').toString();
        final title = (map['title'] ?? '').toString().trim();
        if (title.isEmpty) continue;

        final content = (map['content'] ?? map['description'] ?? '')
            .toString()
            .trim();
        final dateRaw = map['createdAt'] ?? map['date'] ?? map['publishedAt'];
        final date = _parseDateFlexible(dateRaw);
        final deadline = _parseDateFlexibleOrNull(
          map['deadline'] ?? map['dueDate'],
        );
        final itemWeek = _resolveAnnouncementWeek(map, itemId);

        if (itemWeek != weekNumber) {
          continue;
        }

        items.add(
          Announcement(
            id: itemId,
            courseId: matched.id,
            weekNumber: itemWeek,
            title: title,
            content: content,
            date: date,
            deadline: deadline,
          ),
        );
      }

      items.sort((a, b) => b.date.compareTo(a.date));
      return items;
    });
  }

  // Materials
  Stream<List<CourseMaterial>> getMaterials(String courseId, int weekNumber) {
    return _db.collection('subjects').snapshots().map((snapshot) {
      DocumentSnapshot<Map<String, dynamic>>? matched;

      for (final doc in snapshot.docs) {
        if (_courseFromSubjectDoc(doc).id == courseId) {
          matched = doc;
          break;
        }
      }

      if (matched == null || matched.data() == null) {
        return const <CourseMaterial>[];
      }

      final data = matched.data()!;
      final raw = data['materials'];
      if (raw is! List) {
        return const <CourseMaterial>[];
      }

      final items = <CourseMaterial>[];
      for (var i = 0; i < raw.length; i += 1) {
        final item = raw[i];
        if (item is! Map) continue;

        final map = item.map((key, value) => MapEntry(key.toString(), value));
        final itemId = (map['id'] ?? '${matched.id}_m$i').toString();
        final itemWeek = _resolveMaterialWeek(map, itemId);
        if (itemWeek != weekNumber) continue;

        final title = (map['title'] ?? '').toString().trim();
        if (title.isEmpty) continue;

        final type = (map['type'] ?? '').toString().trim();
        final url = (map['url'] ?? '').toString().trim();
        final deadline = _parseDateFlexibleOrNull(
          map['deadline'] ?? map['dueDate'],
        );

        items.add(
          CourseMaterial(
            id: itemId,
            courseId: courseId,
            weekNumber: itemWeek,
            title: title,
            type: type,
            url: url,
            deadline: deadline,
          ),
        );
      }

      items.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
      return items;
    });
  }

  // Sync Data
  Future<void> syncData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _ensureWeeks();

    final userDoc = await _db.collection('users').doc(user.uid).get();
    final group = (userDoc.data()?['group'] as String?)?.trim() ?? '';
    if (group.isEmpty) return;

    final scheduleSnapshot = await _db
        .collection('groups')
        .doc(group)
        .collection('schedule')
        .get();

    final subjectsSnapshot = await _db.collection('subjects').get();
    final Map<String, Map<String, dynamic>> subjectsByCode = {};
    final Map<String, Map<String, dynamic>> subjectsByTitle = {};
    for (final subjectDoc in subjectsSnapshot.docs) {
      final subjectData = subjectDoc.data();
      final idCode = subjectDoc.id.trim().toUpperCase();
      final dataCode = (subjectData['code'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      final title = (subjectData['title'] ?? '').toString().trim();

      if (idCode.isNotEmpty) {
        subjectsByCode[idCode] = subjectData;
      }
      if (dataCode.isNotEmpty) {
        subjectsByCode[dataCode] = subjectData;
      }
      if (title.isNotEmpty) {
        subjectsByTitle[_normalizeTitleKey(title)] = subjectData;
      }
    }

    final scheduleRows = <Map<String, dynamic>>[
      ...scheduleSnapshot.docs.map((doc) => doc.data()),
    ];

    final legacyRows = await _loadLegacyScheduleRows(
      group: group,
      subjectsByCode: subjectsByCode,
    );
    scheduleRows.addAll(legacyRows);

    if (scheduleRows.isEmpty) return;

    final dedup = <String>{};
    final normalizedRows = <Map<String, dynamic>>[];
    for (final row in scheduleRows) {
      final subjectKey =
          (row['subjectCode'] ?? row['subject'] ?? row['subjectTitle'] ?? '')
              .toString()
              .trim()
              .toUpperCase();
      final teacherKey = (row['teacher'] ?? row['professor'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      final semesterKey = (row['semester'] ?? row['term'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      final key = '$subjectKey|$teacherKey|$semesterKey';
      if (dedup.contains(key)) continue;
      dedup.add(key);
      normalizedRows.add(row);
    }

    for (final data in normalizedRows) {
      String subjectCode = (data['subjectCode'] ?? data['subject'] ?? '')
          .toString()
          .trim();
      String subjectTitle =
          (data['subjectTitle'] ?? data['courseName'] ?? data['title'] ?? '')
              .toString()
              .trim();

      final subjectData = _resolveSubjectData(
        subjectCode: subjectCode,
        subjectTitle: subjectTitle,
        subjectsByCode: subjectsByCode,
        subjectsByTitle: subjectsByTitle,
      );

      final teacherName = _pickFirstText(data, const [
        'teacher',
        'professor',
        'teacherName',
        'professorName',
        'instructor',
        'lecturer',
        'teacher_name',
        'professor_name',
        'instructor_name',
      ], fallback: subjectData);
      final professorId = teacherName.isEmpty ? '' : _toDocId(teacherName);

      if (teacherName.isNotEmpty) {
        await _db.collection('staff').doc(professorId).set({
          'name': teacherName,
          'role': 'Professor',
          'avatarUrl':
              'https://ui-avatars.com/api/?name=${Uri.encodeComponent(teacherName)}&background=1f6feb&color=fff',
          'officeHours': _defaultOfficeHours(
            'B-${100 + (teacherName.length % 20)}',
          ),
        }, SetOptions(merge: true));
      }

      final assistantName = _pickFirstText(data, const [
        'assistant',
        'assistantName',
        'assistant_name',
        'teachingAssistant',
        'teaching_assistant',
        'teacherAssistant',
        'ta',
        'taName',
        'ta_name',
      ], fallback: subjectData);

      final assistantIdRaw = _pickFirstText(data, const [
        'assistantId',
        'assistant_id',
        'taId',
        'ta_id',
      ], fallback: subjectData);

      final normalizedTeacher = teacherName.trim().toLowerCase();
      final normalizedAssistant = assistantName.trim().toLowerCase();
      final assistantIsSameAsTeacher =
          normalizedAssistant.isNotEmpty &&
          normalizedAssistant == normalizedTeacher;
      final normalizedAssistantIdRaw = assistantIdRaw.trim().toLowerCase();
      final assistantIdFromRaw = normalizedAssistantIdRaw.isEmpty
          ? ''
          : _toDocId(normalizedAssistantIdRaw);

      final assistantIdFromName =
          (assistantName.isEmpty || assistantIsSameAsTeacher)
          ? ''
          : '${_toDocId(assistantName)}_assistant';

      var assistantId = assistantIdFromRaw.isNotEmpty
          ? assistantIdFromRaw
          : assistantIdFromName;

      if (assistantId == professorId) {
        assistantId = '';
      }

      if (assistantName.isNotEmpty && assistantId.isNotEmpty) {
        await _db.collection('staff').doc(assistantId).set({
          'name': assistantName,
          'role': 'Assistant',
          'avatarUrl':
              'https://ui-avatars.com/api/?name=${Uri.encodeComponent(assistantName)}&background=7f8c8d&color=fff',
          'officeHours': _defaultOfficeHours(
            'A-${200 + (assistantName.length % 20)}',
          ),
        }, SetOptions(merge: true));
      }

      if (subjectCode.isNotEmpty && subjectTitle.isEmpty) {
        subjectTitle =
            (subjectData?['title'] as String?)?.trim() ?? subjectTitle;
      }

      if (subjectCode.isEmpty && subjectTitle.isNotEmpty) {
        final sanitized = subjectTitle
            .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
            .toUpperCase();
        subjectCode = sanitized.length > 4
            ? sanitized.substring(0, 4)
            : sanitized;
      }

      if (subjectTitle.isEmpty) {
        subjectTitle = subjectCode;
      }
      if (subjectTitle.isEmpty) {
        continue;
      }

      final courseId = (subjectCode.isNotEmpty ? subjectCode : subjectTitle)
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '_');
      final semesterLabel = _resolveSemesterFromData(
        data,
        fallback: subjectData,
      );
      if (subjectCode.isNotEmpty) {
        await _db.collection('subjects').doc(subjectCode).set({
          'code': subjectCode,
          'title': subjectTitle,
          'icon': _resolveIcon(subjectTitle),
          'professorId': professorId,
          'professorName': teacherName,
          'semester': semesterLabel,
        }, SetOptions(merge: true));
      }

      await _seedCourseContent(
        subjectDocId: subjectCode.isNotEmpty ? subjectCode : courseId,
        courseId: courseId,
        courseTitle: subjectTitle,
      );
    }
  }

  Course _courseFromSubjectDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final code = (data['code'] ?? doc.id).toString().trim().toUpperCase();
    final title = (data['title'] ?? '').toString().trim();
    final professorName = (data['professorName'] ?? '').toString().trim();
    final professorId = (data['professorId'] ?? '').toString().trim();
    final semester = _normalizeSemesterLabel(
      (data['semester'] ?? data['term'] ?? '').toString(),
    );

    final resolvedTitle = title.isEmpty ? code : title;
    final resolvedId = code.isNotEmpty
        ? code.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')
        : doc.id.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');

    return Course(
      id: resolvedId,
      title: resolvedTitle,
      icon: (data['icon'] ?? _resolveIcon(resolvedTitle)).toString(),
      professorId: professorId,
      professorName: professorName,
      semester: semester.isEmpty ? 'Spring 2026' : semester,
    );
  }

  Future<List<Map<String, dynamic>>> _loadLegacyScheduleRows({
    required String group,
    required Map<String, Map<String, dynamic>> subjectsByCode,
  }) async {
    final rows = <Map<String, dynamic>>[];

    final seenCollections = <String>{};
    final legacyCollectionNames = <String>[];
    for (final code in subjectsByCode.keys) {
      final trimmed = code.trim();
      if (trimmed.isEmpty) continue;
      if (seenCollections.add(trimmed)) {
        legacyCollectionNames.add(trimmed);
      }
    }

    for (final collectionName in legacyCollectionNames) {
      QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await _db.collection(collectionName).get();
      } catch (_) {
        continue;
      }

      if (snapshot.docs.isEmpty) continue;

      for (final doc in snapshot.docs) {
        final data = doc.data();

        final groupValue = _pickFirstText(data, const [
          'group',
          'groupName',
          'groupId',
          'academicGroup',
          'classGroup',
        ]);
        if (groupValue.isNotEmpty &&
            groupValue.toUpperCase() != group.toUpperCase()) {
          continue;
        }

        final subjectCode = _pickFirstText(data, const [
          'subjectCode',
          'subject',
          'code',
        ]);
        final subjectTitle = _pickFirstText(data, const [
          'subjectTitle',
          'title',
          'courseName',
          'name',
        ], fallback: subjectsByCode[collectionName]);

        if (subjectCode.isEmpty && subjectTitle.isEmpty) {
          continue;
        }

        rows.add({
          ...data,
          'subjectCode': subjectCode.isNotEmpty ? subjectCode : collectionName,
          'subjectTitle': subjectTitle,
          'semester':
              _pickFirstText(data, const [
                'semester',
                'semesterName',
                'term',
                'termName',
                'semesterNumber',
                'termNumber',
              ]).isEmpty
              ? 'Fall 2025'
              : _pickFirstText(data, const [
                  'semester',
                  'semesterName',
                  'term',
                  'termName',
                  'semesterNumber',
                  'termNumber',
                ]),
          'professor': _pickFirstText(data, const [
            'professor',
            'teacher',
            'teacherName',
            'instructor',
          ]),
          'assistant': _pickFirstText(data, const [
            'assistant',
            'assistantName',
            'assistant_name',
            'teachingAssistant',
            'teaching_assistant',
            'teacherAssistant',
            'ta',
            'taName',
            'ta_name',
          ]),
        });
      }
    }

    return rows;
  }

  Future<void> _ensureWeeks() async {
    final DateTime semesterStart = DateTime(2026, 2, 7);
    final DateTime semesterEnd = DateTime(2026, 5, 29);

    for (int i = 1; i <= 16; i++) {
      final startDate = semesterStart.add(Duration(days: (i - 1) * 7));
      var endDate = startDate.add(const Duration(days: 6));
      if (endDate.isAfter(semesterEnd)) {
        endDate = semesterEnd;
      }

      final inclusiveEndDate = DateTime(
        endDate.year,
        endDate.month,
        endDate.day,
        23,
        59,
        59,
      );

      await _db.collection('weeks').doc('week_$i').set({
        'number': i,
        'startDate': Timestamp.fromDate(startDate),
        'endDate': Timestamp.fromDate(inclusiveEndDate),
      }, SetOptions(merge: true));
    }
  }

  Future<void> _seedCourseContent({
    required String subjectDocId,
    required String courseId,
    required String courseTitle,
  }) async {
    final DateTime semesterStart = DateTime(2026, 2, 7);

    final subjectDoc = await _db.collection('subjects').doc(subjectDocId).get();
    final subjectData = subjectDoc.data() ?? {};
    final existingRaw = subjectData['announcements'];
    final existing = existingRaw is List ? existingRaw : const [];
    if (existing.isEmpty) {
      await _db.collection('subjects').doc(subjectDocId).set({
        'announcements': [
          {
            'id': '${courseId}_w1_a1',
            'title': 'Course started',
            'content':
                'Welcome to $courseTitle. Please check materials and weekly plan.',
            'createdAt': Timestamp.fromDate(semesterStart),
          },
        ],
      }, SetOptions(merge: true));
    }

    final existingMaterialsRaw = subjectData['materials'];
    final existingMaterials = existingMaterialsRaw is List
        ? existingMaterialsRaw
        : const [];
    if (existingMaterials.isEmpty) {
      final seeded = <Map<String, dynamic>>[];
      for (int week = 1; week <= 16; week++) {
        seeded.add({
          'id': '${courseId}_w${week}_lecture',
          'weekNumber': week,
          'title': 'Lecture $week: Core Concepts',
          'type': 'lecture',
          'url': 'https://example.com/$courseId/lecture-$week',
          'createdAt': Timestamp.fromDate(
            semesterStart.add(Duration(days: (week - 1) * 7)),
          ),
        });
        seeded.add({
          'id': '${courseId}_w${week}_homework',
          'weekNumber': week,
          'title': 'Homework $week',
          'type': 'homework',
          'url': 'https://example.com/$courseId/homework-$week',
          'createdAt': Timestamp.fromDate(
            semesterStart.add(Duration(days: (week - 1) * 7)),
          ),
        });
      }

      await _db.collection('subjects').doc(subjectDocId).set({
        'materials': seeded,
      }, SetOptions(merge: true));
    }
  }

  DateTime _parseDateFlexible(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is int) {
      final millis = raw < 1000000000000 ? raw * 1000 : raw;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }
    return DateTime(1970, 1, 1);
  }

  DateTime? _parseDateFlexibleOrNull(dynamic raw) {
    if (raw == null) return null;
    if (raw is String && raw.trim().isEmpty) return null;
    return _parseDateFlexible(raw);
  }

  int _resolveAnnouncementWeek(Map<String, dynamic> map, String itemId) {
    final explicit = map['weekNumber'];
    final parsedExplicit = explicit is int
        ? explicit
        : int.tryParse(explicit?.toString() ?? '');
    if (parsedExplicit != null && parsedExplicit > 0) {
      return parsedExplicit;
    }

    final match = RegExp(r'_w(\d+)_', caseSensitive: false).firstMatch(itemId);
    if (match != null) {
      final parsed = int.tryParse(match.group(1) ?? '');
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }

    return 1;
  }

  int _resolveMaterialWeek(Map<String, dynamic> map, String itemId) {
    final explicit = map['weekNumber'];
    final parsedExplicit = explicit is int
        ? explicit
        : int.tryParse(explicit?.toString() ?? '');
    if (parsedExplicit != null && parsedExplicit > 0) {
      return parsedExplicit;
    }

    final match = RegExp(r'_w(\d+)_', caseSensitive: false).firstMatch(itemId);
    if (match != null) {
      final parsed = int.tryParse(match.group(1) ?? '');
      if (parsed != null && parsed > 0) {
        return parsed;
      }
    }

    return 1;
  }

  String _toDocId(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  Map<String, dynamic>? _resolveSubjectData({
    required String subjectCode,
    required String subjectTitle,
    required Map<String, Map<String, dynamic>> subjectsByCode,
    required Map<String, Map<String, dynamic>> subjectsByTitle,
  }) {
    final codeKey = subjectCode.trim().toUpperCase();
    if (codeKey.isNotEmpty && subjectsByCode.containsKey(codeKey)) {
      return subjectsByCode[codeKey];
    }

    final titleKey = _normalizeTitleKey(subjectTitle);
    if (titleKey.isNotEmpty && subjectsByTitle.containsKey(titleKey)) {
      return subjectsByTitle[titleKey];
    }

    return null;
  }

  String _pickFirstText(
    Map<String, dynamic> primary,
    List<String> keys, {
    Map<String, dynamic>? fallback,
  }) {
    final normalizedKeys = keys.map(_normalizeKey).toSet();

    for (final key in keys) {
      final value = _dynamicText(primary[key]);
      if (value.isNotEmpty) {
        return value;
      }
    }

    for (final entry in primary.entries) {
      final normalizedEntryKey = _normalizeKey(entry.key);
      if (normalizedKeys.contains(normalizedEntryKey) ||
          _looksLikeAssistantAlias(normalizedEntryKey, normalizedKeys) ||
          _looksLikeTeacherAlias(normalizedEntryKey, normalizedKeys)) {
        final value = _dynamicText(entry.value);
        if (value.isNotEmpty) return value;
      }
    }

    if (fallback != null) {
      for (final key in keys) {
        final value = _dynamicText(fallback[key]);
        if (value.isNotEmpty) {
          return value;
        }
      }

      for (final entry in fallback.entries) {
        final normalizedEntryKey = _normalizeKey(entry.key);
        if (normalizedKeys.contains(normalizedEntryKey) ||
            _looksLikeAssistantAlias(normalizedEntryKey, normalizedKeys) ||
            _looksLikeTeacherAlias(normalizedEntryKey, normalizedKeys)) {
          final value = _dynamicText(entry.value);
          if (value.isNotEmpty) return value;
        }
      }
    }
    return '';
  }

  String _dynamicText(dynamic value) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is num || value is bool) return value.toString().trim();
    if (value is Map) {
      for (final candidateKey in const ['name', 'fullName', 'title', 'value']) {
        final nested = _dynamicText(value[candidateKey]);
        if (nested.isNotEmpty) return nested;
      }
      return '';
    }
    return '';
  }

  String _normalizeKey(String key) {
    return key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  bool _looksLikeAssistantAlias(String key, Set<String> requestedKeys) {
    final wantsAssistant = requestedKeys.any(
      (k) =>
          k.contains('assistant') ||
          k == 'ta' ||
          k.contains('teachingassistant'),
    );
    if (!wantsAssistant) return false;
    return key.contains('assistant') ||
        key == 'ta' ||
        key.contains('teachingassistant');
  }

  bool _looksLikeTeacherAlias(String key, Set<String> requestedKeys) {
    final wantsTeacher = requestedKeys.any(
      (k) =>
          k.contains('teacher') ||
          k.contains('professor') ||
          k.contains('instructor'),
    );
    if (!wantsTeacher) return false;
    return key.contains('teacher') ||
        key.contains('professor') ||
        key.contains('instructor');
  }

  String _resolveSemesterFromData(
    Map<String, dynamic> data, {
    Map<String, dynamic>? fallback,
  }) {
    final candidates = [
      data['semester'],
      data['semesterName'],
      data['term'],
      data['termName'],
      data['semesterNumber'],
      data['termNumber'],
      fallback?['semester'],
      fallback?['semesterName'],
      fallback?['term'],
      fallback?['termName'],
      fallback?['semesterNumber'],
      fallback?['termNumber'],
    ];

    for (final candidate in candidates) {
      final normalized = _normalizeSemesterLabel(candidate?.toString() ?? '');
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }

    return 'Spring 2026';
  }

  String _normalizeSemesterLabel(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';

    final lower = value.toLowerCase();
    if (value == '1' || lower == '1st' || lower.contains('first')) {
      return 'Fall 2025';
    }
    if (value == '2' || lower == '2nd' || lower.contains('second')) {
      return 'Spring 2026';
    }
    if (lower.contains('fall') && lower.contains('2025')) {
      return 'Fall 2025';
    }
    if (lower.contains('spring') && lower.contains('2026')) {
      return 'Spring 2026';
    }
    if (lower == 'fall2025' || lower == 'fall_2025') {
      return 'Fall 2025';
    }
    if (lower == 'spring2026' || lower == 'spring_2026') {
      return 'Spring 2026';
    }

    return value;
  }

  String _normalizeTitleKey(String title) {
    return title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  String _resolveIcon(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('object') ||
        lower.contains('oop') ||
        lower.contains('programming')) {
      return 'code';
    }
    if (lower.contains('math') ||
        lower.contains('calculus') ||
        lower.contains('algebra')) {
      return 'calculate';
    }
    if (lower.contains('physics') || lower.contains('science')) {
      return 'science';
    }
    if (lower.contains('english') ||
        lower.contains('writing') ||
        lower.contains('language')) {
      return 'language';
    }
    if (lower.contains('design') || lower.contains('creative')) {
      return 'design_services';
    }
    return 'book';
  }

  List<Map<String, String>> _defaultOfficeHours(String room) {
    return const [
      {'day': 'Monday', 'time': '10:00 - 12:00'},
      {'day': 'Wednesday', 'time': '14:00 - 16:00'},
    ].map((entry) {
      return {'day': entry['day']!, 'time': entry['time']!, 'location': room};
    }).toList();
  }
}
