import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    try {
      if (kIsWeb) {
        var factory = databaseFactoryFfiWeb;
        return await factory.openDatabase('edurdc_local.db', options: OpenDatabaseOptions(
            version: 5,
            onCreate: _onCreate,
            onUpgrade: _onUpgrade
        ));
      } else {
        String path = join(await getDatabasesPath(), 'edurdc_local.db');
        return await openDatabase(
          path,
          version: 5,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        );
      }
    } catch (e) {
      print("Erreur d'initialisation Database: $e");
      rethrow;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY,
        username TEXT,
        email TEXT,
        role TEXT,
        phone TEXT,
        is_authenticated INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE courses (
        id INTEGER PRIMARY KEY,
        title TEXT,
        description TEXT,
        teacher_name TEXT,
        is_published INTEGER DEFAULT 0,
        sync_status TEXT DEFAULT 'synced'
      )
    ''');

    await db.execute('''
      CREATE TABLE enrollments (
        id INTEGER PRIMARY KEY,
        course_id INTEGER,
        progress REAL DEFAULT 0.0,
        FOREIGN KEY (course_id) REFERENCES courses (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE lessons (
        id INTEGER PRIMARY KEY,
        course_id INTEGER,
        title TEXT,
        content_type TEXT,
        content_file TEXT,
        content_text TEXT,
        "order" INTEGER,
        is_locked INTEGER DEFAULT 0,
        FOREIGN KEY (course_id) REFERENCES courses (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE grades (
        id INTEGER PRIMARY KEY,
        course_id INTEGER,
        course_title TEXT,
        score REAL,
        session TEXT,
        date_graded TEXT,
        FOREIGN KEY (course_id) REFERENCES courses (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE downloaded_courses (
        id INTEGER PRIMARY KEY,
        title TEXT,
        description TEXT,
        teacher_name TEXT,
        thumbnail TEXT,
        lessons_json TEXT,
        downloaded_at TEXT
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE lessons (
          id INTEGER PRIMARY KEY,
          course_id INTEGER,
          title TEXT,
          content_type TEXT,
          content_file TEXT,
          content_text TEXT,
          "order" INTEGER,
          FOREIGN KEY (course_id) REFERENCES courses (id)
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE grades (
          id INTEGER PRIMARY KEY,
          course_id INTEGER,
          course_title TEXT,
          score REAL,
          session TEXT,
          date_graded TEXT
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE lessons ADD COLUMN is_locked INTEGER DEFAULT 0');
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS downloaded_courses (
          id INTEGER PRIMARY KEY,
          title TEXT,
          description TEXT,
          teacher_name TEXT,
          thumbnail TEXT,
          lessons_json TEXT,
          downloaded_at TEXT
        )
      ''');
    }
  }

  // --- CRUD de base ---

  Future<int> insertUser(Map<String, dynamic> user) async {
    Database db = await database;
    return await db.insert('users', user, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, dynamic>?> getUser() async {
    Database db = await database;
    List<Map<String, dynamic>> results = await db.query('users', limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<void> clearAll() async {
    Database db = await database;
    await db.delete('users');
    await db.delete('courses');
    await db.delete('lessons');
    await db.delete('enrollments');
    await db.delete('grades');
  }

  Future<int> insertGrade(Map<String, dynamic> grade) async {
    Database db = await database;
    return await db.insert('grades', grade, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getGrades() async {
    Database db = await database;
    return await db.query('grades', orderBy: 'date_graded DESC');
  }

  // --- Cours téléchargés hors-ligne ---

  Future<void> downloadCourse(Map<String, dynamic> course) async {
    Database db = await database;
    final lessons = course['lessons'] ?? [];
    await db.insert(
      'downloaded_courses',
      {
        'id': course['id'],
        'title': course['title'] ?? '',
        'description': course['description'] ?? '',
        'teacher_name': course['teacher_name'] ?? '',
        'thumbnail': course['thumbnail']?.toString() ?? '',
        'lessons_json': jsonEncode(lessons),
        'downloaded_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getDownloadedCourses() async {
    Database db = await database;
    final rows = await db.query('downloaded_courses', orderBy: 'downloaded_at DESC');
    return rows.map((row) {
      final Map<String, dynamic> course = Map.from(row);
      try {
        course['lessons'] = jsonDecode(row['lessons_json'] as String? ?? '[]');
      } catch (_) {
        course['lessons'] = [];
      }
      return course;
    }).toList();
  }

  Future<void> deleteCourseDownload(int courseId) async {
    Database db = await database;
    await db.delete('downloaded_courses', where: 'id = ?', whereArgs: [courseId]);
  }

  Future<bool> isCourseDownloaded(int courseId) async {
    Database db = await database;
    final result = await db.query('downloaded_courses', where: 'id = ?', whereArgs: [courseId]);
    return result.isNotEmpty;
  }
}
