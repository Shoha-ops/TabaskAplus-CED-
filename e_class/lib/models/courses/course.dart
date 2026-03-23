import 'package:cloud_firestore/cloud_firestore.dart';

class Course {
  final String id;
  final String title;
  final String icon; // Icon name as string, e.g., 'math', 'physics'
  final String professorId;
  final String professorName; // Added for convenience
  final String semester;

  Course({
    required this.id,
    required this.title,
    required this.icon,
    required this.professorId,
    required this.professorName,
    required this.semester,
  });

  factory Course.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return Course(
      id: doc.id,
      title: data['title'] ?? '',
      icon: data['icon'] ?? 'default',
      professorId: data['professorId'] ?? '',
      professorName: data['professorName'] ?? '',
      semester: (data['semester'] ?? '').toString(),
    );
  }
}

class Week {
  final String id;
  final int number;
  final DateTime startDate;
  final DateTime endDate;

  Week({
    required this.id,
    required this.number,
    required this.startDate,
    required this.endDate,
  });

  factory Week.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    final start = _parseDate(data['startDate']);
    final end = _parseDate(data['endDate']);

    return Week(
      id: doc.id,
      number: _parseNumber(data['number']),
      startDate: start,
      endDate: end,
    );
  }

  static int _parseNumber(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  static DateTime _parseDate(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is int) {
      // Treat values < 10^12 as seconds, otherwise milliseconds.
      final millis = raw < 1000000000000 ? raw * 1000 : raw;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed;
    }
    return DateTime(1970, 1, 1);
  }
}

class Staff {
  final String id;
  final String name;
  final String avatarUrl; // Assuming URL or asset path
  final String role; // 'Professor' or 'Assistant'
  final String assistantId;
  final List<OfficeHour> officeHours;

  Staff({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.role,
    required this.assistantId,
    required this.officeHours,
  });

  factory Staff.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    var hours = data['officeHours'] as List<dynamic>? ?? [];
    return Staff(
      id: doc.id,
      name: data['name'] ?? '',
      avatarUrl: data['avatarUrl'] ?? '',
      role: data['role'] ?? 'Professor',
      assistantId: data['assistantId'] ?? '',
      officeHours: hours.map((h) => OfficeHour.fromMap(h)).toList(),
    );
  }
}

class OfficeHour {
  final String day;
  final String time;
  final String location;

  OfficeHour({required this.day, required this.time, required this.location});

  factory OfficeHour.fromMap(Map<String, dynamic> map) {
    return OfficeHour(
      day: map['day'] ?? '',
      time: map['time'] ?? '',
      location: map['location'] ?? '',
    );
  }
}

class Announcement {
  final String id;
  final String courseId;
  final int weekNumber;
  final String title;
  final String content;
  final DateTime date;
  final DateTime? deadline;

  Announcement({
    required this.id,
    required this.courseId,
    required this.weekNumber,
    required this.title,
    required this.content,
    required this.date,
    this.deadline,
  });

  factory Announcement.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    final rawDeadline = data['deadline'] ?? data['dueDate'];
    return Announcement(
      id: doc.id,
      courseId: data['courseId'] ?? '',
      weekNumber: data['weekNumber'] ?? 0,
      title: data['title'] ?? '',
      content: data['content'] ?? '',
      date: (data['date'] as Timestamp).toDate(),
      deadline: _parseDate(rawDeadline),
    );
  }
}

class CourseMaterial {
  final String id;
  final String courseId;
  final int weekNumber;
  final String title;
  final String type; // 'lecture', 'homework', etc.
  final String url;
  final DateTime? deadline;

  CourseMaterial({
    required this.id,
    required this.courseId,
    required this.weekNumber,
    required this.title,
    required this.type,
    required this.url,
    this.deadline,
  });

  factory CourseMaterial.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    final rawDeadline = data['deadline'] ?? data['dueDate'];
    return CourseMaterial(
      id: doc.id,
      courseId: data['courseId'] ?? '',
      weekNumber: data['weekNumber'] ?? 0,
      title: data['title'] ?? '',
      type: data['type'] ?? '',
      url: data['url'] ?? '',
      deadline: _parseDate(rawDeadline),
    );
  }
}

DateTime? _parseDate(dynamic raw) {
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  if (raw is int) {
    final millis = raw < 1000000000000 ? raw * 1000 : raw;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
  if (raw is String) {
    return DateTime.tryParse(raw);
  }
  return null;
}
