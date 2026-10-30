import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

import 'database/planner_database.dart';
import 'database/backup_service.dart';

void main() {
  runApp(const LifePlannerApp());
}

class LifePlannerApp extends StatelessWidget {
  const LifePlannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '24-Hour Life Planner',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3977E8),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
      ),
      home: const PlannerHomePage(),
    );
  }
}

class PlannerTask {
  PlannerTask({
    this.id,
    required this.title,
    required this.start,
    required this.end,
    this.completed = false,
    DateTime? date,
    this.description = '',
    this.category = 'General',
    this.priority = 'Normal',
    this.status = 'Not Started',
    this.recurrence = 'None',
    this.reminderMinutes = 0,
  }) : date = date ?? DateTime.now();

  int? id;
  String title;
  TimeOfDay start;
  TimeOfDay end;
  bool completed;
  DateTime date;
  String description;
  String category;
  String priority;
  String status;
  String recurrence;
  int reminderMinutes;
}

class PlannerHomePage extends StatefulWidget {
  const PlannerHomePage({super.key});

  @override
  State<PlannerHomePage> createState() => _PlannerHomePageState();
}

class _PlannerHomePageState extends State<PlannerHomePage> {
  bool isOromo = true;
  int _selectedIndex = 0;
  DateTime _calendarMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );
  DateTime _selectedCalendarDate = DateTime.now();

  final List<PlannerTask> tasks = [];

  @override
  void initState() {
    super.initState();
    _initializeAppServices();
  }

  Future<void> _setLanguage(bool value) async {
    if (mounted) {
      setState(() => isOromo = value);
    }
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool('isOromo', value);
    } catch (error) {
      debugPrint('Could not save language preference: $error');
    }
  }

  Future<void> _exportAppBackup() async {
    try {
      final result = await BackupService.exportBackup();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == 'cancelled'
                ? (isOromo ? 'Backup haqame.' : 'Backup cancelled.')
                : (isOromo
                      ? "Backup milkaa'inaan kuufame."
                      : 'Backup exported successfully.'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isOromo
                ? 'Backup gochuun hin milkoofne: $error'
                : 'Backup failed: $error',
          ),
        ),
      );
    }
  }

  Future<void> _restoreAppBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isOromo ? "Backup deebisanii fe'uu?" : "Restore backup?"),
        content: Text(
          isOromo
              ? 'Kun deetaa amma appii keessa jiru bakka buusa. Itti fufuu barbaaddaa?'
              : 'This will replace the current app data. Do you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(isOromo ? 'Lakki' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(isOromo ? 'Eeyyee' : 'Continue'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final result = await BackupService.restoreBackup();
      if (result == 'cancelled') return;

      final preferences = await SharedPreferences.getInstance();
      final restoredLanguage = preferences.getBool('isOromo') ?? true;

      if (!mounted) return;
      setState(() => isOromo = restoredLanguage);

      await _loadTasks();

      for (final task in tasks) {
        await _scheduleReminderForTask(task);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isOromo
                ? "Backup deebifamee fe'ameera."
                : 'Backup restored successfully.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isOromo
                ? "Backup deebisanii fe'uun hin milkoofne: $error"
                : 'Restore failed: $error',
          ),
        ),
      );
    }
  }

  Future<void> _initializeAppServices() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final savedLanguage = preferences.getBool('isOromo');
      if (savedLanguage != null && mounted) {
        setState(() => isOromo = savedLanguage);
      }
    } catch (error) {
      debugPrint('Could not load language preference: $error');
    }

    try {
      await NotificationService.instance.initialize();
      await NotificationService.instance.requestPermissions();
    } catch (error) {
      debugPrint('Notification initialization failed: $error');
    }

    await _loadTasks();

    for (final task in tasks) {
      await _scheduleReminderForTask(task);
    }
  }

  Future<void> _scheduleReminderForTask(PlannerTask task) async {
    if (task.id == null) return;

    if (task.completed) {
      await NotificationService.instance.cancel(task.id!);
      return;
    }

    final taskStart = DateTime(
      task.date.year,
      task.date.month,
      task.date.day,
      task.start.hour,
      task.start.minute,
    );

    final reminderTime = taskStart.subtract(
      Duration(minutes: task.reminderMinutes),
    );

    await NotificationService.instance.scheduleTaskReminder(
      id: task.id!,
      title: task.title,
      scheduledAt: reminderTime,
      isOromo: isOromo,
      recurrence: task.recurrence,
    );
  }

  Future<void> _loadTasks() async {
    try {
      final rows = await PlannerDatabase.instance.getTasks();

      final loadedTasks = rows.map((row) {
        final dateText = row['taskDate'] as String?;
        final parsedDate = dateText == null
            ? DateTime.now()
            : DateTime.tryParse(dateText) ?? DateTime.now();

        final completed = (row['completed'] as int? ?? 0) == 1;
        final savedStatus =
            row['status'] as String? ??
            (completed ? 'Completed' : 'Not Started');

        return PlannerTask(
          id: row['id'] as int,
          title: row['title'] as String,
          start: TimeOfDay(
            hour: row['startHour'] as int,
            minute: row['startMinute'] as int,
          ),
          end: TimeOfDay(
            hour: row['endHour'] as int,
            minute: row['endMinute'] as int,
          ),
          completed: completed,
          date: DateTime(parsedDate.year, parsedDate.month, parsedDate.day),
          description: row['description'] as String? ?? '',
          category: row['category'] as String? ?? 'General',
          priority: row['priority'] as String? ?? 'Normal',
          status: savedStatus,
          recurrence: row['recurrence'] as String? ?? 'None',
          reminderMinutes: row['reminderMinutes'] as int? ?? 0,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        tasks
          ..clear()
          ..addAll(loadedTasks);
      });
    } catch (error) {
      debugPrint('Could not load saved tasks: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isOromo
                ? "Hojiiwwan kuufaman fe'uun hin milkoofne."
                : 'Could not load saved tasks.',
          ),
        ),
      );
    }
  }

  String get language => isOromo ? 'Afaan Oromoo' : 'English';

  String get pageTitle => isOromo ? 'Karoora Jireenyaa' : 'Life Planner';

  String get todayLabel => isOromo ? "Har'a" : 'Today';

  String get greeting => isOromo ? 'Guyyaa gaarii!' : 'Have a great day!';

  String get subtitle => isOromo
      ? "Guyyaa kee karoorsii, galma kee bira gahi."
      : 'Plan your day. Make every hour count.';

  String get tasksLabel => isOromo ? "Hojiiwwan har'aa" : "Today's tasks";

  String get addTaskLabel => isOromo ? 'Hojii dabali' : 'Add task';

  String get completedLabel => isOromo ? 'Xumurame' : 'Completed';

  String get remainingLabel => isOromo ? 'Hafe' : 'Remaining';

  String get totalLabel => isOromo ? 'Waliigala' : 'Total tasks';

  String get emptyLabel => isOromo
      ? 'Hojii hin qabdu. Hojii haaraa dabali!'
      : 'No tasks yet. Add your first task!';

  int get completedCount => tasks.where((task) => task.completed).length;

  String formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  DateTime _taskStartDateTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  DateTime _taskEndDateTime(DateTime date, TimeOfDay start, TimeOfDay end) {
    final startDateTime = _taskStartDateTime(date, start);
    var endDateTime = _taskStartDateTime(date, end);

    if (!endDateTime.isAfter(startDateTime)) {
      endDateTime = endDateTime.add(const Duration(days: 1));
    }

    return endDateTime;
  }

  bool _taskTimesOverlap(
    DateTime firstDate,
    TimeOfDay firstStart,
    TimeOfDay firstEnd,
    DateTime secondDate,
    TimeOfDay secondStart,
    TimeOfDay secondEnd,
  ) {
    final firstStartDateTime = _taskStartDateTime(firstDate, firstStart);
    final firstEndDateTime = _taskEndDateTime(firstDate, firstStart, firstEnd);
    final secondStartDateTime = _taskStartDateTime(secondDate, secondStart);
    final secondEndDateTime = _taskEndDateTime(
      secondDate,
      secondStart,
      secondEnd,
    );

    return firstStartDateTime.isBefore(secondEndDateTime) &&
        firstEndDateTime.isAfter(secondStartDateTime);
  }

  String formatDate() {
    final now = DateTime.now();
    const oromoDays = [
      'Wiixata',
      'Kibxata',
      'Roobii',
      'Kamiisa',
      'Jimaata',
      'Sanbata',
      'Dilbata',
    ];
    const englishDays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const oromoMonths = [
      'Amajjii',
      'Guraandhala',
      'Bitooteessa',
      'Ebla',
      'Caamsaa',
      'Waxabajjii',
      'Adooleessa',
      'Hagayya',
      'Fulbaana',
      'Onkololeessa',
      'Sadaasa',
      'Muddee',
    ];
    const englishMonths = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final day = isOromo
        ? oromoDays[now.weekday - 1]
        : englishDays[now.weekday - 1];
    final month = isOromo
        ? oromoMonths[now.month - 1]
        : englishMonths[now.month - 1];

    return '$day, ${now.day} $month ${now.year}';
  }

  Future<void> addTask() async {
    final pageContext = context;
    String titleInput = '';
    String descriptionInput = '';

    TimeOfDay start = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay end = const TimeOfDay(hour: 10, minute: 0);
    DateTime selectedDate = DateTime.now();
    String category = 'General';
    String priority = 'Normal';
    String recurrence = 'None';
    int reminderMinutes = 0;

    try {
      final task = await showDialog<PlannerTask>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final dateLabel =
                  '${selectedDate.year}-'
                  '${selectedDate.month.toString().padLeft(2, '0')}-'
                  '${selectedDate.day.toString().padLeft(2, '0')}';

              return AlertDialog(
                title: Text(isOromo ? 'Hojii haaraa' : 'New task'),
                content: SizedBox(
                  width: 420,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          onChanged: (value) => titleInput = value,
                          autofocus: true,
                          decoration: InputDecoration(
                            labelText: isOromo ? 'Maqaa hojii' : 'Task title',
                            hintText: isOromo
                                ? 'Fakkeenya: Kitaaba dubbisuu'
                                : 'e.g. Read a book',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          onChanged: (value) => descriptionInput = value,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: isOromo ? 'Ibsa hojii' : 'Description',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(isOromo ? 'Guyyaa hojii' : 'Task date'),
                        TextButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: dialogContext,
                              initialDate: selectedDate,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                selectedDate = DateTime(
                                  picked.year,
                                  picked.month,
                                  picked.day,
                                );
                              });
                            }
                          },
                          icon: const Icon(Icons.calendar_month),
                          label: Text(dateLabel),
                        ),
                        const SizedBox(height: 8),
                        Text(isOromo ? 'Yeroo jalqabaa' : 'Start time'),
                        TextButton.icon(
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: dialogContext,
                              initialTime: start,
                            );
                            if (picked != null) {
                              setDialogState(() => start = picked);
                            }
                          },
                          icon: const Icon(Icons.schedule),
                          label: Text(formatTime(start)),
                        ),
                        Text(isOromo ? 'Yeroo xumuraa' : 'End time'),
                        TextButton.icon(
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: dialogContext,
                              initialTime: end,
                            );
                            if (picked != null) {
                              setDialogState(() => end = picked);
                            }
                          },
                          icon: const Icon(Icons.flag_outlined),
                          label: Text(formatTime(end)),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: category,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: isOromo ? 'Gosa hojii' : 'Category',
                            border: const OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'General',
                              child: Text('General'),
                            ),
                            DropdownMenuItem(
                              value: 'Study',
                              child: Text('Study'),
                            ),
                            DropdownMenuItem(
                              value: 'Work',
                              child: Text('Work'),
                            ),
                            DropdownMenuItem(
                              value: 'Health',
                              child: Text('Health'),
                            ),
                            DropdownMenuItem(
                              value: 'Exercise',
                              child: Text('Exercise'),
                            ),
                            DropdownMenuItem(
                              value: 'Personal',
                              child: Text('Personal'),
                            ),
                            DropdownMenuItem(
                              value: 'Rest',
                              child: Text('Rest'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => category = value);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: priority,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: isOromo ? 'Dursa' : 'Priority',
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'Low',
                              child: Text(isOromo ? 'Xiqqaa' : 'Low'),
                            ),
                            DropdownMenuItem(
                              value: 'Normal',
                              child: Text(isOromo ? 'Idilee' : 'Normal'),
                            ),
                            DropdownMenuItem(
                              value: 'High',
                              child: Text(isOromo ? 'Olaanaa' : 'High'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => priority = value);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: recurrence,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: isOromo
                                ? 'Irra deddeebii'
                                : 'Repeat task',
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'None',
                              child: Text(isOromo ? 'Hin jiru' : 'None'),
                            ),
                            DropdownMenuItem(
                              value: 'Daily',
                              child: Text(isOromo ? 'Guyyaa guyyaan' : 'Daily'),
                            ),
                            DropdownMenuItem(
                              value: 'Weekly',
                              child: Text(
                                isOromo ? 'Torban torbaniin' : 'Weekly',
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => recurrence = value);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: reminderMinutes,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: isOromo
                                ? 'Yaadachiisa (daqiiqaa dura)'
                                : 'Reminder (minutes before)',
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 0,
                              child: Text(
                                isOromo ? '0 daqiiqaa' : 'At start (0 min)',
                              ),
                            ),
                            const DropdownMenuItem(
                              value: 5,
                              child: Text('5 minutes before'),
                            ),
                            const DropdownMenuItem(
                              value: 10,
                              child: Text('10 minutes before'),
                            ),
                            const DropdownMenuItem(
                              value: 15,
                              child: Text('15 minutes before'),
                            ),
                            const DropdownMenuItem(
                              value: 30,
                              child: Text('30 minutes before'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => reminderMinutes = value);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(isOromo ? 'Dhiisi' : 'Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      final title = titleInput.trim();

                      if (title.isEmpty) {
                        ScaffoldMessenger.of(pageContext).showSnackBar(
                          SnackBar(
                            content: Text(
                              isOromo
                                  ? 'Maqaa hojii galchi.'
                                  : 'Please enter a task title.',
                            ),
                          ),
                        );
                        return;
                      }

                      final startMinutes = start.hour * 60 + start.minute;
                      final endMinutes = end.hour * 60 + end.minute;

                      if (endMinutes == startMinutes) {
                        showDialog<void>(
                          context: dialogContext,
                          builder: (alertContext) => AlertDialog(
                            title: Text(
                              isOromo
                                  ? 'Akeekkachiisa: Yeroon sirrii miti'
                                  : 'Warning: Invalid time',
                            ),
                            content: Text(
                              isOromo
                                  ? "Yeroon xumuraa yeroo jalqabaa booda ta'uu qaba. Maaloo yeroo sirrii filadhu."
                                  : 'End time must be after start time. Please choose a valid time.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(alertContext),
                                child: Text(isOromo ? 'Tole' : 'OK'),
                              ),
                            ],
                          ),
                        );
                        return;
                      }
                      final selectedDay = DateTime(
                        selectedDate.year,
                        selectedDate.month,
                        selectedDate.day,
                      );

                      String? conflictingTitle;

                      for (final existingTask in tasks) {
                        final existingDay = DateTime(
                          existingTask.date.year,
                          existingTask.date.month,
                          existingTask.date.day,
                        );

                        if (_taskTimesOverlap(
                          selectedDay,
                          start,
                          end,
                          existingTask.date,
                          existingTask.start,
                          existingTask.end,
                        )) {
                          conflictingTitle = existingTask.title;
                          break;
                        }
                      }

                      if (conflictingTitle != null) {
                        showDialog<void>(
                          context: dialogContext,
                          builder: (alertContext) => AlertDialog(
                            title: Text(
                              isOromo
                                  ? "Akeekkachiisa: Yeroon walitti bu'a"
                                  : 'Warning: Time conflict',
                            ),
                            content: Text(
                              isOromo
                                  ? "Sa'aatiin hojii kana hojii "
                                        " waliin walitti bu'a. Maaloo yeroo biraa filadhu."
                                  : 'This time overlaps with "$conflictingTitle". Please choose another time.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(alertContext),
                                child: Text(isOromo ? 'Tole' : 'OK'),
                              ),
                            ],
                          ),
                        );
                        return;
                      }
                      Navigator.pop(
                        dialogContext,
                        PlannerTask(
                          title: title,
                          start: start,
                          end: end,
                          date: selectedDate,
                          description: descriptionInput.trim(),
                          category: category,
                          priority: priority,
                          status: 'Not Started',
                          recurrence: recurrence,
                          reminderMinutes: reminderMinutes,
                        ),
                      );
                    },
                    child: Text(isOromo ? "Olkaa'i" : 'Save'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (task == null || !mounted) return;

      final taskDate = DateTime(task.date.year, task.date.month, task.date.day);

      final id = await PlannerDatabase.instance.insertTask({
        'title': task.title,
        'startHour': task.start.hour,
        'startMinute': task.start.minute,
        'endHour': task.end.hour,
        'endMinute': task.end.minute,
        'completed': task.completed ? 1 : 0,
        'taskDate': taskDate.toIso8601String(),
        'description': task.description,
        'category': task.category,
        'priority': task.priority,
        'status': task.status,
        'recurrence': task.recurrence,
        'reminderMinutes': task.reminderMinutes,
      });

      task.id = id;
      if (!mounted) return;

      setState(() {
        tasks.add(task);
        tasks.sort((a, b) {
          final aDate = DateTime(a.date.year, a.date.month, a.date.day);
          final bDate = DateTime(b.date.year, b.date.month, b.date.day);
          final dateComparison = aDate.compareTo(bDate);

          if (dateComparison != 0) return dateComparison;

          final aTime = a.start.hour * 60 + a.start.minute;
          final bTime = b.start.hour * 60 + b.start.minute;
          return aTime.compareTo(bTime);
        });
      });

      try {
        await _scheduleReminderForTask(task);
      } catch (error) {
        debugPrint('Could not schedule task reminder: $error');
      }
    } catch (error) {
      debugPrint('Could not add task: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isOromo
                  ? 'Hojii kuusuu hin dandeenye.'
                  : 'Could not save the task.',
            ),
          ),
        );
      }
    }
  }

  Future<void> editTask(int index) async {
    final task = tasks[index];
    if (task.id == null) return;

    final titleController = TextEditingController(text: task.title);
    final descriptionController = TextEditingController(text: task.description);
    TimeOfDay start = task.start;
    TimeOfDay end = task.end;
    DateTime selectedDate = task.date;
    String category = task.category;
    String priority = task.priority;
    String recurrence = task.recurrence;
    int reminderMinutes = [0, 5, 10, 15, 30].contains(task.reminderMinutes)
        ? task.reminderMinutes
        : 0;

    try {
      final updated = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final dateLabel =
                  '${selectedDate.year}-'
                  '${selectedDate.month.toString().padLeft(2, '0')}-'
                  '${selectedDate.day.toString().padLeft(2, '0')}';

              return AlertDialog(
                title: Text(isOromo ? 'Hojii gulaali' : 'Edit task'),
                content: SizedBox(
                  width: 420,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: titleController,
                          autofocus: true,
                          decoration: InputDecoration(
                            labelText: isOromo ? 'Maqaa hojii' : 'Task title',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: descriptionController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: isOromo ? 'Ibsa hojii' : 'Description',
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: category,
                          decoration: InputDecoration(
                            labelText: isOromo ? 'Ramaddii hojii' : 'Category',
                            border: const OutlineInputBorder(),
                          ),
                          items:
                              [
                                    'General',
                                    'Study',
                                    'Work',
                                    'Health',
                                    'Exercise',
                                    'Personal',
                                    'Rest',
                                  ]
                                  .map(
                                    (item) => DropdownMenuItem(
                                      value: item,
                                      child: Text(item),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => category = value);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: priority,
                          decoration: InputDecoration(
                            labelText: isOromo ? 'Dursa hojii' : 'Priority',
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'Low',
                              child: Text(isOromo ? 'Xiqqaa' : 'Low'),
                            ),
                            DropdownMenuItem(
                              value: 'Normal',
                              child: Text(isOromo ? 'Idilee' : 'Normal'),
                            ),
                            DropdownMenuItem(
                              value: 'High',
                              child: Text(isOromo ? 'Olaanaa' : 'High'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => priority = value);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: recurrence,
                          decoration: InputDecoration(
                            labelText: isOromo ? 'Irra deddeebii' : 'Repeat',
                            border: const OutlineInputBorder(),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'None',
                              child: Text(isOromo ? "Hin deddeebi'u" : 'None'),
                            ),
                            DropdownMenuItem(
                              value: 'Daily',
                              child: Text(isOromo ? 'Guyyaa guyyaan' : 'Daily'),
                            ),
                            DropdownMenuItem(
                              value: 'Weekly',
                              child: Text(
                                isOromo ? 'Torban torbaniin' : 'Weekly',
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => recurrence = value);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                          initialValue: reminderMinutes,
                          decoration: InputDecoration(
                            labelText: isOromo
                                ? 'Daqiiqaa yaadachiisaa'
                                : 'Reminder (minutes before)',
                            border: const OutlineInputBorder(),
                          ),
                          items: [0, 5, 10, 15, 30]
                              .map(
                                (minutes) => DropdownMenuItem<int>(
                                  value: minutes,
                                  child: Text(
                                    minutes == 0
                                        ? (isOromo
                                              ? 'Yaadachiisa hin jiru'
                                              : 'No reminder')
                                        : '$minutes ${isOromo ? 'daqiiqaa dura' : 'minutes before'}',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => reminderMinutes = value);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(isOromo ? 'Guyyaa hojii' : 'Task date'),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: dialogContext,
                              initialDate: selectedDate,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                selectedDate = DateTime(
                                  picked.year,
                                  picked.month,
                                  picked.day,
                                );
                              });
                            }
                          },
                          icon: const Icon(Icons.calendar_month),
                          label: Text(dateLabel),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            isOromo ? 'Yeroo jalqabaa' : 'Start time',
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: dialogContext,
                              initialTime: start,
                            );
                            if (picked != null) {
                              setDialogState(() => start = picked);
                            }
                          },
                          icon: const Icon(Icons.schedule),
                          label: Text(formatTime(start)),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(isOromo ? 'Yeroo xumuraa' : 'End time'),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: dialogContext,
                              initialTime: end,
                            );
                            if (picked != null) {
                              setDialogState(() => end = picked);
                            }
                          },
                          icon: const Icon(Icons.flag_outlined),
                          label: Text(formatTime(end)),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(isOromo ? 'Dhiisi' : 'Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      final newTitle = titleController.text.trim();
                      if (newTitle.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isOromo
                                  ? 'Maqaa hojii galchi.'
                                  : 'Please enter a task title.',
                            ),
                          ),
                        );
                        return;
                      }

                      final startMinutes = start.hour * 60 + start.minute;
                      final endMinutes = end.hour * 60 + end.minute;

                      if (endMinutes == startMinutes) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isOromo
                                  ? "Yeroon xumuraa yeroo jalqabaa booda ta'uu qaba."
                                  : 'End time must be after start time.',
                            ),
                          ),
                        );
                        return;
                      }

                      final selectedDay = DateTime(
                        selectedDate.year,
                        selectedDate.month,
                        selectedDate.day,
                      );

                      for (final other in tasks) {
                        if (other.id == task.id) continue;

                        if (_taskTimesOverlap(
                          selectedDay,
                          start,
                          end,
                          other.date,
                          other.start,
                          other.end,
                        )) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                isOromo
                                    ? "Yeroon hojii \"${other.title}\" waliin walitti bu'a."
                                    : 'This time overlaps with "${other.title}".',
                              ),
                            ),
                          );
                          return;
                        }
                      }

                      Navigator.pop(dialogContext, true);
                    },
                    child: Text(isOromo ? "Olkaa'i" : 'Save changes'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (updated != true || !mounted) return;

      final newDate = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
      );

      await PlannerDatabase.instance.updateTask(task.id!, {
        'title': titleController.text.trim(),
        'startHour': start.hour,
        'startMinute': start.minute,
        'endHour': end.hour,
        'endMinute': end.minute,
        'completed': task.completed ? 1 : 0,
        'taskDate': newDate.toIso8601String(),
        'description': descriptionController.text.trim(),
        'category': category,
        'priority': priority,
        'status': task.status,
        'recurrence': recurrence,
        'reminderMinutes': reminderMinutes,
      });

      task.title = titleController.text.trim();
      task.description = descriptionController.text.trim();
      task.start = start;
      task.end = end;
      task.date = newDate;
      task.category = category;
      task.priority = priority;
      task.recurrence = recurrence;
      task.reminderMinutes = reminderMinutes;

      setState(() {
        tasks.sort((a, b) {
          final aDate = DateTime(a.date.year, a.date.month, a.date.day);
          final bDate = DateTime(b.date.year, b.date.month, b.date.day);
          final dateComparison = aDate.compareTo(bDate);
          if (dateComparison != 0) return dateComparison;
          final aTime = a.start.hour * 60 + a.start.minute;
          final bTime = b.start.hour * 60 + b.start.minute;
          return aTime.compareTo(bTime);
        });
      });

      try {
        await _scheduleReminderForTask(task);
      } catch (error) {
        debugPrint('Could not reschedule edited task reminder: $error');
      }
    } catch (error) {
      debugPrint('Could not edit task: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isOromo
                  ? 'Hojii gulaaluun hin milkoofne.'
                  : 'Could not update the task.',
            ),
          ),
        );
      }
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      titleController.dispose();
      descriptionController.dispose();
    }
  }

  Future<void> deleteTask(int index) async {
    final task = tasks[index];

    try {
      if (task.id != null) {
        await PlannerDatabase.instance.deleteTask(task.id!);
      }

      if (!mounted) return;
      setState(() => tasks.remove(task));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isOromo
                ? 'Hojii haquun hin milkoofne.'
                : 'Could not delete the task.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final remainingCount = tasks.length - completedCount;
    final progress = tasks.isEmpty ? 0.0 : completedCount / tasks.length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: const Color(0xFFE8EFFF),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.calendar_month_rounded,
                color: Color(0xFF3977E8),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                pageTitle,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: PopupMenuButton<bool>(
              tooltip: 'Language',
              onSelected: (value) => _setLanguage(value),
              itemBuilder: (context) => const [
                PopupMenuItem(value: true, child: Text('Afaan Oromoo')),
                PopupMenuItem(value: false, child: Text('English')),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.language, size: 18),
                    const SizedBox(width: 5),
                    Text(
                      isOromo ? 'OR' : 'EN',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: _selectedIndex == 0
          ? SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                children: [
                  Text(
                    formatDate(),
                    style: const TextStyle(
                      color: Color(0xFF3977E8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    greeting,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF17233C),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                  const SizedBox(height: 24),

                  // Daily progress card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3977E8), Color(0xFF635BDF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isOromo
                              ? "Milkaa'ina guyyaa kee"
                              : 'Your daily progress',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${(progress * 100).round()}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 38,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '$completedCount / ${tasks.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 9,
                            backgroundColor: Colors.white30,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          isOromo
                              ? "Tarkaanfiin xixiqqoon milkaa'ina guddaa fida."
                              : 'Small steps lead to big achievements.',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Summary cards
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryCard(
                          icon: Icons.check_circle_outline,
                          iconColor: const Color(0xFF159B72),
                          value: '$completedCount',
                          label: completedLabel,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SummaryCard(
                          icon: Icons.pending_actions,
                          iconColor: const Color(0xFFEA9635),
                          value: '$remainingCount',
                          label: remainingLabel,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SummaryCard(
                          icon: Icons.list_alt,
                          iconColor: const Color(0xFF3977E8),
                          value: '${tasks.length}',
                          label: totalLabel,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          tasksLabel,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: addTask,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(addTaskLabel),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  if (tasks.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.event_note,
                            size: 44,
                            color: Colors.blueGrey,
                          ),
                          const SizedBox(height: 12),
                          Text(emptyLabel, textAlign: TextAlign.center),
                        ],
                      ),
                    )
                  else
                    ...tasks.asMap().entries.map((entry) {
                      final index = entry.key;
                      final task = entry.value;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.black.withAlpha(10)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Checkbox(
                                value: task.completed,
                                activeColor: const Color(0xFF159B72),
                                onChanged: (value) async {
                                  final previousValue = task.completed;
                                  final newValue = value ?? false;

                                  setState(() {
                                    task.completed = newValue;
                                  });

                                  if (task.id == null) return;
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );

                                  try {
                                    await PlannerDatabase.instance.updateTask(
                                      task.id!,
                                      {'completed': newValue ? 1 : 0},
                                    );
                                  } catch (error) {
                                    if (!mounted) return;
                                    setState(() {
                                      task.completed = previousValue;
                                    });
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          isOromo
                                              ? 'Jijjiirama kuusuu hin dandeenye.'
                                              : 'Could not save the completion status.',
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                              Container(
                                width: 4,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: task.completed
                                      ? const Color(0xFF159B72)
                                      : const Color(0xFF3977E8),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      task.title,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                        decoration: task.completed
                                            ? TextDecoration.lineThrough
                                            : TextDecoration.none,
                                        color: task.completed
                                            ? Colors.black45
                                            : const Color(0xFF17233C),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.access_time,
                                          size: 14,
                                          color: Colors.black45,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            '${formatTime(task.start)} - ${formatTime(task.end)}',
                                            style: const TextStyle(
                                              color: Colors.black54,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: isOromo ? 'Gulaali' : 'Edit',
                                onPressed: () => editTask(index),
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  color: Color(0xFF3977E8),
                                ),
                              ),
                              IconButton(
                                tooltip: isOromo ? 'Haqi' : 'Delete',
                                onPressed: () => deleteTask(index),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.black45,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                  const SizedBox(height: 20),
                  Center(
                    child: Text(
                      '24-Hour Life Planner',
                      style: TextStyle(
                        color: Colors.blueGrey.shade400,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            )
          : _buildPlaceholderPage(_selectedIndex),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: isOromo ? 'Mana' : 'Home',
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_month_outlined),
            selectedIcon: const Icon(Icons.calendar_month),
            label: isOromo ? 'Kalaandarii' : 'Calendar',
          ),
          NavigationDestination(
            icon: const Icon(Icons.school_outlined),
            selectedIcon: const Icon(Icons.school),
            label: isOromo ? 'Barnoota' : 'Study',
          ),
          NavigationDestination(
            icon: const Icon(Icons.bar_chart_outlined),
            selectedIcon: const Icon(Icons.bar_chart),
            label: isOromo ? 'Gabaasa' : 'Reports',
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: isOromo ? 'Qindaa' : 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderPage(int index) {
    if (index == 1) {
      return _buildCalendarPage();
    }
    if (index == 2) {
      return _buildStudyPage();
    }
    if (index == 3) {
      return _buildReportsPage();
    }
    if (index == 4) {
      return _buildSettingsPage();
    }

    final titles = isOromo
        ? ['Mana', 'Kalaandarii', 'Gabaasa', "Qindaa'ina"]
        : ['Home', 'Calendar', 'Reports', 'Settings'];

    final descriptions = isOromo
        ? [
            '',
            '',
            'Gabaasni hojii itti aansee ni ijaarrama.',
            "Qindaa'inni appii itti aansee ni ijaarrama.",
          ]
        : [
            '',
            '',
            'The reports page will be built next.',
            'The settings page will be built next.',
          ];

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                [
                  Icons.home_outlined,
                  Icons.calendar_month_outlined,
                  Icons.bar_chart_outlined,
                  Icons.settings_outlined,
                ][index],
                size: 64,
                color: const Color(0xFF3977E8),
              ),
              const SizedBox(height: 16),
              Text(
                titles[index],
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                descriptions[index],
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudyPage() {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            isOromo ? 'Barnoota Koo' : 'My Studies',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            isOromo
                ? 'Koorsii, sagantaa torbanii, qormaata fi hojii manaa kee bakka tokkootti bulchi.'
                : 'Manage courses, your weekly timetable, exams and assignments in one place.',
            style: const TextStyle(color: Colors.black54, fontSize: 15),
          ),
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.menu_book_outlined,
                color: Color(0xFF3977E8),
                size: 32,
              ),
              title: Text(isOromo ? 'Koorsii' : 'Courses'),
              subtitle: Text(
                isOromo
                    ? 'Koorsii fi odeeffannoo semester galmeessi.'
                    : 'Add courses and semester details.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showCoursesPage,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.calendar_view_week_outlined,
                color: Color(0xFF159B72),
                size: 32,
              ),
              title: Text(isOromo ? 'Sagantaa Torbanii' : 'Weekly Timetable'),
              subtitle: Text(
                isOromo
                    ? 'Guyyaa, sa\'aatii, kutaa fi lab.'
                    : 'Days, times, rooms and labs.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showTimetablePage,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.assignment_outlined,
                color: Color(0xFFE59A24),
                size: 32,
              ),
              title: Text(
                isOromo ? 'Qormaata fi Hojii Manaa' : 'Exams and Assignments',
              ),
              subtitle: Text(
                isOromo
                    ? 'Quiz, test, mid exam, final exam fi deadline.'
                    : 'Quizzes, tests, midterms, finals and deadlines.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _showAcademicEventsPage,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAcademicEventsPage() async {
    if (!mounted) return;

    final db = PlannerDatabase.instance;
    final courses = await db.getCourses();
    if (!mounted) return;

    Future<List<Map<String, Object?>>> eventsFuture = db.getAcademicEvents();
    String selectedFilter = 'All';

    await showDialog<void>(
      context: context,
      builder: (pageContext) {
        return StatefulBuilder(
          builder: (dialogContext, refreshDialog) {
            Future<void> reloadEvents() async {
              refreshDialog(() {
                eventsFuture = db.getAcademicEvents();
              });
            }

            Future<void> addEvent() async {
              final titleController = TextEditingController();
              final descriptionController = TextEditingController();
              DateTime eventDate = DateTime.now();
              int? selectedCourseId;
              String eventType = 'Exam';

              final saved = await showDialog<bool>(
                context: dialogContext,
                builder: (formDialogContext) {
                  return StatefulBuilder(
                    builder: (formContext, refreshForm) {
                      final types = <String, String>{
                        'Exam': isOromo ? 'Qormaata' : 'Exam',
                        'Quiz': 'Quiz',
                        'Assignment': isOromo ? 'Hojii manaa' : 'Assignment',
                        'Midterm': 'Midterm',
                        'Final': isOromo ? 'Qormaata xumuraa' : 'Final exam',
                      };

                      return AlertDialog(
                        title: Text(
                          isOromo ? 'Qormaata/Hojii dabali' : 'Add exam/task',
                        ),
                        content: SizedBox(
                          width: 420,
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextField(
                                  controller: titleController,
                                  autofocus: true,
                                  decoration: InputDecoration(
                                    labelText: isOromo
                                        ? 'Mata-duree *'
                                        : 'Title *',
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  initialValue: eventType,
                                  decoration: InputDecoration(
                                    labelText: isOromo ? 'Gosa' : 'Type',
                                    border: const OutlineInputBorder(),
                                  ),
                                  items: types.entries.map((entry) {
                                    return DropdownMenuItem<String>(
                                      value: entry.key,
                                      child: Text(entry.value),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      refreshForm(() => eventType = value);
                                    }
                                  },
                                ),
                                const SizedBox(height: 12),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    '${isOromo ? 'Guyyaa' : 'Date'}: '
                                    '${eventDate.year}-'
                                    '${eventDate.month.toString().padLeft(2, '0')}-'
                                    '${eventDate.day.toString().padLeft(2, '0')}',
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    icon: const Icon(Icons.calendar_month),
                                    label: Text(
                                      isOromo
                                          ? 'Guyyaa filadhu'
                                          : 'Choose date',
                                    ),
                                    onPressed: () async {
                                      final chosen = await showDatePicker(
                                        context: formContext,
                                        initialDate: eventDate,
                                        firstDate: DateTime(2020),
                                        lastDate: DateTime(2100),
                                      );
                                      if (chosen != null) {
                                        refreshForm(() => eventDate = chosen);
                                      }
                                    },
                                  ),
                                ),
                                if (courses.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<int>(
                                    initialValue: selectedCourseId,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      labelText: isOromo
                                          ? 'Koorsii (filannoo)'
                                          : 'Course (optional)',
                                      border: const OutlineInputBorder(),
                                    ),
                                    items: [
                                      DropdownMenuItem<int>(
                                        value: null,
                                        child: Text(
                                          isOromo
                                              ? 'Koorsii hin filatamne'
                                              : 'No course selected',
                                        ),
                                      ),
                                      ...courses.map((course) {
                                        final id = course['id'] as int;
                                        return DropdownMenuItem<int>(
                                          value: id,
                                          child: Text(
                                            '${course['name'] ?? ''}',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        );
                                      }),
                                    ],
                                    onChanged: (value) {
                                      refreshForm(
                                        () => selectedCourseId = value,
                                      );
                                    },
                                  ),
                                ],
                                const SizedBox(height: 12),
                                TextField(
                                  controller: descriptionController,
                                  maxLines: 3,
                                  decoration: InputDecoration(
                                    labelText: isOromo
                                        ? 'Ibsa / Yaadannoo (filannoo)'
                                        : 'Description / Notes (optional)',
                                    border: const OutlineInputBorder(),
                                    alignLabelWithHint: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(formContext, false),
                            child: Text(isOromo ? 'Dhiisi' : 'Cancel'),
                          ),
                          FilledButton.icon(
                            icon: const Icon(Icons.save),
                            onPressed: () async {
                              final title = titleController.text.trim();
                              if (title.isEmpty) {
                                ScaffoldMessenger.of(formContext).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      isOromo
                                          ? 'Mata-duree galchi.'
                                          : 'Enter a title.',
                                    ),
                                  ),
                                );
                                return;
                              }

                              final date =
                                  '${eventDate.year}-'
                                  '${eventDate.month.toString().padLeft(2, '0')}-'
                                  '${eventDate.day.toString().padLeft(2, '0')}';

                              FocusManager.instance.primaryFocus?.unfocus();

                              await db.insertAcademicEvent({
                                'courseId': selectedCourseId,
                                'title': title,
                                'eventType': eventType,
                                'eventDate': date,
                                'dueDate': date,
                                'description': descriptionController.text
                                    .trim(),
                                'completed': 0,
                                'status': 'Pending',
                              });

                              if (formContext.mounted) {
                                Navigator.pop(formContext, true);
                              }
                            },
                            label: Text(isOromo ? 'Kuusi' : 'Save'),
                          ),
                        ],
                      );
                    },
                  );
                },
              );

              await Future<void>.delayed(const Duration(milliseconds: 300));
              titleController.dispose();
              descriptionController.dispose();

              if (saved == true) {
                await reloadEvents();
              }
            }

            final filterLabels = <String, String>{
              'All': isOromo ? 'Hunda' : 'All',
              'Exams': isOromo ? 'Qormaata' : 'Exams',
              'Assignments': isOromo ? 'Hojii manaa' : 'Assignments',
              'Pending': isOromo ? 'Hin xumuramne' : 'Pending',
              'Completed': isOromo ? 'Xumurame' : 'Completed',
            };

            Color eventColor(String type) {
              switch (type.toLowerCase()) {
                case 'quiz':
                  return Colors.red;
                case 'midterm':
                  return Colors.orange.shade800;
                case 'final':
                  return Colors.deepPurple;
                case 'assignment':
                  return Colors.blue;
                case 'exam':
                  return Colors.deepOrange;
                default:
                  return Colors.teal;
              }
            }

            IconData eventIcon(String type) {
              switch (type.toLowerCase()) {
                case 'quiz':
                  return Icons.bolt;
                case 'assignment':
                  return Icons.assignment_outlined;
                case 'midterm':
                case 'final':
                case 'exam':
                  return Icons.school_outlined;
                default:
                  return Icons.event_note;
              }
            }

            String relativeDate(String rawDate) {
              final parsed = DateTime.tryParse(rawDate);
              if (parsed == null) return rawDate;

              final today = DateTime.now();
              final todayOnly = DateTime(today.year, today.month, today.day);
              final eventOnly = DateTime(parsed.year, parsed.month, parsed.day);
              final days = eventOnly.difference(todayOnly).inDays;

              if (days == 0) return isOromo ? "Har'a" : 'Today';
              if (days == 1) return isOromo ? 'Boru' : 'Tomorrow';
              if (days == -1) return isOromo ? 'Kaleessa' : 'Yesterday';
              if (days > 1) {
                return isOromo ? 'Guyyaa $days booda' : 'In $days days';
              }
              return isOromo
                  ? 'Guyyaa ${days.abs()} darbe'
                  : '${days.abs()} days ago';
            }

            return AlertDialog(
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
              contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              title: Row(
                children: [
                  const Icon(Icons.event_note, color: Colors.indigo),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isOromo
                          ? 'Qormaata fi Hojii Manaa'
                          : 'Exams and Assignments',
                    ),
                  ),
                  IconButton(
                    tooltip: isOromo ? 'Cufi' : 'Close',
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              content: SizedBox(
                width: 560,
                height: 500,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isOromo
                          ? "Guyyaa irratti hundaa'uun tartiibaan"
                          : 'Organized by date',
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: filterLabels.entries.map((entry) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(entry.value),
                              selected: selectedFilter == entry.key,
                              onSelected: (_) {
                                refreshDialog(() => selectedFilter = entry.key);
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: FutureBuilder<List<Map<String, Object?>>>(
                        future: eventsFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          if (snapshot.hasError) {
                            return Center(
                              child: Text(
                                isOromo
                                    ? 'Galmee banuu irratti dogoggorri uumame.'
                                    : 'Could not load academic events.',
                              ),
                            );
                          }

                          final events = List<Map<String, Object?>>.from(
                            snapshot.data ?? [],
                          );

                          events.sort((a, b) {
                            final dateA =
                                DateTime.tryParse('${a['eventDate'] ?? ''}') ??
                                DateTime(2100);
                            final dateB =
                                DateTime.tryParse('${b['eventDate'] ?? ''}') ??
                                DateTime(2100);
                            return dateA.compareTo(dateB);
                          });

                          final filteredEvents = events.where((event) {
                            final type = '${event['eventType'] ?? ''}'
                                .toLowerCase();
                            final completed = event['completed'] == 1;

                            switch (selectedFilter) {
                              case 'Exams':
                                return [
                                  'exam',
                                  'quiz',
                                  'midterm',
                                  'final',
                                ].contains(type);
                              case 'Assignments':
                                return type == 'assignment';
                              case 'Pending':
                                return !completed;
                              case 'Completed':
                                return completed;
                              default:
                                return true;
                            }
                          }).toList();

                          if (filteredEvents.isEmpty) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.event_available,
                                      size: 48,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      isOromo
                                          ? 'Galmeen filannoo kanaa hin jiru.'
                                          : 'No items in this filter yet.',
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }

                          return ListView.separated(
                            padding: const EdgeInsets.only(top: 8, bottom: 8),
                            itemCount: filteredEvents.length,
                            separatorBuilder: (_, index) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final event = filteredEvents[index];
                              final id = event['id'] as int;
                              final title = '${event['title'] ?? ''}';
                              final type = '${event['eventType'] ?? ''}';
                              final date = '${event['eventDate'] ?? ''}';
                              final description =
                                  '${event['description'] ?? ''}'.trim();
                              final completed = event['completed'] == 1;
                              final color = eventColor(type);

                              String courseName = '';
                              for (final course in courses) {
                                if (course['id'] == event['courseId']) {
                                  courseName = '${course['name'] ?? ''}';
                                  break;
                                }
                              }

                              return Card(
                                elevation: 1,
                                clipBehavior: Clip.antiAlias,
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      left: BorderSide(
                                        color: completed ? Colors.green : color,
                                        width: 5,
                                      ),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 8,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Checkbox(
                                              value: completed,
                                              onChanged: (checked) async {
                                                await db.updateAcademicEvent(
                                                  id,
                                                  {
                                                    'completed': checked == true
                                                        ? 1
                                                        : 0,
                                                    'status': checked == true
                                                        ? 'Completed'
                                                        : 'Pending',
                                                  },
                                                );
                                                await reloadEvents();
                                              },
                                            ),
                                            Icon(
                                              eventIcon(type),
                                              color: color,
                                              size: 22,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    title,
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16,
                                                      decoration: completed
                                                          ? TextDecoration
                                                                .lineThrough
                                                          : TextDecoration.none,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 5),
                                                  Wrap(
                                                    spacing: 6,
                                                    runSpacing: 4,
                                                    children: [
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 9,
                                                              vertical: 4,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: color
                                                              .withValues(
                                                                alpha: 0.12,
                                                              ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                20,
                                                              ),
                                                        ),
                                                        child: Text(
                                                          type,
                                                          style: TextStyle(
                                                            color: color,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      ),
                                                      Text(
                                                        relativeDate(date),
                                                        style: TextStyle(
                                                          color: completed
                                                              ? Colors.green
                                                              : color,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: isOromo
                                                  ? 'Haqi'
                                                  : 'Delete',
                                              icon: const Icon(
                                                Icons.delete_outline,
                                                color: Colors.red,
                                              ),
                                              onPressed: () async {
                                                final confirm = await showDialog<bool>(
                                                  context: dialogContext,
                                                  builder: (confirmContext) =>
                                                      AlertDialog(
                                                        title: Text(
                                                          isOromo
                                                              ? 'Haqi?'
                                                              : 'Delete event?',
                                                        ),
                                                        content: Text(
                                                          isOromo
                                                              ? 'Galmee kana haquu barbaaddaa?'
                                                              : 'Are you sure you want to delete this item?',
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                  confirmContext,
                                                                  false,
                                                                ),
                                                            child: Text(
                                                              isOromo
                                                                  ? 'Dhiisi'
                                                                  : 'Cancel',
                                                            ),
                                                          ),
                                                          FilledButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                  confirmContext,
                                                                  true,
                                                                ),
                                                            child: Text(
                                                              isOromo
                                                                  ? 'Haqi'
                                                                  : 'Delete',
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                );

                                                if (confirm == true) {
                                                  await db.deleteAcademicEvent(
                                                    id,
                                                  );
                                                  await reloadEvents();
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 48,
                                            right: 8,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  const Icon(
                                                    Icons.calendar_today,
                                                    size: 14,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(child: Text(date)),
                                                ],
                                              ),
                                              if (courseName.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.school_outlined,
                                                      size: 14,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(courseName),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                              if (description.isNotEmpty) ...[
                                                const SizedBox(height: 8),
                                                Container(
                                                  width: double.infinity,
                                                  padding: const EdgeInsets.all(
                                                    9,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .surfaceContainerHighest
                                                        .withValues(alpha: 0.5),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const Icon(
                                                        Icons
                                                            .sticky_note_2_outlined,
                                                        size: 16,
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Expanded(
                                                        child: Text(
                                                          description,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                FilledButton.icon(
                  onPressed: addEvent,
                  icon: const Icon(Icons.add),
                  label: Text(isOromo ? 'Dabali' : 'Add'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(isOromo ? 'Cufi' : 'Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showCoursesPage() async {
    if (!mounted) return;

    final courses = await PlannerDatabase.instance.getCourses();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (listContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.school_outlined, color: Colors.indigo),
            const SizedBox(width: 10),
            Expanded(child: Text(isOromo ? 'Koorsiiwwan koo' : 'My courses')),
          ],
        ),
        content: SizedBox(
          width: 650,
          child: courses.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.menu_book_outlined, size: 52),
                      const SizedBox(height: 12),
                      Text(
                        isOromo
                            ? 'Koorsiin ammaaf hin galmoofne.'
                            : 'No courses have been registered yet.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: courses.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final course = courses[index];
                    final name = course['name'] as String? ?? '';
                    final code = course['code'] as String? ?? '';
                    final semester = course['semester'] as String? ?? '';
                    final year = course['academicYear'] as String? ?? '';
                    final department = course['department'] as String? ?? '';
                    final instructor = course['instructor'] as String? ?? '';
                    final credits = course['creditHours']?.toString() ?? '0';
                    final grade = course['targetGrade'] as String? ?? '';

                    final details = [
                      if (code.isNotEmpty) code,
                      if (semester.isNotEmpty) semester,
                      if (year.isNotEmpty) year,
                      if (department.isNotEmpty) department,
                      if (credits != '0' && credits != '0.0') '$credits Cr.Hr',
                      if (grade.isNotEmpty) 'Target: $grade',
                      if (instructor.isNotEmpty) instructor,
                    ];

                    return Card(
                      elevation: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.indigo.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.menu_book_outlined,
                                color: Colors.indigo,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  if (details.isNotEmpty) ...[
                                    const SizedBox(height: 5),
                                    Text(
                                      details.join(' â€¢ '),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: isOromo ? 'Filannoo' : 'Options',
                              onSelected: (action) async {
                                final id = course['id'] as int?;
                                if (id == null) return;

                                if (action == 'edit') {
                                  Navigator.of(listContext).pop();
                                  await _showAddCourseDialog(course: course);
                                } else if (action == 'delete') {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (confirmContext) => AlertDialog(
                                      title: Text(
                                        isOromo
                                            ? 'Koorsii haquu?'
                                            : 'Delete course?',
                                      ),
                                      content: Text(
                                        isOromo
                                            ? 'Koorsii "$name" haquu barbaaddaa?'
                                            : 'Delete "$name"?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(
                                            confirmContext,
                                            false,
                                          ),
                                          child: Text(
                                            isOromo ? 'Dhiisi' : 'Cancel',
                                          ),
                                        ),
                                        FilledButton(
                                          onPressed: () => Navigator.pop(
                                            confirmContext,
                                            true,
                                          ),
                                          child: Text(
                                            isOromo ? 'Haqi' : 'Delete',
                                          ),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm == true) {
                                    await PlannerDatabase.instance.deleteCourse(
                                      id,
                                    );
                                    if (listContext.mounted) {
                                      Navigator.of(listContext).pop();
                                    }
                                    if (mounted) await _showCoursesPage();
                                  }
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      const Icon(Icons.edit_outlined, size: 20),
                                      const SizedBox(width: 8),
                                      Text(isOromo ? 'Gulaali' : 'Edit'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(isOromo ? 'Haqi' : 'Delete'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(listContext).pop(),
            child: Text(isOromo ? 'Cufi' : 'Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(listContext).pop();
              await _showAddCourseDialog();
            },
            icon: const Icon(Icons.add),
            label: Text(isOromo ? 'Koorsii dabali' : 'Add course'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddCourseDialog({Map<String, Object?>? course}) async {
    if (!mounted) return;

    final isEditing = course != null;
    final nameController = TextEditingController(
      text: course?['name'] as String? ?? '',
    );
    final codeController = TextEditingController(
      text: course?['code'] as String? ?? '',
    );
    final departmentController = TextEditingController(
      text: course?['department'] as String? ?? '',
    );
    final yearController = TextEditingController(
      text:
          course?['academicYear'] as String? ??
          '${DateTime.now().year}/${DateTime.now().year + 1}',
    );
    final instructorController = TextEditingController(
      text: course?['instructor'] as String? ?? '',
    );
    final notesController = TextEditingController(
      text: course?['notes'] as String? ?? '',
    );
    final creditController = TextEditingController(
      text: course?['creditHours']?.toString() ?? '3',
    );

    String semester = course?['semester'] as String? ?? 'Sem 2';
    String targetGrade = course?['targetGrade'] as String? ?? '';
    bool saving = false;
    bool saved = false;

    final departments = [
      'Software Engineering',
      'Computer Science',
      'Information Technology',
      'Information Systems',
      'Electrical Engineering',
      'Civil Engineering',
      'Other',
    ];

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            scrollable: true,
            title: Row(
              children: [
                const Icon(Icons.school_outlined, color: Colors.indigo),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isEditing
                        ? (isOromo ? 'Koorsii gulaali' : 'Edit course')
                        : (isOromo
                              ? 'Odeeffannoo Koorsii'
                              : 'Course Information'),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 600,
              height: (MediaQuery.sizeOf(dialogContext).height * 0.55).clamp(
                220.0,
                500.0,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isOromo
                          ? '1. ODEEFFANNOO BARNOOTAA'
                          : '1. ACADEMIC INFORMATION',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue:
                          [
                                '${DateTime.now().year}/${DateTime.now().year + 1}',
                                '${DateTime.now().year - 1}/${DateTime.now().year}',
                                course?['academicYear'] as String? ?? '',
                              ]
                              .where((v) => v.isNotEmpty)
                              .toSet()
                              .contains(yearController.text)
                          ? yearController.text
                          : '${DateTime.now().year}/${DateTime.now().year + 1}',
                      decoration: InputDecoration(
                        labelText: isOromo ? 'Bara barnootaa' : 'Academic year',
                        border: const OutlineInputBorder(),
                      ),
                      items:
                          [
                            '${DateTime.now().year}/${DateTime.now().year + 1}',
                            '${DateTime.now().year - 1}/${DateTime.now().year}',
                          ].toSet().map((year) {
                            return DropdownMenuItem(
                              value: year,
                              child: Text(year),
                            );
                          }).toList(),
                      onChanged: saving
                          ? null
                          : (value) {
                              if (value != null) {
                                yearController.text = value;
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isOromo ? 'Semisteera' : 'Semester',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Wrap(
                      spacing: 4,
                      children: ['Sem 1', 'Sem 2', 'Summer'].map((value) {
                        return ChoiceChip(
                          label: Text(value),
                          selected: semester == value,
                          onSelected: saving
                              ? null
                              : (_) => setDialogState(() => semester = value),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue:
                          departments.contains(departmentController.text)
                          ? departmentController.text
                          : 'Other',
                      decoration: InputDecoration(
                        labelText: isOromo ? 'Mummee' : 'Department',
                        border: const OutlineInputBorder(),
                      ),
                      items: departments.map((department) {
                        return DropdownMenuItem(
                          value: department,
                          child: Text(department),
                        );
                      }).toList(),
                      onChanged: saving
                          ? null
                          : (value) {
                              if (value != null && value != 'Other') {
                                departmentController.text = value;
                              } else if (value == 'Other') {
                                departmentController.clear();
                              }
                              setDialogState(() {});
                            },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: departmentController,
                      enabled: !saving,
                      decoration: InputDecoration(
                        labelText: isOromo
                            ? "Mummee (yoo kan biraa ta'e barreessi)"
                            : 'Department (enter another if needed)',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      isOromo ? '2. ODEEFFANNOO KOORSII' : '2. COURSE DETAILS',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: nameController,
                      enabled: !saving,
                      decoration: InputDecoration(
                        labelText: isOromo
                            ? 'Maqaa koorsii *'
                            : 'Course title *',
                        hintText: 'e.g. Web Development',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: codeController,
                      enabled: !saving,
                      decoration: InputDecoration(
                        labelText: isOromo ? 'Koodii koorsii' : 'Course code',
                        hintText: 'e.g. SEng-3011',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: creditController,
                      enabled: !saving,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: isOromo
                            ? 'Credit hours / ECTS'
                            : 'Credit hours / ECTS',
                        hintText: 'e.g. 3',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: targetGrade.isEmpty ? null : targetGrade,
                      decoration: InputDecoration(
                        labelText: isOromo
                            ? 'Kaayyoo qabxii (Target grade)'
                            : 'Target grade',
                        border: const OutlineInputBorder(),
                      ),
                      items: ['A+', 'A', 'B+', 'B', 'C+', 'C', 'D', 'F']
                          .map(
                            (grade) => DropdownMenuItem(
                              value: grade,
                              child: Text(grade),
                            ),
                          )
                          .toList(),
                      onChanged: saving
                          ? null
                          : (value) =>
                                setDialogState(() => targetGrade = value ?? ''),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      isOromo
                          ? '3. ODEEFFANNOO BARSIISAA'
                          : '3. INSTRUCTOR INFORMATION',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: instructorController,
                      enabled: !saving,
                      decoration: InputDecoration(
                        labelText: isOromo
                            ? 'Maqaa barsiisaa'
                            : 'Instructor name',
                        hintText: 'Dr. / Mr. / Ms.',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      enabled: !saving,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: isOromo
                            ? 'Yaadannoo dabalataa'
                            : 'Additional notes',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: Text(isOromo ? 'Dhiisi' : 'Cancel'),
              ),
              FilledButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        final name = nameController.text.trim();
                        final credits = double.tryParse(
                          creditController.text.trim(),
                        );

                        if (name.isEmpty || credits == null || credits < 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                isOromo
                                    ? 'Maqaa koorsii galchi; credit hour sirreessi.'
                                    : 'Enter a course title and valid credit hours.',
                              ),
                            ),
                          );
                          return;
                        }

                        setDialogState(() => saving = true);
                        try {
                          final data = <String, Object?>{
                            'name': name,
                            'code': codeController.text.trim(),
                            'department': departmentController.text.trim(),
                            'semester': semester,
                            'academicYear': yearController.text.trim(),
                            'instructor': instructorController.text.trim(),
                            'creditHours': credits,
                            'targetGrade': targetGrade,
                            'notes': notesController.text.trim(),
                          };

                          if (isEditing) {
                            await PlannerDatabase.instance.updateCourse(
                              course['id'] as int,
                              data,
                            );
                          } else {
                            await PlannerDatabase.instance.insertCourse(data);
                          }

                          saved = true;
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                        } catch (error) {
                          setDialogState(() => saving = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${isOromo ? 'Kuusuu hin dandeenye' : 'Could not save'}: $error',
                                ),
                              ),
                            );
                          }
                        }
                      },
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  saving
                      ? (isOromo ? 'Kuusaa jira...' : 'Saving...')
                      : (isOromo ? 'Kuusi' : 'Save'),
                ),
              ),
            ],
          ),
        ),
      );

      if (saved && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isOromo
                  ? (isEditing
                        ? 'Koorsiin sirreeffameera.'
                        : 'Koorsiin kuufameera.')
                  : (isEditing
                        ? 'Course updated successfully.'
                        : 'Course saved successfully.'),
            ),
          ),
        );
        await _showCoursesPage();
      }
    } finally {
      nameController.dispose();
      codeController.dispose();
      departmentController.dispose();
      yearController.dispose();
      instructorController.dispose();
      notesController.dispose();
      creditController.dispose();
    }
  }

  String _timetableDayName(int day) {
    const english = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const oromo = [
      'Wiixata',
      'Kibxata',
      'Roobii',
      'Kamiisa',
      'Jimaata',
      'Sanbata',
      'Dilbata',
    ];
    return isOromo ? oromo[day - 1] : english[day - 1];
  }

  String _timetableTime(int hour, int minute) {
    final time = TimeOfDay(hour: hour, minute: minute);
    return time.format(context);
  }

  Future<void> _showTimetablePage() async {
    if (!mounted) return;

    final courses = await PlannerDatabase.instance.getCourses();
    final entries = await PlannerDatabase.instance.getTimetable();
    if (!mounted) return;

    final courseNames = <int, String>{
      for (final course in courses)
        if (course['id'] is int)
          course['id'] as int: (course['name'] ?? '').toString(),
    };

    final today = DateTime.now().weekday;
    int selectedDay = today;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, refresh) {
            final dayEntries =
                entries
                    .where((entry) => entry['dayOfWeek'] == selectedDay)
                    .toList()
                  ..sort((a, b) {
                    final aMinutes =
                        (a['startHour'] as int) * 60 +
                        (a['startMinute'] as int);
                    final bMinutes =
                        (b['startHour'] as int) * 60 +
                        (b['startMinute'] as int);
                    return aMinutes.compareTo(bMinutes);
                  });

            Color sessionColor(String type) {
              switch (type.toLowerCase()) {
                case 'lab':
                  return Colors.deepPurple;
                case 'tutorial':
                  return Colors.teal;
                case 'break':
                  return Colors.green;
                case 'exam':
                case 'quiz':
                  return Colors.red;
                default:
                  return Colors.blue;
              }
            }

            IconData sessionIcon(String type) {
              switch (type.toLowerCase()) {
                case 'lab':
                  return Icons.biotech_outlined;
                case 'tutorial':
                  return Icons.menu_book_outlined;
                case 'break':
                  return Icons.coffee_outlined;
                case 'exam':
                case 'quiz':
                  return Icons.assignment_outlined;
                default:
                  return Icons.school_outlined;
              }
            }

            final dayShortNames = isOromo
                ? ['Wiix', 'Kib', 'Roo', 'Kam', 'Jim', 'San', 'Dil']
                : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

            return AlertDialog(
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
              contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              title: Row(
                children: [
                  const Icon(
                    Icons.calendar_view_week_rounded,
                    color: Color(0xFF159B72),
                    size: 28,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      isOromo ? 'Sagantaa Torbanii' : 'Weekly Timetable',
                    ),
                  ),
                  IconButton(
                    tooltip: isOromo ? 'Cufi' : 'Close',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              content: SizedBox(
                width: 650,
                height: 510,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: isOromo ? 'Guyyaa duraa' : 'Previous day',
                          onPressed: () {
                            refresh(() {
                              selectedDay = selectedDay == 1
                                  ? 7
                                  : selectedDay - 1;
                            });
                          },
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: List.generate(7, (index) {
                                final day = index + 1;
                                final selected = selectedDay == day;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  child: ChoiceChip(
                                    label: Text(dayShortNames[index]),
                                    selected: selected,
                                    onSelected: (_) {
                                      refresh(() => selectedDay = day);
                                    },
                                  ),
                                );
                              }),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: isOromo ? 'Guyyaa itti aanu' : 'Next day',
                          onPressed: () {
                            refresh(() {
                              selectedDay = selectedDay == 7
                                  ? 1
                                  : selectedDay + 1;
                            });
                          },
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF7F2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.schedule, color: Color(0xFF159B72)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_timetableDayName(selectedDay)} Â· '
                              '${dayEntries.length} '
                              '${isOromo ? 'sagantaa' : 'entries'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: dayEntries.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.event_available_outlined,
                                      size: 54,
                                      color: Color(0xFF159B72),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      isOromo
                                          ? 'Guyyaa kanaaf sagantaan hin jiru.'
                                          : 'No classes scheduled for this day.',
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      isOromo
                                          ? 'Sagantaa haaraa dabaluuf tuqi.'
                                          : 'Add a class or appointment to get started.',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: dayEntries.length,
                              separatorBuilder: (_, index) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final entry = dayEntries[index];
                                final id = entry['id'] as int?;
                                final courseId = entry['courseId'] as int?;
                                final courseName =
                                    courseNames[courseId] ??
                                    (isOromo
                                        ? 'Koorsii hin filatamne'
                                        : 'No course selected');

                                final startHour = entry['startHour'] as int;
                                final startMinute = entry['startMinute'] as int;
                                final endHour = entry['endHour'] as int;
                                final endMinute = entry['endMinute'] as int;

                                final startTime = _timetableTime(
                                  startHour,
                                  startMinute,
                                );
                                final endTime = _timetableTime(
                                  endHour,
                                  endMinute,
                                );

                                final room = (entry['room'] ?? '')
                                    .toString()
                                    .trim();
                                final type = (entry['sessionType'] ?? 'Lecture')
                                    .toString();
                                final notes = (entry['notes'] ?? '')
                                    .toString()
                                    .trim();

                                final color = sessionColor(type);
                                final sessionTypes = <String, String>{
                                  'Lecture': isOromo ? 'Barumsa' : 'Lecture',
                                  'Lab': isOromo
                                      ? 'Laaboraatorii'
                                      : 'Lab / Practical',
                                  'Tutorial': isOromo ? 'Shaakala' : 'Tutorial',
                                  'Break': isOromo ? 'Boqonnaa' : 'Break',
                                  'Exam': isOromo ? 'Qormaata' : 'Exam',
                                  'Quiz': 'Quiz',
                                };

                                return Card(
                                  elevation: 1,
                                  clipBehavior: Clip.antiAlias,
                                  child: IntrinsicHeight(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Container(
                                          width: 82,
                                          color: color.withValues(alpha: 0.10),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 12,
                                          ),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                startTime,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: color,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              const Padding(
                                                padding: EdgeInsets.symmetric(
                                                  vertical: 5,
                                                ),
                                                child: Icon(
                                                  Icons.arrow_downward,
                                                  size: 14,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                              Text(
                                                endTime,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(width: 4, color: color),
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              12,
                                              10,
                                              6,
                                              10,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Icon(
                                                      sessionIcon(type),
                                                      color: color,
                                                      size: 21,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        courseName,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 15,
                                                        ),
                                                      ),
                                                    ),
                                                    PopupMenuButton<String>(
                                                      tooltip: isOromo
                                                          ? 'Hojii'
                                                          : 'Actions',
                                                      padding: EdgeInsets.zero,
                                                      onSelected: (action) async {
                                                        if (action == 'edit' &&
                                                            id != null) {
                                                          Navigator.of(
                                                            dialogContext,
                                                          ).pop();
                                                          await _showTimetableEntryDialog(
                                                            entry: entry,
                                                          );
                                                        }

                                                        if (action ==
                                                                'delete' &&
                                                            id != null) {
                                                          final confirm = await showDialog<bool>(
                                                            context:
                                                                dialogContext,
                                                            builder: (confirmContext) => AlertDialog(
                                                              title: Text(
                                                                isOromo
                                                                    ? 'Sagantaa haquu?'
                                                                    : 'Delete timetable entry?',
                                                              ),
                                                              content: Text(
                                                                isOromo
                                                                    ? 'Sagantaa kana haquu barbaaddaa?'
                                                                    : 'Are you sure you want to delete this entry?',
                                                              ),
                                                              actions: [
                                                                TextButton(
                                                                  onPressed: () =>
                                                                      Navigator.pop(
                                                                        confirmContext,
                                                                        false,
                                                                      ),
                                                                  child: Text(
                                                                    isOromo
                                                                        ? 'Dhiisi'
                                                                        : 'Cancel',
                                                                  ),
                                                                ),
                                                                FilledButton(
                                                                  onPressed: () =>
                                                                      Navigator.pop(
                                                                        confirmContext,
                                                                        true,
                                                                      ),
                                                                  child: Text(
                                                                    isOromo
                                                                        ? 'Haqi'
                                                                        : 'Delete',
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          );

                                                          if (confirm == true) {
                                                            await PlannerDatabase
                                                                .instance
                                                                .deleteTimetableEntry(
                                                                  id,
                                                                );
                                                            if (dialogContext
                                                                .mounted) {
                                                              Navigator.of(
                                                                dialogContext,
                                                              ).pop();
                                                            }
                                                            if (mounted) {
                                                              await _showTimetablePage();
                                                            }
                                                          }
                                                        }
                                                      },
                                                      itemBuilder: (_) => [
                                                        PopupMenuItem(
                                                          value: 'edit',
                                                          child: Text(
                                                            isOromo
                                                                ? 'Gulaali'
                                                                : 'Edit',
                                                          ),
                                                        ),
                                                        PopupMenuItem(
                                                          value: 'delete',
                                                          child: Text(
                                                            isOromo
                                                                ? 'Haqi'
                                                                : 'Delete',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 5),
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 4,
                                                  children: [
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: color.withValues(
                                                          alpha: 0.12,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              20,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        sessionTypes[type] ??
                                                            type,
                                                        style: TextStyle(
                                                          color: color,
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                    if (room.isNotEmpty)
                                                      Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          const Icon(
                                                            Icons
                                                                .location_on_outlined,
                                                            size: 14,
                                                          ),
                                                          const SizedBox(
                                                            width: 3,
                                                          ),
                                                          Text(
                                                            room,
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 12,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                  ],
                                                ),
                                                if (notes.isNotEmpty) ...[
                                                  const SizedBox(height: 8),
                                                  Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const Icon(
                                                        Icons.notes,
                                                        size: 15,
                                                        color: Colors.grey,
                                                      ),
                                                      const SizedBox(width: 5),
                                                      Expanded(
                                                        child: Text(
                                                          notes,
                                                          style: Theme.of(
                                                            context,
                                                          ).textTheme.bodySmall,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(isOromo ? 'Cufi' : 'Close'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    await _showTimetableEntryDialog();
                  },
                  icon: const Icon(Icons.add),
                  label: Text(
                    isOromo
                        ? 'Barnoota / Beellama dabali'
                        : 'Add class / appointment',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showTimetableEntryDialog({Map<String, Object?>? entry}) async {
    if (!mounted) return;

    final courses = await PlannerDatabase.instance.getCourses();
    if (!mounted) return;

    final roomController = TextEditingController(
      text: (entry?['room'] ?? '').toString(),
    );
    final notesController = TextEditingController(
      text: (entry?['notes'] ?? '').toString(),
    );

    int selectedDay = (entry?['dayOfWeek'] as int?) ?? DateTime.monday;
    int? selectedCourseId = entry?['courseId'] as int?;
    if (selectedCourseId == null && courses.isNotEmpty) {
      selectedCourseId = courses.first['id'] as int?;
    }

    TimeOfDay startTime = TimeOfDay(
      hour: (entry?['startHour'] as int?) ?? 8,
      minute: (entry?['startMinute'] as int?) ?? 0,
    );
    TimeOfDay endTime = TimeOfDay(
      hour: (entry?['endHour'] as int?) ?? 9,
      minute: (entry?['endMinute'] as int?) ?? 0,
    );
    String sessionType = (entry?['sessionType'] ?? 'Lecture').toString();

    final sessionTypes = <String, String>{
      'Lecture': isOromo ? 'Barumsa' : 'Lecture',
      'Lab': isOromo ? 'Laaboraatorii' : 'Lab',
      'Tutorial': isOromo ? 'Shaakala' : 'Tutorial',
    };

    final saved = await showDialog<bool>(
      context: context,
      builder: (formContext) => StatefulBuilder(
        builder: (formContext, setFormState) => AlertDialog(
          title: Text(
            entry == null
                ? (isOromo ? 'Sagantaa haaraa' : 'Add timetable entry')
                : (isOromo ? 'Sagantaa gulaali' : 'Edit timetable entry'),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    value: selectedDay,
                    decoration: InputDecoration(
                      labelText: isOromo ? 'Guyyaa' : 'Day',
                      prefixIcon: const Icon(Icons.calendar_today),
                      border: const OutlineInputBorder(),
                    ),
                    items: List.generate(
                      7,
                      (index) => DropdownMenuItem(
                        value: index + 1,
                        child: Text(_timetableDayName(index + 1)),
                      ),
                    ),
                    onChanged: (value) {
                      if (value != null) {
                        setFormState(() => selectedDay = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  if (courses.isNotEmpty)
                    DropdownButtonFormField<int>(
                      value: selectedCourseId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: isOromo ? 'Koorsii' : 'Course',
                        prefixIcon: const Icon(Icons.menu_book_rounded),
                        border: const OutlineInputBorder(),
                      ),
                      items: courses.map((course) {
                        final id = course['id'] as int;
                        final name = (course['name'] ?? '').toString();
                        final code = (course['code'] ?? '').toString();
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text(
                            code.isEmpty ? name : '$name ($code)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setFormState(() => selectedCourseId = value);
                      },
                    )
                  else
                    Text(
                      isOromo
                          ? 'Koorsii hin jiru. Sagantaa koorsii malee kuusuu dandeessa.'
                          : 'No courses yet. You can save a timetable entry without a course.',
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: formContext,
                              initialTime: startTime,
                            );
                            if (picked != null) {
                              setFormState(() => startTime = picked);
                            }
                          },
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text(
                            '${isOromo ? 'Jalqaba' : 'Start'}\n${startTime.format(formContext)}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: formContext,
                              initialTime: endTime,
                            );
                            if (picked != null) {
                              setFormState(() => endTime = picked);
                            }
                          },
                          icon: const Icon(Icons.stop_rounded),
                          label: Text(
                            '${isOromo ? 'Xumura' : 'End'}\n${endTime.format(formContext)}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: sessionType,
                    decoration: InputDecoration(
                      labelText: isOromo ? 'Gosa barnootaa' : 'Class type',
                      prefixIcon: const Icon(Icons.category_outlined),
                      border: const OutlineInputBorder(),
                    ),
                    items: sessionTypes.entries
                        .map(
                          (item) => DropdownMenuItem<String>(
                            value: item.key,
                            child: Text(item.value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setFormState(() => sessionType = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: roomController,
                    decoration: InputDecoration(
                      labelText: isOromo ? 'Kutaa / Laab' : 'Room / Lab',
                      prefixIcon: const Icon(Icons.location_on_outlined),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: isOromo ? 'Yaadannoo' : 'Notes',
                      prefixIcon: const Icon(Icons.notes_rounded),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(formContext).pop(false),
              child: Text(isOromo ? 'Haqi' : 'Cancel'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final startMinutes = startTime.hour * 60 + startTime.minute;
                final endMinutes = endTime.hour * 60 + endTime.minute;
                if (endMinutes == startMinutes) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isOromo
                            ? "Yeroon xumuraa yeroo jalqabaa booda ta'uu qaba."
                            : 'End time must be later than start time.',
                      ),
                    ),
                  );
                  return;
                }

                final values = <String, Object?>{
                  'courseId': selectedCourseId,
                  'dayOfWeek': selectedDay,
                  'startHour': startTime.hour,
                  'startMinute': startTime.minute,
                  'endHour': endTime.hour,
                  'endMinute': endTime.minute,
                  'room': roomController.text.trim(),
                  'sessionType': sessionType,
                  'notes': notesController.text.trim(),
                };

                try {
                  final id = entry?['id'] as int?;
                  if (id == null) {
                    await PlannerDatabase.instance.insertTimetableEntry(values);
                  } else {
                    await PlannerDatabase.instance.updateTimetableEntry(
                      id,
                      values,
                    );
                  }
                  if (formContext.mounted) {
                    Navigator.of(formContext).pop(true);
                  }
                } catch (error) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${isOromo ? 'Kuusuu hin dandeenye' : 'Could not save'}: $error',
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.save_rounded),
              label: Text(isOromo ? 'Kuusi' : 'Save'),
            ),
          ],
        ),
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 300));
    roomController.dispose();
    notesController.dispose();

    if (saved == true && mounted) {
      await _showTimetablePage();
    }
  }

  Widget _buildSettingsPage() {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            isOromo ? "Qindaa'ina" : 'Settings',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            isOromo
                ? 'Filannoowwan appii kee bulchi.'
                : 'Manage your app preferences.',
            style: const TextStyle(color: Colors.black54, fontSize: 15),
          ),
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: const Icon(Icons.language, color: Color(0xFF3977E8)),
              title: Text(isOromo ? 'Afaan' : 'Language'),
              subtitle: Text(isOromo ? 'Afaan Oromoo' : 'English'),
              trailing: PopupMenuButton<bool>(
                tooltip: isOromo ? 'Afaan jijjiiri' : 'Change language',
                onSelected: (value) {
                  _setLanguage(value);
                },
                itemBuilder: (context) => [
                  PopupMenuItem<bool>(
                    value: true,
                    child: Row(
                      children: [
                        if (isOromo) const Icon(Icons.check, size: 18),
                        if (isOromo) const SizedBox(width: 8),
                        const Text('Afaan Oromoo'),
                      ],
                    ),
                  ),
                  PopupMenuItem<bool>(
                    value: false,
                    child: Row(
                      children: [
                        if (!isOromo) const Icon(Icons.check, size: 18),
                        if (!isOromo) const SizedBox(width: 8),
                        const Text('English'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.backup_outlined,
                color: Color(0xFF3977E8),
              ),
              title: Text(isOromo ? 'Backup gochuu' : 'Export backup'),
              subtitle: Text(
                isOromo
                    ? 'Deetaa kee faayila JSON keessatti kuusi.'
                    : 'Save your app data to a JSON file.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _exportAppBackup,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(
                Icons.settings_backup_restore,
                color: Color(0xFF3977E8),
              ),
              title: Text(
                isOromo ? "Backup deebisanii fe'uu" : "Restore backup",
              ),
              subtitle: Text(
                isOromo
                    ? 'Faayila backup duraan kuufame irraa deetaa deebisi.'
                    : 'Restore data from a saved backup file.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _restoreAppBackup,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline, color: Color(0xFF3977E8)),
              title: Text(isOromo ? "Waa'ee appii" : 'About app'),
              subtitle: const Text('24-Hour Life Planner'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                showAboutDialog(
                  context: context,
                  applicationName: '24-Hour Life Planner',
                  children: [
                    Text(
                      isOromo
                          ? 'Appii hojii guyyaa kee karoorsuu, hordofuu fi xumura isaa ilaaluuf gargaaru.'
                          : 'An app to plan your day, track tasks, and review progress.',
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isOromo ? 'Haala hojii kee' : 'Your task overview',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.list_alt),
                    title: Text(isOromo ? 'Hojii waliigalaa' : 'Total tasks'),
                    trailing: Text('${tasks.length}'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.check_circle_outline,
                      color: Colors.green,
                    ),
                    title: Text(isOromo ? 'Xumurame' : 'Completed'),
                    trailing: Text('$completedCount'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.pending_actions,
                      color: Colors.orange,
                    ),
                    title: Text(isOromo ? 'Hafe' : 'Remaining'),
                    trailing: Text('${tasks.length - completedCount}'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _taskOccursOnDate(PlannerTask task, DateTime targetDate) {
    final taskDay = DateTime(task.date.year, task.date.month, task.date.day);
    final targetDay = DateTime(targetDate.year, targetDate.month, targetDate.day);

    if (targetDay.isBefore(taskDay)) return false;

    if (task.recurrence == 'Daily') return true;
    if (task.recurrence == 'Weekly') {
      return taskDay.weekday == targetDay.weekday;
    }

    return taskDay == targetDay;
  }
  Widget _buildCalendarPage() {
    final now = DateTime.now();
    final firstDay = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
    final daysInMonth = DateTime(
      _calendarMonth.year,
      _calendarMonth.month + 1,
      0,
    ).day;
    final startWeekday = firstDay.weekday % 7;

    final selectedTasks =
        tasks.where((task) {
          return _taskOccursOnDate(task, _selectedCalendarDate);
        }).toList()..sort((a, b) {
          final aMinutes = a.start.hour * 60 + a.start.minute;
          final bMinutes = b.start.hour * 60 + b.start.minute;
          return aMinutes.compareTo(bMinutes);
        });

    final monthNames = isOromo
        ? [
            'Amajjii',
            'Guraandhala',
            'Bitooteessa',
            'Ebla',
            'Caamsaa',
            'Waxabajjii',
            'Adooleessa',
            'Hagayya',
            'Fuulbana',
            'Onkololeessa',
            'Sadaasa',
            'Muddee',
          ]
        : [
            'January',
            'February',
            'March',
            'April',
            'May',
            'June',
            'July',
            'August',
            'September',
            'October',
            'November',
            'December',
          ];

    final weekdays = isOromo
        ? ['Dil', 'Wix', 'Qib', 'Rob', 'Kam', 'Jim', 'San']
        : ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            isOromo ? 'Kalaandarii' : 'Calendar',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            isOromo
                ? 'Guyyaa filadhu; hojiiwwan kee ilaali.'
                : 'Choose a date to see your tasks.',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.black.withAlpha(12)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _calendarMonth = DateTime(
                            _calendarMonth.year,
                            _calendarMonth.month - 1,
                            1,
                          );
                          _selectedCalendarDate = DateTime(
                            _calendarMonth.year,
                            _calendarMonth.month,
                            1,
                          );
                        });
                      },
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        '${monthNames[_calendarMonth.month - 1]} ${_calendarMonth.year}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _calendarMonth = DateTime(
                            _calendarMonth.year,
                            _calendarMonth.month + 1,
                            1,
                          );
                          _selectedCalendarDate = DateTime(
                            _calendarMonth.year,
                            _calendarMonth.month,
                            1,
                          );
                        });
                      },
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: weekdays
                      .map(
                        (day) => Expanded(
                          child: Center(
                            child: Text(
                              day,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.black54,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: startWeekday + daysInMonth,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 5,
                    crossAxisSpacing: 5,
                  ),
                  itemBuilder: (context, cellIndex) {
                    final day = cellIndex - startWeekday + 1;

                    if (day < 1 || day > daysInMonth) {
                      return const SizedBox.shrink();
                    }

                    final date = DateTime(
                      _calendarMonth.year,
                      _calendarMonth.month,
                      day,
                    );

                    final isSelected =
                        date.year == _selectedCalendarDate.year &&
                        date.month == _selectedCalendarDate.month &&
                        date.day == _selectedCalendarDate.day;

                    final isToday =
                        date.year == now.year &&
                        date.month == now.month &&
                        date.day == now.day;

                    final hasTasks = tasks.any(
                      (task) => _taskOccursOnDate(task, date),
                    );

                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        setState(() => _selectedCalendarDate = date);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF3977E8)
                              : isToday
                              ? const Color(0xFFE8F0FF)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: isToday && !isSelected
                              ? Border.all(color: const Color(0xFF3977E8))
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$day',
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.black87,
                                fontWeight: isSelected || isToday
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            if (hasTasks)
                              Container(
                                margin: const EdgeInsets.only(top: 3),
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.white
                                      : const Color(0xFF3977E8),
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '${isOromo ? 'Hojiiwwan' : 'Tasks'}: ${twoDigits(_selectedCalendarDate.day)}/${twoDigits(_selectedCalendarDate.month)}/${_selectedCalendarDate.year}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          if (selectedTasks.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                isOromo
                    ? 'Guyyaa kanaaf hojii kuufame hin jiru.'
                    : 'No tasks saved for this date.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
            )
          else
            ...selectedTasks.map(
              (task) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black.withAlpha(12)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.circle,
                      size: 10,
                      color: Color(0xFF3977E8),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              decoration: task.completed
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${task.start.format(context)} - ${task.end.format(context)}',
                            style: const TextStyle(color: Colors.black54),
                          ),
                          if (task.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(task.description),
                          ],
                        ],
                      ),
                    ),
                    if (task.completed)
                      const Icon(Icons.check_circle, color: Colors.green)
                    else
                      const Icon(Icons.schedule, color: Colors.orange),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReportsPage() {
    final totalTasks = tasks.length;
    final finishedTasks = completedCount;
    final pendingTasks = totalTasks - finishedTasks;
    final progress = totalTasks == 0 ? 0.0 : finishedTasks / totalTasks;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            isOromo ? 'Gabaasa Hojii' : 'Task Reports',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF17233C),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isOromo
                ? 'Haala hojiiwwan kee asitti ilaali.'
                : 'Review the status of your tasks here.',
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3977E8), Color(0xFF635BDF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOromo ? 'Milkaa\'ina waliigalaa' : 'Overall completion',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 16),
                Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 38,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: Colors.white30,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  isOromo
                      ? '$finishedTasks / $totalTasks hojii xumurame'
                      : '$finishedTasks of $totalTasks tasks completed',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  icon: Icons.check_circle_outline,
                  iconColor: const Color(0xFF159B72),
                  value: '$finishedTasks',
                  label: isOromo ? 'Xumurame' : 'Completed',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryCard(
                  icon: Icons.pending_actions,
                  iconColor: const Color(0xFFEA9635),
                  value: '$pendingTasks',
                  label: isOromo ? 'Hafe' : 'Remaining',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryCard(
                  icon: Icons.list_alt,
                  iconColor: const Color(0xFF3977E8),
                  value: '$totalTasks',
                  label: isOromo ? 'Waliigala' : 'Total',
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          Text(
            isOromo ? 'Haala gabaasaa' : 'Report summary',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          if (totalTasks == 0)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black12),
              ),
              child: Text(
                isOromo
                    ? 'Hojiiwwan hin jiran. Jalqaba hojii haaraa dabali.'
                    : 'There are no tasks yet. Add a task to get started.',
                textAlign: TextAlign.center,
              ),
            )
          else ...[
            _ReportStatusRow(
              label: isOromo ? 'Hojii xumurame' : 'Completed tasks',
              count: finishedTasks,
              total: totalTasks,
              color: const Color(0xFF159B72),
            ),
            const SizedBox(height: 12),
            _ReportStatusRow(
              label: isOromo ? 'Hojii hin xumuramne' : 'Uncompleted tasks',
              count: pendingTasks,
              total: totalTasks,
              color: const Color(0xFFEA9635),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withAlpha(10)),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 9),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ReportStatusRow extends StatelessWidget {
  const _ReportStatusRow({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : count / total;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: Colors.black12,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}


