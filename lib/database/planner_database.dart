import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class PlannerDatabase {
  PlannerDatabase._();

  static final PlannerDatabase instance = PlannerDatabase._();
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _openDatabase();
    return _database!;
  }

  Future<Database> _openDatabase() async {
    final dbPath = await getDatabasesPath();
    final filePath = join(dbPath, 'life_planner.db');

    return openDatabase(
      filePath,
      version: 7,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            startHour INTEGER NOT NULL,
            startMinute INTEGER NOT NULL,
            endHour INTEGER NOT NULL,
            endMinute INTEGER NOT NULL,
            completed INTEGER NOT NULL DEFAULT 0,
            taskDate TEXT NOT NULL DEFAULT '2000-01-01',
            description TEXT NOT NULL DEFAULT '',
            category TEXT NOT NULL DEFAULT 'General',
            priority TEXT NOT NULL DEFAULT 'Normal',
            status TEXT NOT NULL DEFAULT 'Not Started',
            recurrence TEXT NOT NULL DEFAULT 'None',
            colorValue INTEGER,
            reminderMinutes INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await _createStudentTables(db);
        await _createGoalsTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE tasks ADD COLUMN taskDate TEXT NOT NULL DEFAULT '2000-01-01'",
          );
          await db.execute(
            "ALTER TABLE tasks ADD COLUMN description TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE tasks ADD COLUMN category TEXT NOT NULL DEFAULT 'General'",
          );
          await db.execute(
            "ALTER TABLE tasks ADD COLUMN priority TEXT NOT NULL DEFAULT 'Normal'",
          );
          await db.execute(
            "ALTER TABLE tasks ADD COLUMN status TEXT NOT NULL DEFAULT 'Not Started'",
          );
          await db.execute(
            "ALTER TABLE tasks ADD COLUMN recurrence TEXT NOT NULL DEFAULT 'None'",
          );
          await db.execute('ALTER TABLE tasks ADD COLUMN colorValue INTEGER');
          await db.execute(
            'ALTER TABLE tasks ADD COLUMN reminderMinutes INTEGER NOT NULL DEFAULT 0',
          );

          final now = DateTime.now();
          final today =
              '${now.year.toString().padLeft(4, '0')}-'
              '${now.month.toString().padLeft(2, '0')}-'
              '${now.day.toString().padLeft(2, '0')}';

          await db.update('tasks', {
            'taskDate': today,
          }, where: "taskDate = '2000-01-01'");

          await db.execute('''
            UPDATE tasks
            SET status = CASE
              WHEN completed = 1 THEN 'Completed'
              ELSE 'Not Started'
            END
          ''');
        }

        if (oldVersion < 3) {
          await _createStudentTables(db);
        }

        if (oldVersion < 4) {
          await _createGoalsTable(db);
        }

        if (oldVersion < 5) {
          await db.execute(
            "ALTER TABLE goals ADD COLUMN actualGrade TEXT NOT NULL DEFAULT ''",
          );
        }

        if (oldVersion < 6) {
          await db.execute(
            "ALTER TABLE courses ADD COLUMN instructorEmail TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE courses ADD COLUMN officeHours TEXT NOT NULL DEFAULT ''",
          );
        }

        if (oldVersion < 7) {
          final columns = await db.rawQuery('PRAGMA table_info(courses)');
          final columnNames = columns
              .map((column) => column['name'] as String)
              .toSet();

          if (!columnNames.contains('instructorEmail')) {
            await db.execute(
              "ALTER TABLE courses ADD COLUMN instructorEmail TEXT NOT NULL DEFAULT ''",
            );
          }

          if (!columnNames.contains('officeHours')) {
            await db.execute(
              "ALTER TABLE courses ADD COLUMN officeHours TEXT NOT NULL DEFAULT ''",
            );
          }
        }
      },
    );
  }

  static Future<void> _createGoalsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS goals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        targetScore REAL NOT NULL DEFAULT 0,
        targetMaxScore REAL NOT NULL DEFAULT 100,
        actualGrade TEXT NOT NULL DEFAULT '',
        dueDate TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'Active',
        courseId INTEGER,
        createdAt TEXT NOT NULL DEFAULT '',
        FOREIGN KEY(courseId) REFERENCES courses(id) ON DELETE SET NULL
      )
    ''');
  }

  static Future<void> _createStudentTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE courses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        code TEXT NOT NULL DEFAULT '',
        department TEXT NOT NULL DEFAULT '',
        semester TEXT NOT NULL DEFAULT '',
        academicYear TEXT NOT NULL DEFAULT '',
        instructor TEXT NOT NULL DEFAULT '',
        instructorEmail TEXT NOT NULL DEFAULT '',
        officeHours TEXT NOT NULL DEFAULT '',
        creditHours REAL NOT NULL DEFAULT 0,
        targetGrade TEXT NOT NULL DEFAULT '',
        actualGrade TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE weekly_timetable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        courseId INTEGER,
        dayOfWeek INTEGER NOT NULL,
        startHour INTEGER NOT NULL,
        startMinute INTEGER NOT NULL,
        endHour INTEGER NOT NULL,
        endMinute INTEGER NOT NULL,
        room TEXT NOT NULL DEFAULT '',
        sessionType TEXT NOT NULL DEFAULT 'Lecture',
        notes TEXT NOT NULL DEFAULT '',
        FOREIGN KEY(courseId) REFERENCES courses(id)
          ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE academic_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        courseId INTEGER,
        title TEXT NOT NULL,
        eventType TEXT NOT NULL,
        eventDate TEXT NOT NULL,
        startHour INTEGER,
        startMinute INTEGER,
        dueDate TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        location TEXT NOT NULL DEFAULT '',
        reminderMinutes INTEGER NOT NULL DEFAULT 60,
        completed INTEGER NOT NULL DEFAULT 0,
        score REAL,
        maxScore REAL,
        status TEXT NOT NULL DEFAULT 'Pending',
        FOREIGN KEY(courseId) REFERENCES courses(id)
          ON DELETE SET NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_timetable_day ON weekly_timetable(dayOfWeek)',
    );
    await db.execute(
      'CREATE INDEX idx_academic_events_date ON academic_events(eventDate)',
    );
  }

  Future<int> insertTask(Map<String, Object?> task) async {
    final db = await database;
    final values = Map<String, Object?>.from(task);

    values.putIfAbsent('taskDate', () {
      final now = DateTime.now();
      return '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
    });

    return db.insert('tasks', values);
  }

  Future<List<Map<String, Object?>>> getTasks() async {
    final db = await database;
    return db.query(
      'tasks',
      orderBy: 'taskDate ASC, startHour ASC, startMinute ASC',
    );
  }

  Future<int> updateTask(int id, Map<String, Object?> task) async {
    final db = await database;
    return db.update('tasks', task, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteTask(int id) async {
    final db = await database;
    return db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertCourse(Map<String, Object?> course) async {
    final db = await database;
    return db.insert('courses', course);
  }

  Future<List<Map<String, Object?>>> getCourses() async {
    final db = await database;
    return db.query('courses', orderBy: 'name COLLATE NOCASE ASC');
  }

  Future<int> updateCourse(int id, Map<String, Object?> course) async {
    final db = await database;
    return db.update('courses', course, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteCourse(int id) async {
    final db = await database;
    return db.delete('courses', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertTimetableEntry(Map<String, Object?> entry) async {
    final db = await database;
    return db.insert('weekly_timetable', entry);
  }

  Future<List<Map<String, Object?>>> getTimetable({int? dayOfWeek}) async {
    final db = await database;
    return db.query(
      'weekly_timetable',
      where: dayOfWeek == null ? null : 'dayOfWeek = ?',
      whereArgs: dayOfWeek == null ? null : [dayOfWeek],
      orderBy: 'dayOfWeek ASC, startHour ASC, startMinute ASC',
    );
  }

  Future<int> updateTimetableEntry(int id, Map<String, Object?> entry) async {
    final db = await database;
    return db.update(
      'weekly_timetable',
      entry,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteTimetableEntry(int id) async {
    final db = await database;
    return db.delete('weekly_timetable', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertAcademicEvent(Map<String, Object?> event) async {
    final db = await database;
    return db.insert('academic_events', event);
  }

  Future<List<Map<String, Object?>>> getAcademicEvents({
    String? fromDate,
    String? toDate,
    int? courseId,
  }) async {
    final db = await database;
    final conditions = <String>[];
    final arguments = <Object?>[];

    if (fromDate != null) {
      conditions.add('eventDate >= ?');
      arguments.add(fromDate);
    }
    if (toDate != null) {
      conditions.add('eventDate <= ?');
      arguments.add(toDate);
    }
    if (courseId != null) {
      conditions.add('courseId = ?');
      arguments.add(courseId);
    }

    return db.query(
      'academic_events',
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: arguments.isEmpty ? null : arguments,
      orderBy: 'eventDate ASC, startHour ASC, startMinute ASC',
    );
  }

  Future<int> updateAcademicEvent(int id, Map<String, Object?> event) async {
    final db = await database;
    return db.update(
      'academic_events',
      event,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteAcademicEvent(int id) async {
    final db = await database;
    return db.delete('academic_events', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertGoal(Map<String, Object?> goal) async {
    final db = await database;
    return db.insert('goals', goal);
  }

  Future<List<Map<String, Object?>>> getGoals({int? courseId}) async {
    final db = await database;
    return db.query(
      'goals',
      where: courseId == null ? null : 'courseId = ?',
      whereArgs: courseId == null ? null : [courseId],
      orderBy: 'dueDate ASC, id DESC',
    );
  }

  Future<int> updateGoal(int id, Map<String, Object?> goal) async {
    final db = await database;
    return db.update('goals', goal, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteGoal(int id) async {
    final db = await database;
    return db.delete('goals', where: 'id = ?', whereArgs: [id]);
  }
}
