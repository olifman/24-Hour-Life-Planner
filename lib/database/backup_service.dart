import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'planner_database.dart';

class BackupService {
  BackupService._();

  static const int _backupVersion = 1;

  static const List<String> _tables = [
    'tasks',
    'courses',
    'weekly_timetable',
    'academic_events',
    'goals',
  ];

  static Future<Map<String, dynamic>> _buildBackupData() async {
    final db = await PlannerDatabase.instance.database;
    final preferences = await SharedPreferences.getInstance();

    final Map<String, List<Map<String, Object?>>> data = {};

    for (final table in _tables) {
      data[table] = await db.query(table);
    }

    return {
      'app': '24-Hour Life Planner',
      'backupVersion': _backupVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'tables': data,
      'settings': {'isOromo': preferences.getBool('isOromo') ?? true},
    };
  }

  static Future<String> exportBackup() async {
    final data = await _buildBackupData();
    final jsonText = const JsonEncoder.withIndent('  ').convert(data);
    final bytes = Uint8List.fromList(utf8.encode(jsonText));
    final date = DateTime.now().toIso8601String().substring(0, 10);

    final savedUri = await FilePicker.saveFile(
      fileName: 'life_planner_backup_$date.json',
      bytes: bytes,
      mimeType: 'application/json',
      dialogTitle: 'Save Life Planner backup',
    );

    if (savedUri == null) {
      return 'cancelled';
    }

    return 'saved';
  }

  static Future<String> restoreBackup() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: 'Select Life Planner backup',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (picked.isEmpty) {
      return 'cancelled';
    }

    final bytes = await picked.first.readAsBytes();
    final decoded = jsonDecode(utf8.decode(bytes));

    if (decoded is! Map<String, dynamic> ||
        decoded['app'] != '24-Hour Life Planner' ||
        decoded['backupVersion'] != _backupVersion ||
        decoded['tables'] is! Map<String, dynamic>) {
      throw const FormatException('Backup file format is not supported.');
    }

    final rawTables = decoded['tables'] as Map<String, dynamic>;

    for (final table in _tables) {
      final rows = rawTables[table];

      if (rows is! List || rows.any((row) => row is! Map<String, dynamic>)) {
        throw FormatException('Backup data for $table is invalid.');
      }
    }

    final db = await PlannerDatabase.instance.database;

    // Validate backup columns before changing existing data.
    for (final table in _tables) {
      final schema = await db.rawQuery('PRAGMA table_info($table)');
      final allowedColumns = schema
          .map((column) => column['name'] as String)
          .toSet();

      final rows = rawTables[table] as List;

      for (final row in rows) {
        final rowMap = row as Map<String, dynamic>;
        final unknownColumns = rowMap.keys
            .where((column) => !allowedColumns.contains(column))
            .toList();

        if (unknownColumns.isNotEmpty) {
          throw FormatException(
            'Backup table $table has unsupported columns: '
            '${unknownColumns.join(', ')}',
          );
        }
      }
    }
    // Save the current data before any restore changes are made.
    final safetyData = await _buildBackupData();
    final safetyJson = const JsonEncoder.withIndent('  ').convert(safetyData);
    final documents = await getApplicationDocumentsDirectory();
    final safetyFile = File(
      p.join(
        documents.path,
        'life_planner_safety_${DateTime.now().millisecondsSinceEpoch}.json',
      ),
    );
    await safetyFile.writeAsString(safetyJson, flush: true);

    await db.transaction((txn) async {
      // Delete child rows before their referenced courses.
      await txn.delete('goals');
      await txn.delete('academic_events');
      await txn.delete('weekly_timetable');
      await txn.delete('tasks');
      await txn.delete('courses');

      // Insert parent rows before rows that reference them.
      for (final table in [
        'courses',
        'tasks',
        'weekly_timetable',
        'academic_events',
        'goals',
      ]) {
        final rows = rawTables[table] as List;

        for (final row in rows) {
          await txn.insert(
            table,
            Map<String, Object?>.from(row as Map<String, dynamic>),
          );
        }
      }
    });

    final settings = decoded['settings'];
    if (settings is Map<String, dynamic> && settings['isOromo'] is bool) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool('isOromo', settings['isOromo'] as bool);
    }

    return safetyFile.path;
  }
}
