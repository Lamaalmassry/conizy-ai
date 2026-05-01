import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;

void main() {
  runApp(
    const Directionality(
      textDirection: TextDirection.rtl,
      child: ConizyApp(),
    ),
  );
}

class ConizyApp extends StatelessWidget {
  const ConizyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CONIZY',
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F7FC),
        fontFamily: 'Arial',
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const SplashScreen(),
    );
  }
}

void _showComingSoon(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('الميزة قيد التطوير')),
  );
}

class _ChatMessage {
  final String text;
  final bool isAi;
  const _ChatMessage({required this.text, required this.isAi});
}

class _ConizyAiService {
  // ضع هنا رابط Lambda/API Gateway الذي يستدعي Bedrock (Nova Micro).
  static const String _endpoint = 'https://kqhqjz42uq3qyfvtdroztd733e0skpgc.lambda-url.us-east-1.on.aws/';

  static Future<String> ask(String prompt) async {
    final uri = Uri.tryParse(_endpoint);
    if (uri == null || _endpoint.contains('YOUR-LAMBDA-URL')) {
      return 'الربط غير مكتمل بعد. أضيفي رابط Lambda هنا داخل _ConizyAiService.';
    }

    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': prompt}),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final serverReply = _extractReply(response.body);
        if (serverReply != null && serverReply.isNotEmpty) {
          return serverReply;
        }
        return _localFallbackReply(prompt);
      }

      final reply = _extractReply(response.body);
      if (reply != null && reply.isNotEmpty) return reply;
      return _localFallbackReply(prompt);
    } catch (_) {
      return _localFallbackReply(prompt);
    }
  }

  static String? _extractReply(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return (decoded['reply'] ?? decoded['output'] ?? decoded['message'] ?? '').toString().trim();
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static String _localFallbackReply(String prompt) {
    final text = prompt.trim();
    if (text.contains('نصيحة')) {
      return 'نصيحة سريعة: حددي سقف يومي للصرف، وأي مبلغ يتبقى انقليه فورًا للتوفير.';
    }
    if (text.contains('توقع') || text.contains('الشهر')) {
      return 'توقع مبدئي: استمري على نفس الوتيرة مع تخفيض بسيط 10% يوميًا لتتجنبي تجاوز الميزانية.';
    }
    if (text.contains('توفير') || text.contains('خطة')) {
      return 'خطة بسيطة: ابدئي بـ 20% توفير ثابت أول ما ينزل الدخل، ثم وزعي الباقي على الضروريات والمرن.';
    }
    return 'جاهز أساعدك. اكتبي هدفك المالي الحالي وأنا أعطيك خطوة عملية تبدأي فيها اليوم.';
  }
}

class _AppStorage {
  static const String _currentUserKey = 'current_user_email';
  static const String _incomeKey = 'monthly_income';
  static const String _savingPercentKey = 'saving_percent';
  static const String _expensesKey = 'expenses';
  static Database? _db;

  static String _normalizeEmail(String? email) {
    final e = (email ?? '').trim().toLowerCase();
    return e.isEmpty ? 'guest@local' : e;
  }

  static Future<String> _activeUser() async {
    final prefs = await SharedPreferences.getInstance();
    return _normalizeEmail(prefs.getString(_currentUserKey));
  }

  static String _scopedKey(String user, String key) => '$user::$key';

  static Future<void> setCurrentUser(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentUserKey, _normalizeEmail(email));
  }

  static Future<String> getCurrentUserName() async {
    final user = await _activeUser();
    final localPart = user.split('@').first.trim();
    if (localPart.isEmpty || localPart == 'guest') {
      return 'مستخدم';
    }
    return localPart;
  }

  static Future<Database> _getDb() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'conizy_local.db');
    _db = await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE expenses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_email TEXT NOT NULL,
            amount INTEGER NOT NULL,
            category TEXT NOT NULL,
            payment_method TEXT NOT NULL,
            note TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE goals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_email TEXT NOT NULL,
            name TEXT NOT NULL,
            goal_type TEXT NOT NULL,
            target_amount INTEGER NOT NULL,
            duration TEXT NOT NULL,
            reminder TEXT NOT NULL,
            saved_amount INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute("ALTER TABLE expenses ADD COLUMN user_email TEXT NOT NULL DEFAULT 'guest@local'");
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS goals (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_email TEXT NOT NULL,
              name TEXT NOT NULL,
              goal_type TEXT NOT NULL,
              target_amount INTEGER NOT NULL,
              duration TEXT NOT NULL,
              reminder TEXT NOT NULL,
              saved_amount INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL
            )
          ''');
        }
      },
    );
    await _migrateFromPrefsIfNeeded(_db!);
    return _db!;
  }

  static Future<void> _migrateFromPrefsIfNeeded(Database db) async {
    final migrated = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['migrated_v1'],
      limit: 1,
    );
    if (migrated.isNotEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final activeUser = _normalizeEmail(prefs.getString(_currentUserKey));
    final oldIncome = prefs.getInt(_incomeKey);
    final oldSaving = prefs.getDouble(_savingPercentKey);
    final oldExpenses = prefs.getStringList(_expensesKey) ?? <String>[];

    if (oldIncome != null) {
      await db.insert('settings', {'key': _scopedKey(activeUser, _incomeKey), 'value': '$oldIncome'},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    if (oldSaving != null) {
      await db.insert('settings', {'key': _scopedKey(activeUser, _savingPercentKey), 'value': '$oldSaving'},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    for (final encoded in oldExpenses) {
      try {
        final item = jsonDecode(encoded) as Map<String, dynamic>;
        await db.insert('expenses', {
          'user_email': activeUser,
          'amount': (item['amount'] as num?)?.toInt() ?? 0,
          'category': (item['category'] as String?) ?? 'أخرى',
          'payment_method': (item['paymentMethod'] as String?) ?? 'كاش',
          'note': (item['note'] as String?) ?? '',
          'created_at': (item['createdAt'] as String?) ?? DateTime.now().toIso8601String(),
        });
      } catch (_) {
        // Ignore malformed legacy records.
      }
    }

    await db.insert('settings', {'key': 'migrated_v1', 'value': '1'},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> saveMonthlyIncome(int value) async {
    final user = await _activeUser();
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_scopedKey(user, _incomeKey), value);
      return;
    }
    final db = await _getDb();
    await db.insert(
      'settings',
      {'key': _scopedKey(user, _incomeKey), 'value': '$value'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<int> getMonthlyIncome() async {
    final user = await _activeUser();
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_scopedKey(user, _incomeKey)) ?? 0;
    }
    final db = await _getDb();
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_scopedKey(user, _incomeKey)],
      limit: 1,
    );
    return int.tryParse(rows.isEmpty ? '' : '${rows.first['value']}') ?? 0;
  }

  static Future<void> saveSavingPercent(double value) async {
    final user = await _activeUser();
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_scopedKey(user, _savingPercentKey), value);
      return;
    }
    final db = await _getDb();
    await db.insert(
      'settings',
      {'key': _scopedKey(user, _savingPercentKey), 'value': '$value'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<double> getSavingPercent() async {
    final user = await _activeUser();
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble(_scopedKey(user, _savingPercentKey)) ?? 20;
    }
    final db = await _getDb();
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [_scopedKey(user, _savingPercentKey)],
      limit: 1,
    );
    return double.tryParse(rows.isEmpty ? '' : '${rows.first['value']}') ?? 20;
  }

  static Future<List<Map<String, dynamic>>> getExpenses() async {
    final user = await _activeUser();
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_scopedKey(user, _expensesKey)) ?? <String>[];
      return raw
          .map((item) => jsonDecode(item) as Map<String, dynamic>)
          .toList(growable: false);
    }
    final db = await _getDb();
    final rows = await db.query(
      'expenses',
      where: 'user_email = ?',
      whereArgs: [user],
      orderBy: 'created_at DESC',
    );
    return rows
        .map((row) => <String, dynamic>{
              'amount': row['amount'],
              'category': row['category'],
              'paymentMethod': row['payment_method'],
              'note': row['note'],
              'createdAt': row['created_at'],
            })
        .toList(growable: false);
  }

  static Future<void> addExpense({
    required int amount,
    required String category,
    required String paymentMethod,
    required String note,
  }) async {
    final user = await _activeUser();
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getStringList(_scopedKey(user, _expensesKey)) ?? <String>[];
      current.add(
        jsonEncode(<String, dynamic>{
          'amount': amount,
          'category': category,
          'paymentMethod': paymentMethod,
          'note': note,
          'createdAt': DateTime.now().toIso8601String(),
        }),
      );
      await prefs.setStringList(_scopedKey(user, _expensesKey), current);
      return;
    }
    final db = await _getDb();
    await db.insert('expenses', {
      'user_email': user,
      'amount': amount,
      'category': category,
      'payment_method': paymentMethod,
      'note': note,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> addGoal({
    required String name,
    required String goalType,
    required int targetAmount,
    required String duration,
    required String reminder,
  }) async {
    final user = await _activeUser();
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final key = _scopedKey(user, 'goals');
      final current = prefs.getStringList(key) ?? <String>[];
      current.add(jsonEncode({
        'name': name,
        'goalType': goalType,
        'targetAmount': targetAmount,
        'duration': duration,
        'reminder': reminder,
        'savedAmount': 0,
        'createdAt': DateTime.now().toIso8601String(),
      }));
      await prefs.setStringList(key, current);
      return;
    }
    final db = await _getDb();
    await db.insert('goals', {
      'user_email': user,
      'name': name,
      'goal_type': goalType,
      'target_amount': targetAmount,
      'duration': duration,
      'reminder': reminder,
      'saved_amount': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getGoals() async {
    final user = await _activeUser();
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final key = _scopedKey(user, 'goals');
      final raw = prefs.getStringList(key) ?? <String>[];
      return raw.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
    }
    final db = await _getDb();
    final rows = await db.query('goals', where: 'user_email = ?', whereArgs: [user], orderBy: 'created_at DESC');
    return rows
        .map((r) => <String, dynamic>{
              'name': r['name'],
              'goalType': r['goal_type'],
              'targetAmount': r['target_amount'],
              'duration': r['duration'],
              'reminder': r['reminder'],
              'savedAmount': r['saved_amount'],
              'createdAt': r['created_at'],
            })
        .toList(growable: false);
  }
}

class _HomeStats {
  final int monthlyIncome;
  final int totalExpenses;
  final int todayCoffeeExpense;
  final int suggestedSaving;

  const _HomeStats({
    required this.monthlyIncome,
    required this.totalExpenses,
    required this.todayCoffeeExpense,
    required this.suggestedSaving,
  });
}

class _AnalyticsData {
  final int monthlyIncome;
  final int monthSpent;
  final int projectedMonthSpent;
  final int predictedOverrun;
  final int dailyCutNeeded;
  final int weeklyAvg;
  final String topCategory;
  final int topCategoryPercent;
  final int coffeeSpent;
  final Map<String, int> categoryTotals;

  const _AnalyticsData({
    required this.monthlyIncome,
    required this.monthSpent,
    required this.projectedMonthSpent,
    required this.predictedOverrun,
    required this.dailyCutNeeded,
    required this.weeklyAvg,
    required this.topCategory,
    required this.topCategoryPercent,
    required this.coffeeSpent,
    required this.categoryTotals,
  });
}

Future<_AnalyticsData> _loadAnalyticsData() async {
  final income = await _AppStorage.getMonthlyIncome();
  final expenses = await _AppStorage.getExpenses();
  final now = DateTime.now();

  final monthExpenses = expenses.where((item) {
    final raw = item['createdAt'];
    if (raw is! String) return false;
    final dt = DateTime.tryParse(raw);
    return dt != null && dt.year == now.year && dt.month == now.month;
  }).toList();

  final totals = <String, int>{};
  var monthSpent = 0;
  for (final item in monthExpenses) {
    final amount = (item['amount'] as num?)?.toInt() ?? 0;
    final category = (item['category'] as String?) ?? 'أخرى';
    monthSpent += amount;
    totals[category] = (totals[category] ?? 0) + amount;
  }

  final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
  final elapsedDays = math.max(1, now.day);
  final projected = (monthSpent / elapsedDays * daysInMonth).round();
  final safeIncome = income > 0 ? income : 1000;
  final overrun = math.max(0, projected - safeIncome);
  final remainingDays = math.max(1, daysInMonth - now.day);
  final dailyCut = overrun == 0 ? 0 : (overrun / remainingDays).ceil();
  final weeklyAvg = (monthSpent / elapsedDays * 7).round();

  String topCategory = 'أخرى';
  var topAmount = 0;
  totals.forEach((category, value) {
    if (value > topAmount) {
      topAmount = value;
      topCategory = category;
    }
  });
  final topPercent = monthSpent == 0 ? 0 : ((topAmount / monthSpent) * 100).round();
  final coffeeSpent = totals['قهوة'] ?? 0;

  return _AnalyticsData(
    monthlyIncome: safeIncome,
    monthSpent: monthSpent,
    projectedMonthSpent: projected,
    predictedOverrun: overrun,
    dailyCutNeeded: dailyCut,
    weeklyAvg: weeklyAvg,
    topCategory: topCategory,
    topCategoryPercent: topPercent,
    coffeeSpent: coffeeSpent,
    categoryTotals: totals,
  );
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _didNavigate = false;

  void _openOnboarding() {
    if (_didNavigate) return;
    _didNavigate = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const OnboardingOneScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF6956A5),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openOnboarding,
        child: Stack(
          children: [
            Positioned(
              right: -40,
              top: 220,
              child: Container(
                width: 320,
                height: 160,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(38),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _SplashLogo(),
                  const SizedBox(height: 12),
                  const Text(
                    'Connect Insights. Act Easy.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplashLogo extends StatelessWidget {
  const _SplashLogo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 205.06,
      height: 45.55,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Positioned(
            left: 0,
            top: 3,
            child: SizedBox(
              width: 55,
              height: 39,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 9,
                    child: Transform.rotate(
                      angle: -0.22,
                      child: Container(
                        width: 28,
                        height: 22,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4E95CF),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    top: 4,
                    child: Transform.rotate(
                      angle: -0.14,
                      child: Container(
                        width: 30,
                        height: 26,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF04960),
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    top: 6,
                    child: Transform.rotate(
                      angle: -0.14,
                      child: Container(
                        width: 25,
                        height: 23,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 58,
            top: 4,
            child: RichText(
              text: const TextSpan(
                children: [
                  TextSpan(
                    text: 'CONIZY ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  TextSpan(
                    text: 'AI',
                    style: TextStyle(
                      color: Color(0xFFE24B4A),
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OnboardingOneScreen extends StatelessWidget {
  const OnboardingOneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF6956A5),
        body: SafeArea(
          child: Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: 412,
                height: 917,
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: ColoredBox(color: Color(0xFF6956A5)),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: -35,
                      child: Opacity(
                        opacity: 0.42,
                        child: Image.asset(
                          'assets/onboarding1_bg.png',
                          fit: BoxFit.cover,
                          height: 540,
                        ),
                      ),
                    ),
                    // Mask artifact lines on image edges.
                    const Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: ColoredBox(
                        color: Color(0xFF6956A5),
                        child: SizedBox(width: 26),
                      ),
                    ),
                    const Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: ColoredBox(
                        color: Color(0xFF6956A5),
                        child: SizedBox(width: 26),
                      ),
                    ),
                    const Positioned(
                      right: 42,
                      top: 250,
                      child: SizedBox(
                        width: 235,
                        child: Text(
                          'خلّي فلوسك\nتحكي قصتها',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 42,
                            fontWeight: FontWeight.w700,
                            height: 1.05,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 42,
                      top: 430,
                      child: SizedBox(
                        width: 245,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            InkWell(
                              onTap: () {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (_) => const Directionality(
                                      textDirection: TextDirection.rtl,
                                      child: OnboardingTwoScreen(),
                                    ),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(26),
                              child: Container(
                                width: 42,
                                height: 42,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.arrow_back,
                                  color: Color(0xFF6A56A5),
                                  size: 22,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'تابع مصروفك بذكاء، فهم\nعاداتك المالية، وحقق أهدافك.',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 84,
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 25,
                              height: 6,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(100),
                              ),
                            ),
                            const SizedBox(width: 3),
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: const Color(0xFFC8CAC0),
                                borderRadius: BorderRadius.circular(100),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      right: 24,
                      bottom: 34,
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => const Directionality(
                                textDirection: TextDirection.rtl,
                                child: LoginScreen(),
                              ),
                            ),
                          );
                        },
                        child: const Text(
                          'تخطي',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingDecorCard extends StatelessWidget {
  final double alpha;
  final bool highlight;
  const _OnboardingDecorCard({required this.alpha, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.52,
      child: Container(
        width: 658.43,
        height: 258.45,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(29.28),
          border: Border(
            left: BorderSide(color: Colors.white.withValues(alpha: 0.50), width: 2.93),
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.50), width: 2.93),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0x3F16182A),
              blurRadius: 58.56,
              offset: const Offset(0, 58.56),
            ),
          ],
          color: Colors.white.withValues(alpha: alpha),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(29.28),
          child: Stack(
          children: [
            Positioned(
              left: 0,
              top: -38,
              child: Container(
                width: 678.32,
                height: 391.63,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: highlight ? 0.10 : 0.06),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: highlight ? 0.12 : 0.08),
                      Colors.white.withValues(alpha: 0.02),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 29.28,
              top: 10,
              child: Text(
                'BANK NAME',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: highlight ? 0.32 : 0.26),
                  fontSize: 29.28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Positioned(
              left: 29.28,
              bottom: 46,
              child: Text(
                '1234 5678 9009 8765',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: highlight ? 0.34 : 0.24),
                  fontSize: 29.28,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1,
                ),
              ),
            ),
            Positioned(
              left: 29.28,
              bottom: 16,
              child: Text(
                'CARDHOLDER NAME',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: highlight ? 0.30 : 0.22),
                  fontSize: 20.5,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            Positioned(
              right: 44,
              bottom: 16,
              child: Text(
                '08/28',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: highlight ? 0.30 : 0.22),
                  fontSize: 20.5,
                ),
              ),
            ),
            Positioned(
              right: 112,
              bottom: 17,
              child: Text(
                'VALID\nTHRU',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: highlight ? 0.30 : 0.22),
                  fontSize: 8.8,
                  height: 0.95,
                ),
              ),
            ),
            Positioned(
              left: 29.28,
              top: 84,
              child: Container(
                width: 81.87,
                height: 47.27,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5.31),
                  border: Border.all(width: 1.02, color: const Color(0xFFC5AF76)),
                  gradient: const LinearGradient(
                    begin: Alignment(0.08, 0.41),
                    end: Alignment(1.00, 0.70),
                    colors: [Color(0xFFFFEB94), Color(0xFFDEA002)],
                  ),
                ),
              ),
            ),
            Positioned(
              right: 46,
              top: 84,
              child: Icon(
                Icons.wifi,
                size: 34,
                color: Colors.white.withValues(alpha: highlight ? 0.35 : 0.24),
              ),
            ),
            if (highlight)
              Positioned(
                left: 430,
                top: 50,
                child: Transform.rotate(
                  angle: -1.57,
                  child: Text(
                    'VISA',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.24),
                      fontSize: 56,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }
}

class OnboardingTwoScreen extends StatelessWidget {
  const OnboardingTwoScreen({super.key});
  static const AssetImage _onboardingImage = AssetImage('assets/onboarding2.png');

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF6956A5),
        body: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 412,
              height: 917,
              child: Stack(
                children: [
                  Positioned(
                    left: 78,
                    top: 62,
                    child: Container(
                      width: 256,
                      height: 302,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        image: const DecorationImage(image: _onboardingImage, fit: BoxFit.cover),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x44000000),
                            blurRadius: 12,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 242,
                    top: 476,
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const Directionality(
                              textDirection: TextDirection.rtl,
                              child: OnboardingThreeScreen(),
                            ),
                          ),
                        );
                      },
                      child: Container(
                        width: 100,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4961),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Text(
                          'ابدء الان',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w300),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 53,
                    top: 568,
                    child: SizedBox(
                      width: 306,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: const [
                          SizedBox(
                            width: 248,
                            child: Text(
                              'تحكم بمصاريفـــــك بنظرة أوضــــــــــــــح',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                          ),
                          SizedBox(height: 16),
                          SizedBox(
                            width: 248,
                            child: Text(
                              'تتبع نفقاتك اليومية بسهولة لتبني عادات مالية أفضــــــــــل\n',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w300,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 184,
                    top: 758,
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: const Color(0xFFC8CAC0),
                            borderRadius: BorderRadius.circular(100),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Container(
                          width: 25,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(100),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: const Color(0xFFC8CAC0),
                            borderRadius: BorderRadius.circular(100),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 22,
                    top: 835,
                    child: SizedBox(
                      width: 368,
                      height: 44,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 313,
                            top: 9,
                            child: InkWell(
                              onTap: () {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (_) => const Directionality(
                                      textDirection: TextDirection.rtl,
                                      child: LoginScreen(),
                                    ),
                                  ),
                                );
                              },
                              child: const Text(
                                'تخطي',
                                textAlign: TextAlign.right,
                                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w300),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: -3,
                            child: InkWell(
                              onTap: () {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (_) => const Directionality(
                                      textDirection: TextDirection.rtl,
                                      child: OnboardingThreeScreen(),
                                    ),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(24),
                              child: const CircleAvatar(
                                radius: 23.5,
                                backgroundColor: Colors.white,
                                child: Icon(Icons.arrow_back, color: Color(0xFF6956A5), size: 24),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OnboardingThreeScreen extends StatelessWidget {
  const OnboardingThreeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF6856A5),
        body: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 412,
              height: 917,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 120,
                    child: Container(width: 412, height: 2, color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  Positioned(
                    left: 0,
                    top: 230,
                    child: Container(width: 412, height: 2, color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  Positioned(
                    left: 0,
                    top: 340,
                    child: Container(width: 412, height: 2, color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  Positioned(
                    left: 301,
                    top: 58,
                    child: _onboardingNode(Icons.show_chart_rounded),
                  ),
                  Positioned(
                    left: 194,
                    top: 262,
                    child: _onboardingNode(Icons.public_rounded),
                  ),
                  Positioned(
                    left: 175,
                    top: 369,
                    child: _onboardingNode(Icons.account_balance_wallet_outlined),
                  ),
                  Positioned(
                    left: 42,
                    top: 371,
                    child: _onboardingNode(Icons.person_outline_rounded),
                  ),
                  Positioned(
                    left: 96,
                    top: 183,
                    child: _onboardingNode(Icons.savings_outlined),
                  ),
                  Positioned(
                    left: 241,
                    top: 183,
                    child: _onboardingNode(Icons.account_balance_wallet_rounded),
                  ),
                  Positioned(
                    left: 58,
                    top: 397,
                    child: SizedBox(
                      width: 256,
                      height: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 63,
                    top: 224,
                    child: Container(
                      width: 250,
                      height: 170,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 53,
                    top: 522,
                    child: SizedBox(
                      width: 306,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          SizedBox(
                            width: 306,
                            child: Text(
                              'ابدأ تبني عادات ماليـــــــة\nأفضل اليــــــــــــــــــــــــــوم!',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                height: 1.15,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'رؤى ذكية تساعدك تتحكم أكثـر\nوتصرف بوعي كل يوم',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w300,
                              height: 1.15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 184,
                    top: 758,
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: const Color(0xFFC8CAC0),
                            borderRadius: BorderRadius.circular(100),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: const Color(0xFFC8CAC0),
                            borderRadius: BorderRadius.circular(100),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Container(
                          width: 25,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(100),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 22,
                    top: 833,
                    child: SizedBox(
                      width: 368,
                      height: 44,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 313,
                            top: 9,
                            child: InkWell(
                              onTap: () {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (_) => const Directionality(
                                      textDirection: TextDirection.rtl,
                                      child: LoginScreen(),
                                    ),
                                  ),
                                );
                              },
                              child: const Text(
                                'تخطي',
                                textAlign: TextAlign.right,
                                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w300),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: -3,
                            child: InkWell(
                              onTap: () {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (_) => const Directionality(
                                      textDirection: TextDirection.rtl,
                                      child: LoginScreen(),
                                    ),
                                  ),
                                );
                              },
                              borderRadius: BorderRadius.circular(24),
                              child: const CircleAvatar(
                                radius: 23.5,
                                backgroundColor: Colors.white,
                                child: Icon(Icons.arrow_back, color: Color(0xFF6956A5), size: 24),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _onboardingNode(IconData icon) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFF8D7BCC),
        shape: BoxShape.circle,
        border: Border.all(width: 3, color: Colors.white),
        boxShadow: const [
          BoxShadow(color: Color(0x19000000), blurRadius: 4, offset: Offset(0, 4)),
        ],
      ),
      child: Icon(icon, size: 22, color: Colors.white),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 412,
              height: 917,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 38),
                child: Column(
                  children: [
                    const SizedBox(height: 96),
                    const _LoginBrandLogo(),
                    const SizedBox(height: 72),
                    const Text(
                      'تسجيل الدخول',
                      style: TextStyle(
                        color: Color(0xFF323232),
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _loginTabs(),
                    const SizedBox(height: 28),
                    _inputLine(
                      label: 'البريد الاكتروني',
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    _inputLine(
                      label: 'كلمة المرور',
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      trailing: IconButton(
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_outlined : Icons.remove_red_eye_outlined,
                          color: const Color(0xFF3C3D3D),
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: () async {
                          final email = _emailController.text.trim();
                          await _AppStorage.setCurrentUser(email);
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => const Directionality(
                                textDirection: TextDirection.rtl,
                                child: QuickSetupScreen(),
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6856A5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          elevation: 0,
                        ),
                        child: const Text(
                          'تسجيل دخول',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'نسيت كلمة المرور؟',
                      style: TextStyle(
                        color: Color(0xFF949496),
                        fontSize: 14,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: const [
                        Expanded(child: Divider(color: Color(0xFFE8E8E8))),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text('أو', style: TextStyle(color: Color(0xFF8B8884), fontSize: 11)),
                        ),
                        Expanded(child: Divider(color: Color(0xFFE8E8E8))),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      height: 55,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F7F7),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: const Color(0x7FC9C9C9)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text('المتابعة ب Google', style: TextStyle(color: Color(0xFF7F8888), fontSize: 15)),
                          SizedBox(width: 8),
                          Icon(Icons.g_mobiledata_rounded, color: Color(0xFF4285F4), size: 24),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loginTabs() {
    return Container(
      width: double.infinity,
      height: 53,
      decoration: BoxDecoration(
        color: const Color(0xFFF6F5F9),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Color(0x02000000), blurRadius: 20, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: Text('حساب جديد', style: TextStyle(color: const Color(0xFF949496), fontSize: 12)),
            ),
          ),
          Container(
            width: 159,
            height: 37,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(5),
              boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 25, offset: Offset(0, 15))],
            ),
            child: const Center(
              child: Text('تسجيل دخول', style: TextStyle(color: Color(0xFF686868), fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputLine({
    required String label,
    required TextEditingController controller,
    Widget? trailing,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (trailing != null) trailing,
            const Spacer(),
            Text(label, style: const TextStyle(color: Color(0xFF3C3D3D), fontSize: 12)),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          textAlign: TextAlign.right,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 6),
            border: InputBorder.none,
          ),
        ),
        const SizedBox(height: 10),
        const Divider(height: 1, color: Color(0xFFCCCCCC)),
      ],
    );
  }
}

class _LoginBrandLogo extends StatelessWidget {
  const _LoginBrandLogo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 158,
      height: 24,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 28,
            height: 18,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 4,
                  child: Transform.rotate(
                    angle: -0.18,
                    child: Container(
                      width: 14,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B9AF5),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 9,
                  top: 2,
                  child: Transform.rotate(
                    angle: -0.18,
                    child: Container(
                      width: 14,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4961),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          RichText(
            text: const TextSpan(
              children: [
                TextSpan(
                  text: 'CONIZY ',
                  style: TextStyle(
                    color: Color(0xFF6761A8),
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                TextSpan(
                  text: 'AI',
                  style: TextStyle(
                    color: Color(0xFFEF4961),
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class QuickSetupScreen extends StatefulWidget {
  const QuickSetupScreen({super.key});

  @override
  State<QuickSetupScreen> createState() => _QuickSetupScreenState();
}

class _QuickSetupScreenState extends State<QuickSetupScreen> {
  String _amount = '0';

  void _onDigitTap(String digit) {
    setState(() {
      if (_amount == '0') {
        _amount = digit;
      } else {
        _amount += digit;
      }
    });
  }

  void _onDelete() {
    setState(() {
      if (_amount.length <= 1) {
        _amount = '0';
      } else {
        _amount = _amount.substring(0, _amount.length - 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 412,
              height: 917,
              child: Stack(
                children: [
                  const Positioned(
                    top: 64,
                    right: 26,
                    child: SizedBox(
                      width: 222,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'كم دخلك الشهري؟',
                            style: TextStyle(color: Colors.black, fontSize: 20, fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'تقديري كمان مقبول — رح نساعدك تحسبه',
                            style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w400),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 26,
                    top: 153,
                    child: Container(
                      width: 361,
                      height: 180,
                      decoration: BoxDecoration(
                        color: const Color(0x3F6856A5),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: const Color(0x77411C5D)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'دخلك الشهري',
                            style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w400),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            '${_amount}₪',
                            style: const TextStyle(color: Colors.black, fontSize: 40, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 64,
                    top: 370,
                    child: SizedBox(
                      width: 284,
                      child: Wrap(
                        spacing: 37,
                        runSpacing: 20,
                        children: [
                          for (final n in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
                            _QuickKeyButton(label: n, onTap: () => _onDigitTap(n)),
                          const SizedBox(width: 70, height: 70),
                          _QuickKeyButton(label: '0', onTap: () => _onDigitTap('0')),
                          _QuickKeyButton(icon: Icons.backspace_outlined, onTap: _onDelete, smallIcon: true),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 38,
                    top: 770,
                    child: SizedBox(
                      width: 336,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: () async {
                          final income = int.tryParse(_amount) ?? 0;
                          await _AppStorage.saveMonthlyIncome(income);
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => Directionality(
                                textDirection: TextDirection.rtl,
                                child: BudgetSetupScreen(monthlyIncome: income),
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6856A5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          elevation: 0,
                        ),
                        child: const Text(
                          'التالي',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickKeyButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool smallIcon;
  const _QuickKeyButton({this.label, this.icon, required this.onTap, this.smallIcon = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(35),
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black.withValues(alpha: 0.20)),
        ),
        child: Center(
          child: icon != null
              ? Icon(icon, size: smallIcon ? 18 : 24, color: const Color(0xFF7F7F7F))
              : Text(
                  label ?? '',
                  style: const TextStyle(color: Color(0xFF14121E), fontSize: 28, fontWeight: FontWeight.w500),
                ),
        ),
      ),
    );
  }
}

class BudgetSetupScreen extends StatefulWidget {
  final int monthlyIncome;
  const BudgetSetupScreen({super.key, required this.monthlyIncome});

  @override
  State<BudgetSetupScreen> createState() => _BudgetSetupScreenState();
}

class _BudgetSetupScreenState extends State<BudgetSetupScreen> {
  double _savingPercent = 20;

  @override
  Widget build(BuildContext context) {
    final suggestedSaving = (widget.monthlyIncome * (_savingPercent / 100)).round();
    final usedPercent = (100 - _savingPercent).round();
    final necessitiesPercent = usedPercent;
    final savingPercent = _savingPercent.round();
    final necessitiesAmount = (widget.monthlyIncome * 0.50).round();
    final funAmount = (widget.monthlyIncome * 0.30).round();
    final savingPlanAmount = (widget.monthlyIncome * 0.20).round();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 412,
              height: 917,
              child: Stack(
                children: [
                  Positioned(
                    left: 143,
                    top: 70,
                    child: SizedBox(
                      width: 244,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: const [
                          Text('حدد ميزانيتك', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                          SizedBox(height: 8),
                          Text(
                            'كم رح تصرف بالشهر كحد أقصى؟ (اختياري)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 26,
                    top: 159,
                    child: Container(
                      width: 361,
                      height: 180,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD9D4E8),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: const Color(0x96411D5D)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('دخلك الشهري', style: TextStyle(fontSize: 12)),
                          const SizedBox(height: 20),
                          Text('${widget.monthlyIncome}₪', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 12),
                          Text('توفير متوقع: ${suggestedSaving}₪', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 22,
                    top: 378,
                    child: SizedBox(
                      width: 367,
                      child: Row(
                        children: [
                          Text('${savingPercent}%', style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 7),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 12,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
                                overlayShape: SliderComponentShape.noOverlay,
                                activeTrackColor: const Color(0xFF6856A5),
                                inactiveTrackColor: const Color(0xFFE8E7E7),
                                thumbColor: const Color(0xFF6856A5),
                              ),
                              child: Slider(
                                value: _savingPercent,
                                min: 0,
                                max: 100,
                                divisions: 100,
                                onChanged: (v) => setState(() => _savingPercent = v),
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Text('${necessitiesPercent}%', style: const TextStyle(fontSize: 16)),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 169,
                    top: 412,
                    child: Text(
                      '${necessitiesPercent}% نسبة الضروريات',
                      style: TextStyle(color: const Color(0xFF1C5D1E), fontSize: 12, fontWeight: FontWeight.w400),
                    ),
                  ),
                  const Positioned(left: 214, top: 478, child: Text('توزيع مقترح (20/30/50)', style: TextStyle(fontSize: 16))),
                  Positioned(
                    left: 27,
                    top: 524,
                    child: SizedBox(
                      width: 360,
                      child: Column(
                        children: [
                          _BudgetRow(label: 'ضروريات (50%)', amount: necessitiesAmount),
                          const SizedBox(height: 9),
                          _BudgetRow(label: 'ترفيه (30%)', amount: funAmount),
                          const SizedBox(height: 9),
                          _BudgetRow(label: 'توفير (20%)', amount: savingPlanAmount, highlighted: true),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 38,
                    top: 769,
                    child: SizedBox(
                      width: 336,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: () async {
                          await _AppStorage.saveMonthlyIncome(widget.monthlyIncome);
                          await _AppStorage.saveSavingPercent(_savingPercent);
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => const Directionality(
                                textDirection: TextDirection.rtl,
                                child: GoalSetupScreen(),
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6856A5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          elevation: 0,
                        ),
                        child: const Text('التالي', style: TextStyle(color: Colors.white, fontSize: 16)),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 150,
                    top: 839,
                    child: TextButton(
                      onPressed: () async {
                        await _AppStorage.saveMonthlyIncome(widget.monthlyIncome);
                        await _AppStorage.saveSavingPercent(_savingPercent);
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const Directionality(textDirection: TextDirection.rtl, child: HomePage()),
                          ),
                        );
                      },
                      child: const Text('تخطي هذه الخطوة', style: TextStyle(color: Colors.black, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BudgetRow extends StatelessWidget {
  final String label;
  final int amount;
  final bool highlighted;
  const _BudgetRow({required this.label, required this.amount, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 55,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFEF4961) : const Color(0xFFF3F3F3),
        borderRadius: BorderRadius.circular(15),
        border: highlighted ? null : Border.all(color: const Color(0xFFCACACA)),
      ),
      child: Row(
        children: [
          Text(
            '$amount₪',
            style: TextStyle(
              color: highlighted ? Colors.white : const Color(0xFF3C3D3D),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            label,
            style: TextStyle(color: highlighted ? Colors.white : const Color(0xFF3C3D3D), fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class GoalSetupScreen extends StatefulWidget {
  const GoalSetupScreen({super.key});

  @override
  State<GoalSetupScreen> createState() => _GoalSetupScreenState();
}

class _GoalSetupScreenState extends State<GoalSetupScreen> {
  final Set<int> _selected = {0};

  final List<Map<String, String>> _goals = const [
    {'title': 'توفير مبلغ معين', 'subtitle': 'حدد هدف توفير شهري أو سنوي'},
    {'title': 'تقليل الهدر', 'subtitle': 'راقب الفئات اللي بتصرف فيها كثير'},
    {'title': 'فهم عاداتي المالية', 'subtitle': 'تحليل ذكي لنمط مصاريفك'},
    {'title': 'الاستقلال المالي', 'subtitle': 'خطة طويلة المدى للحرية المالية'},
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 412,
              height: 917,
              child: Stack(
                children: [
                  Positioned(
                    left: 142,
                    top: 66,
                    child: SizedBox(
                      width: 244,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: const [
                          Text('حدد هدفك!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                          SizedBox(height: 8),
                          Text('اختر هدف أو أكثر — رح نخصص تجربتك عليه', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    top: 45,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(24),
                      child: const SizedBox(
                        width: 47,
                        height: 47,
                        child: Icon(Icons.arrow_back, color: Color(0xFF3C3D3D), size: 22),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 26,
                    top: 153,
                    child: SizedBox(
                      width: 360,
                      child: Column(
                        children: List.generate(_goals.length, (i) {
                          final isSelected = _selected.contains(i);
                          return Padding(
                            padding: EdgeInsets.only(bottom: i == _goals.length - 1 ? 0 : 9),
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selected.remove(i);
                                  } else {
                                    _selected.add(i);
                                  }
                                });
                              },
                              borderRadius: BorderRadius.circular(15),
                              child: Container(
                                width: double.infinity,
                                height: 80,
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFFD9D4E8) : Colors.white,
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(
                                    color: isSelected ? const Color(0xFF9EA3A6) : const Color(0xFFB1A5D7),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const SizedBox(width: 18),
                                    Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isSelected ? const Color(0xFF6856A5) : Colors.white,
                                        border: Border.all(color: const Color(0xFF6856A5)),
                                      ),
                                      child: isSelected
                                          ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                                          : null,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            _goals[i]['title']!,
                                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(_goals[i]['subtitle']!, style: const TextStyle(fontSize: 14)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 18),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 38,
                    top: 625,
                    child: SizedBox(
                      width: 336,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => const Directionality(
                                textDirection: TextDirection.rtl,
                                child: HomePage(),
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6856A5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                          elevation: 0,
                        ),
                        child: const Text('انهاء الاعداد', style: TextStyle(color: Colors.white, fontSize: 16)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Future<_HomeStats> _loadStats() async {
    final analytics = await _loadAnalyticsData();
    final now = DateTime.now();
    final expenses = await _AppStorage.getExpenses();
    final coffeeToday = expenses.where((item) {
      if (item['category'] != 'قهوة') return false;
      final raw = item['createdAt'];
      if (raw is! String) return false;
      final dt = DateTime.tryParse(raw);
      return dt != null && dt.year == now.year && dt.month == now.month && dt.day == now.day;
    }).fold<int>(0, (sum, item) => sum + ((item['amount'] as num?)?.toInt() ?? 0));

    return _HomeStats(
      monthlyIncome: analytics.monthlyIncome,
      totalExpenses: analytics.monthSpent,
      todayCoffeeExpense: coffeeToday,
      suggestedSaving: analytics.monthlyIncome - analytics.monthSpent,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<_HomeStats>(
          future: _loadStats(),
          builder: (context, snapshot) {
            final stats = snapshot.data ??
                const _HomeStats(
                  monthlyIncome: 0,
                  totalExpenses: 0,
                  todayCoffeeExpense: 0,
                  suggestedSaving: 0,
                );
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _header(context),
                const SizedBox(height: 12),
                _balanceCard(stats),
                const SizedBox(height: 10),
                _storyAlertCard(context),
                const SizedBox(height: 12),
                _budgetProgressCard(stats),
                const SizedBox(height: 12),
                _streakCard(context),
                const SizedBox(height: 12),
                _goalsCard(context),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AddExpenseScreen()),
          );
          if (mounted) setState(() {});
        },
        backgroundColor: const Color(0xFF6856A5),
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _bottomNav(context),
    );
  }

  Widget _header(BuildContext context) {
    return FutureBuilder<String>(
      future: _AppStorage.getCurrentUserName(),
      builder: (context, snapshot) {
        final userName = snapshot.data ?? 'مستخدم';
        final firstChar = userName.isNotEmpty ? userName[0].toUpperCase() : 'م';
        return Row(
          children: [
            IconButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ExpensesHistoryScreen()),
                );
              },
              icon: const Icon(Icons.notifications_none_rounded),
            ),
            const Spacer(),
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF6856A5),
              child: Text(firstChar, style: const TextStyle(color: Colors.white)),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(userName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                const Text('موظف عن بعد', style: TextStyle(fontSize: 10, color: Colors.black54)),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _balanceCard(_HomeStats stats) {
    final income = stats.monthlyIncome;
    final suggestedSaving = math.max(0, stats.suggestedSaving);
    final coffeeToday = stats.todayCoffeeExpense;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF6856A5), Color(0xFF4E95CF)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text(
            'رصيدك الحالي',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            '${income}₪',
            style: const TextStyle(color: Colors.white, fontSize: 40, height: 1),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _MiniInfoCard(title: 'المدخرات', value: '${suggestedSaving}₪')),
              SizedBox(width: 8),
              Expanded(child: _MiniInfoCard(title: 'مصروف اليوم', value: '${coffeeToday}₪')),
            ],
          )
        ],
      ),
    );
  }

  Widget _storyAlertCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4961),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text(
            'قصتك اليوم ✨\nاليوم صرفت 70% من ميزانيتك... أغلبها على القهوة ☕',
            style: TextStyle(color: Colors.white, fontSize: 12, height: 1.55),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StoryScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFEF4961),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Fix It', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              const Spacer(),
              const Text(
                'اضغط لمعرفة التفاصيل',
                style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _budgetProgressCard(_HomeStats stats) {
    final income = stats.monthlyIncome;
    final spent = stats.totalExpenses;
    final ratio = income <= 0 ? 0.0 : (spent / income).clamp(0.0, 1.0);
    final spentPercent = (ratio * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          children: [
            Text('$spentPercent% مصروف', style: const TextStyle(color: Color(0xFF6856A5), fontSize: 12)),
            const Spacer(),
            Text('${spent}₪', style: const TextStyle(fontSize: 16)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 12,
            backgroundColor: const Color(0xFFE8E7E7),
            color: const Color(0xFF6856A5),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text('${income}₪', style: const TextStyle(fontSize: 13)),
            const Spacer(),
            const Text('0₪', style: TextStyle(fontSize: 13)),
          ],
        ),
      ],
    );
  }

  Widget _streakCard(BuildContext context) {
    const dayItems = [
      ('ج', '27'),
      ('خم', '26'),
      ('أر', '25'),
      ('ث', '24'),
      ('اث', '23'),
      ('أح', '22'),
      ('س', '21'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFFE5E5E5)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFD8D3F4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('🔥 5 يوم', style: TextStyle(fontSize: 15)),
              ),
              const Spacer(),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('سلسلة الالتزام', style: TextStyle(fontSize: 20, height: 1.1)),
                  Text('بدون تجاوز الميزانية', style: TextStyle(fontSize: 15, color: Color(0xFF8D8D8D))),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(dayItems.length, (index) {
            final day = dayItems[index].$1;
            final date = dayItems[index].$2;
            final isInactive = index == 0;
            final isToday = index == 1;
            final isPrimary = index == 2;
            final active = !isInactive && !isToday;
            return Column(
              children: [
                Text(
                  day,
                  style: TextStyle(
                    fontSize: 14,
                    color: isPrimary ? const Color(0xFF6856A5) : Colors.black,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: isToday
                        ? const Color(0xFF6856A5)
                        : active
                            ? const Color(0xFFDCD8F2)
                            : const Color(0xFFECECEC),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: isInactive ? const Color(0xFFBEBEBE) : const Color(0xFF8D82E8),
                      width: isInactive ? 1.0 : 0.7,
                    ),
                  ),
                  child: Center(
                    child: isInactive
                        ? const Icon(Icons.circle, size: 8, color: Color(0xFFC1B5B5))
                        : Text(
                            isToday ? 'اليوم' : '✓',
                            style: TextStyle(
                              color: isToday ? Colors.white : const Color(0xFF6856A5),
                              fontSize: 12,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  date,
                  style: TextStyle(
                    fontSize: 30 / 2.3,
                    color: isPrimary ? const Color(0xFF6856A5) : Colors.black,
                  ),
                ),
              ],
            );
          }),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AiAssistantScreen()),
                );
              },
              borderRadius: BorderRadius.circular(50),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFF6856A5),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: const Text(
                  'CONIZY AI ✨',
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const Spacer(),
            const Text(
              '5 أيام بدون تجاوز! استمر',
              style: TextStyle(color: Color(0xFF6856A5), fontSize: 18 / 1.5, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ],
    );
  }

  Widget _goalsCard(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GoalsScreen()),
                );
              },
              child: const Text('مشاهدة الكل', style: TextStyle(color: Color(0xFF6856A5), fontSize: 13)),
            ),
            const Spacer(),
            const Text('الاهداف', style: TextStyle(fontSize: 16)),
          ],
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const GoalsScreen()),
            );
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 128,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF6856A5), width: 2),
            ),
            child: const Center(
              child: Text(
                'أضف هدفًا جديدًا، ابدأ رحلتك نحو الاستقرار المالي',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF6F7474), fontSize: 14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bottomNav(BuildContext context) {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      color: Colors.white,
      elevation: 12,
      child: SizedBox(
        height: 74,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavItem(
              icon: Icons.person_outline,
              label: 'حسابي',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountScreen()),
                );
              },
            ),
            _NavItem(
              icon: Icons.emoji_events_outlined,
              label: 'الانجازات',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AchievementsScreen()),
                );
              },
            ),
            const SizedBox(width: 36),
            _NavItem(
              icon: Icons.analytics_outlined,
              label: 'تحليل',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AnalysisScreen()),
                );
              },
            ),
            const _NavItem(icon: Icons.home_rounded, label: 'الرئيسية', active: true),
          ],
        ),
      ),
    );
  }
}

class _MiniInfoCard extends StatelessWidget {
  final String title;
  final String value;
  const _MiniInfoCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x19D9D9D9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 14)),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  const _NavItem({
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF6856A5) : const Color(0x803C3D3D);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: color, fontSize: 12, letterSpacing: 0.24)),
        ],
      ),
    );
  }
}

class StoryScreen extends StatelessWidget {
  const StoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.black87),
                    ),
                    const Text(
                      'نمط الإنفاق الأسبوعي',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: const Color(0xFF4E95CF),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'تصرف أكثر أيام الاثنين\nيتزامن مع اجتماعات الشغل الأسبوعية',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _bar(12, false),
                          _bar(18, false),
                          _bar(26, false),
                          _bar(40, false),
                          _bar(67, true),
                          _bar(47, false),
                          _bar(34, false),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('ج', style: TextStyle(color: Colors.white, fontSize: 12)),
                          Text('خم', style: TextStyle(color: Colors.white, fontSize: 12)),
                          Text('أر', style: TextStyle(color: Colors.white, fontSize: 12)),
                          Text('ث', style: TextStyle(color: Colors.white, fontSize: 12)),
                          Text('اث', style: TextStyle(color: Colors.white, fontSize: 12)),
                          Text('أح', style: TextStyle(color: Colors.white, fontSize: 12)),
                          Text('س', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDEAEA),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFF3333), width: 2.5),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'التأثير المالي',
                        style: TextStyle(color: Color(0xFF860E0E), fontSize: 13),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'هذا النمط كلّفك 180₪ إضافية هذا الشهر',
                        style: TextStyle(color: Color(0xFF860E0E), fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF7EE),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF4AB04E), width: 2.5),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'اقتراح ذكي',
                        style: TextStyle(color: Color(0xFF1C5D1E), fontSize: 13),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'ضع حد 20₪ للقهوة أيام الاثنين',
                        style: TextStyle(color: Color(0xFF1C5D1E), fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AiAssistantScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(50),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6856A5),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: const Text(
                        'CONIZY AI ✨',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CommitmentScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6856A5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: const Text(
                      'جرب هذا الاقتراح',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddExpenseScreen()),
            );
          },
          backgroundColor: const Color(0xFF6856A5),
          shape: const CircleBorder(),
          child: const Icon(Icons.add, color: Colors.white),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: BottomAppBar(
          shape: const CircularNotchedRectangle(),
          notchMargin: 8,
          color: Colors.white,
          elevation: 12,
          child: SizedBox(
            height: 74,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.person_outline,
                  label: 'حسابي',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AccountScreen()),
                    );
                  },
                ),
                _NavItem(
                  icon: Icons.emoji_events_outlined,
                  label: 'الانجازات',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AchievementsScreen()),
                    );
                  },
                ),
                const SizedBox(width: 36),
                _NavItem(
                  icon: Icons.analytics_outlined,
                  label: 'تحليل',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AnalysisScreen()),
                    );
                  },
                ),
                _NavItem(
                  icon: Icons.home_rounded,
                  label: 'الرئيسية',
                  active: true,
                  onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bar(double h, bool highlighted) {
    return Container(
      width: 39,
      height: h,
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFEF4961) : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(5),
          topRight: Radius.circular(5),
        ),
      ),
    );
  }
}

class CommitmentScreen extends StatefulWidget {
  const CommitmentScreen({super.key});

  @override
  State<CommitmentScreen> createState() => _CommitmentScreenState();
}

class _CommitmentScreenState extends State<CommitmentScreen> {
  late Future<_AnalyticsData> _analyticsFuture;

  @override
  void initState() {
    super.initState();
    _analyticsFuture = _loadAnalyticsData();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: FutureBuilder<_AnalyticsData>(
            future: _analyticsFuture,
            builder: (context, snapshot) {
              final data = snapshot.data;
              final dailySave = math.max(5, data?.dailyCutNeeded ?? 15);
              final monthlySave = dailySave * 30;
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.black87),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEEDFE),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '5 أيام ✨',
                        style: TextStyle(fontSize: 15),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6856A5),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 92,
                        height: 92,
                        decoration: const BoxDecoration(
                          color: Color(0xFF534388),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_circle_outline_rounded,
                          color: Color(0xFFFF9EAF),
                          size: 46,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'قلل ${data?.topCategory ?? 'القهوة'} اليوم!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'إجراء يومي واحد فقط',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF534388),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('إذا فعلت هذا', style: TextStyle(color: Colors.white, fontSize: 14)),
                            SizedBox(height: 8),
                            Text(
                              'توفر ${dailySave}₪ اليوم',
                              style: TextStyle(
                                color: Color(0xFFEA9EA9),
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text('= ${monthlySave}₪ / شهر', style: TextStyle(color: Colors.white, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        barrierColor: Colors.black.withOpacity(0.58),
                        builder: (_) => _CommitmentSuccessDialog(
                          dailySave: dailySave,
                          monthlySave: monthlySave,
                        ),
                      );
                    },
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: const Text(
                      'تعهدت بذلك',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4961),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AiAssistantScreen()),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF6856A5), width: 1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: const Text(
                      'اقترح إجراء اخر',
                      style: TextStyle(color: Color(0xFF6856A5), fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AiAssistantScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(50),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6856A5),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: const Text(
                        'CONIZY AI ✨',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ],
                ),
              );
            },
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddExpenseScreen()),
            );
          },
          backgroundColor: const Color(0xFF6856A5),
          shape: const CircleBorder(),
          child: const Icon(Icons.add, color: Colors.white),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: BottomAppBar(
          shape: const CircularNotchedRectangle(),
          notchMargin: 8,
          color: Colors.white,
          elevation: 12,
          child: SizedBox(
            height: 74,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.person_outline,
                  label: 'حسابي',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AccountScreen()),
                    );
                  },
                ),
                _NavItem(
                  icon: Icons.emoji_events_outlined,
                  label: 'الانجازات',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AchievementsScreen()),
                    );
                  },
                ),
                const SizedBox(width: 36),
                _NavItem(
                  icon: Icons.analytics_outlined,
                  label: 'تحليل',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AnalysisScreen()),
                    );
                  },
                ),
                _NavItem(
                  icon: Icons.home_rounded,
                  label: 'الرئيسية',
                  active: true,
                  onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommitmentSuccessDialog extends StatelessWidget {
  final int dailySave;
  final int monthlySave;
  const _CommitmentSuccessDialog({
    required this.dailySave,
    required this.monthlySave,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 27),
      child: Container(
        width: 357,
        padding: const EdgeInsets.fromLTRB(22, 30, 22, 20),
        decoration: BoxDecoration(
          color: const Color(0xFF6856A5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 95,
              height: 95,
              decoration: const BoxDecoration(
                color: Color(0xFF534388),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline_rounded,
                color: Color(0xFFFF9EAF),
                size: 45,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'أحسنت! تعهد محفوظ',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'ستوفر ${dailySave}₪ اليوم = ${monthlySave}₪ هذا الشهر',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF534388),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Expanded(child: _SuccessStat(value: '120₪', label: 'وفرت')),
                  _SuccessDivider(),
                  Expanded(child: _SuccessStat(value: '72%', label: 'أفضل أيام')),
                  _SuccessDivider(),
                  Expanded(child: _SuccessStat(value: '6', label: 'أيام streak')),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AnalysisScreen()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4961),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: const Text(
                  'استمر',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuccessStat extends StatelessWidget {
  final String value;
  final String label;
  const _SuccessStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFFF99A7),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _SuccessDivider extends StatelessWidget {
  const _SuccessDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      width: 1,
      color: Colors.white30,
    );
  }
}

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  late Future<_AnalyticsData> _analyticsFuture;

  @override
  void initState() {
    super.initState();
    _analyticsFuture = _loadAnalyticsData();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: FutureBuilder<_AnalyticsData>(
            future: _analyticsFuture,
            builder: (context, snapshot) {
              final data = snapshot.data;
              final totals = data?.categoryTotals ?? const <String, int>{};
              final totalSpentRaw = data?.monthSpent ?? 0;
              final totalSpent = math.max(0, totalSpentRaw);
              final foodPercent = totalSpent == 0 ? 0 : (((totals['طعام'] ?? 0) / totalSpent) * 100).round();
              final coffeePercent = totalSpent == 0 ? 0 : (((totals['قهوة'] ?? 0) / totalSpent) * 100).round();
              final transportPercent = totalSpent == 0 ? 0 : (((totals['مواصلات'] ?? 0) / totalSpent) * 100).round();
              final otherAmount = totalSpent == 0
                  ? 0
                  : totalSpent - (totals['طعام'] ?? 0) - (totals['قهوة'] ?? 0) - (totals['مواصلات'] ?? 0);
              final otherPercent = totalSpent == 0 ? 0 : math.max(0, ((otherAmount / totalSpent) * 100).round());
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.black87),
                    ),
                    const Spacer(),
                    const Text(
                      'تحليل المصاريف',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDEDED),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: const [
                      Expanded(child: _SegmentChip(label: 'هذا السنة')),
                      SizedBox(width: 4),
                      Expanded(child: _SegmentChip(label: 'اليوم')),
                      SizedBox(width: 4),
                      Expanded(child: _SegmentChip(label: 'هذا الاسبوع', active: true)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFECECEC)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0C000000),
                        blurRadius: 4,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'توزيع المصاريف',
                        style: TextStyle(
                          color: Color(0xFF1B1B1B),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                _LegendRow(percent: '$foodPercent%', label: 'طعام', color: const Color(0xFF4E95CF)),
                                const SizedBox(height: 10),
                                _LegendRow(percent: '$coffeePercent%', label: 'قهوة', color: const Color(0xFF1C5D1E)),
                                const SizedBox(height: 10),
                                _LegendRow(percent: '$transportPercent%', label: 'مواصلات', color: const Color(0xFFF0C556)),
                                const SizedBox(height: 10),
                                _LegendRow(percent: '$otherPercent%', label: 'أخرى', color: const Color(0xFFF67B7B)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _DonutChart(
                            foodPercent: foodPercent,
                            coffeePercent: coffeePercent,
                            transportPercent: transportPercent,
                            otherPercent: otherPercent,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _InsightCard(
                  bg: const Color(0xFFEDEDED),
                  border: const Color(0xFFCCCCCC),
                  title: 'أعلى فئة صرف: ${data?.topCategory ?? 'طعام'} (${data?.topCategoryPercent ?? 0}%)',
                  subtitle: 'متوسطك : ${data?.weeklyAvg ?? 0}₪ / أسبوع',
                  buttonText: 'Fix it',
                  buttonColor: const Color(0xFF6856A5),
                ),
                const SizedBox(height: 14),
                _InsightCard(
                  bg: const Color(0xFFFDEAEA),
                  border: const Color(0xFFEF4961),
                  title: 'مصروفك الحالي هذا الشهر: ${data?.monthSpent ?? 0}₪',
                  subtitle: 'حاول تراجع مصاريف ${data?.topCategory ?? 'الترفيه'}',
                  buttonText: 'Fix it',
                  buttonColor: const Color(0xFFE24B4A),
                  badge: 'توقع',
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const EndMonthForecastScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6856A5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: const Text(
                      'Fix it الان',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AiAssistantScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(50),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6856A5),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: const Text(
                        'CONIZY AI ✨',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ],
                ),
              );
            },
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddExpenseScreen()),
            );
          },
          backgroundColor: const Color(0xFF6856A5),
          shape: const CircleBorder(),
          child: const Icon(Icons.add, color: Colors.white),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: BottomAppBar(
          shape: const CircularNotchedRectangle(),
          notchMargin: 8,
          color: Colors.white,
          elevation: 12,
          child: SizedBox(
            height: 74,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.person_outline,
                  label: 'حسابي',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AccountScreen()),
                    );
                  },
                ),
                _NavItem(
                  icon: Icons.emoji_events_outlined,
                  label: 'الانجازات',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AchievementsScreen()),
                    );
                  },
                ),
                const SizedBox(width: 36),
                const _NavItem(icon: Icons.analytics_outlined, label: 'تحليل', active: true),
                _NavItem(
                  icon: Icons.home_rounded,
                  label: 'الرئيسية',
                  onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SegmentChip extends StatelessWidget {
  final String label;
  final bool active;
  const _SegmentChip({required this.label, this.active = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 39,
      decoration: BoxDecoration(
        color: active ? const Color(0xFF6856A5) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : const Color(0xFF040202),
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final String percent;
  final String label;
  final Color color;
  const _LegendRow({required this.percent, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(percent, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        const Spacer(),
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF7F7F7F))),
        const SizedBox(width: 4),
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      ],
    );
  }
}

class _DonutChart extends StatelessWidget {
  final int foodPercent;
  final int coffeePercent;
  final int transportPercent;
  final int otherPercent;
  const _DonutChart({
    required this.foodPercent,
    required this.coffeePercent,
    required this.transportPercent,
    required this.otherPercent,
  });

  @override
  Widget build(BuildContext context) {
    final sumPercents = foodPercent + coffeePercent + transportPercent + otherPercent;
    if (sumPercents <= 0) {
      return SizedBox(
        width: 150,
        height: 150,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 150,
              height: 150,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFE8E7E7),
              ),
            ),
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
          ],
        ),
      );
    }
    final total = sumPercents;
    final f = foodPercent / total;
    final c = coffeePercent / total;
    final t = transportPercent / total;
    final o = otherPercent / total;
    return SizedBox(
      width: 150,
      height: 150,
      child: CustomPaint(
        painter: _DonutPainter(
          segments: [f, c, t, o],
          colors: const [
            Color(0xFF4E95CF),
            Color(0xFF1C5D1E),
            Color(0xFFF0C556),
            Color(0xFFF67B7B),
          ],
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<double> segments;
  final List<Color> colors;
  _DonutPainter({required this.segments, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 16.0;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    var start = -math.pi / 2;
    for (var i = 0; i < segments.length; i++) {
      final sweep = (2 * math.pi) * segments[i];
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..color = colors[i];
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
    final holePaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(size.width / 2, size.height / 2), 48, holePaint);
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.segments != segments || oldDelegate.colors != colors;
  }
}

class _InsightCard extends StatelessWidget {
  final Color bg;
  final Color border;
  final String title;
  final String subtitle;
  final String buttonText;
  final Color buttonColor;
  final String? badge;

  const _InsightCard({
    required this.bg,
    required this.border,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.buttonColor,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (badge != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEBB7BE),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badge!,
                  style: const TextStyle(color: Color(0xFFB22C2C), fontSize: 12),
                ),
              ),
            ),
          Text(title, style: TextStyle(color: border == const Color(0xFFEF4961) ? const Color(0xFF860E0E) : Colors.black, fontSize: 13)),
          const SizedBox(height: 6),
          Text(subtitle, style: TextStyle(color: border == const Color(0xFFEF4961) ? const Color(0xFFBA6250) : const Color(0xFF7E8081), fontSize: 13)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CommitmentScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: buttonColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                buttonText,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EndMonthForecastScreen extends StatefulWidget {
  const EndMonthForecastScreen({super.key});

  @override
  State<EndMonthForecastScreen> createState() => _EndMonthForecastScreenState();
}

class _EndMonthForecastScreenState extends State<EndMonthForecastScreen> {
  late Future<_AnalyticsData> _analyticsFuture;

  @override
  void initState() {
    super.initState();
    _analyticsFuture = _loadAnalyticsData();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: FutureBuilder<_AnalyticsData>(
            future: _analyticsFuture,
            builder: (context, snapshot) {
              final data = snapshot.data;
              final income = data?.monthlyIncome ?? 1000;
              final projected = data?.projectedMonthSpent ?? 0;
              final overrun = data?.predictedOverrun ?? 0;
              final dailyCut = data?.dailyCutNeeded ?? 0;
              final progressRatio = income <= 0 ? 0.0 : (projected / income).clamp(0.0, 1.0);
              final progressRight = (260 * (1 - progressRatio)).clamp(0, 260).toDouble();
              final hasOverrun = overrun > 0;
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.black87),
                    ),
                    const Spacer(),
                    const Text(
                      'توقع نهاية الشهر',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: hasOverrun ? const Color(0xFFFDEAEA) : const Color(0xFFEAF7EE),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: hasOverrun ? const Color(0xFFFF3333) : const Color(0xFF1C5D1E),
                      width: 2.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        hasOverrun ? 'تحذير — توقع التجاوز' : 'ممتاز — ضمن الميزانية',
                        style: TextStyle(
                          color: hasOverrun ? const Color(0xFF860E0E) : const Color(0xFF1C5D1E),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ستصرف ~${projected}₪ هذا الشهر',
                        style: TextStyle(
                          color: hasOverrun ? const Color(0xFF860E0E) : const Color(0xFF1C5D1E),
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        hasOverrun
                            ? 'الميزانية: ${income}₪ — تجاوز متوقع: ${overrun}₪'
                            : 'الميزانية: ${income}₪ — لا يوجد تجاوز متوقع',
                        style: TextStyle(
                          color: hasOverrun ? const Color(0xFFBC5858) : const Color(0xFF1C5D1E),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  height: 205,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F8F8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFBCC1C5), width: 1),
                  ),
                  child: Stack(
                    children: [
                      const Align(
                        alignment: Alignment.topRight,
                        child: Text(
                          'مسار الشهر',
                          style: TextStyle(color: Color(0xFF3C3D3D), fontSize: 13),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 12,
                        child: Container(
                          height: 1,
                          color: const Color(0xFFDACACA),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 28,
                        child: Container(
                          height: 1,
                          color: hasOverrun ? const Color(0xFFB1232A) : const Color(0xFF1C5D1E),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        right: progressRight,
                        bottom: 28,
                        child: Container(
                          height: 3,
                          color: const Color(0xFF6856A5),
                        ),
                      ),
                      Positioned(
                        left: 14,
                        bottom: 2,
                        child: Text(
                          'المصروف الحالي: ${data?.monthSpent ?? 0}₪',
                          style: const TextStyle(color: Color(0xFF3C3D3D), fontSize: 11),
                        ),
                      ),
                      Positioned(
                        right: 14,
                        bottom: 2,
                        child: Text(
                          'توقع نهاية الشهر: ${projected}₪',
                          style: const TextStyle(color: Color(0xFF3C3D3D), fontSize: 11),
                        ),
                      ),
                      const Positioned(
                        left: 150,
                        bottom: 70,
                        child: CircleAvatar(
                          radius: 6,
                          backgroundColor: Color(0xFF6856A5),
                        ),
                      ),
                      const Positioned(
                        left: 142,
                        bottom: 52,
                        child: Text(
                          'اليوم',
                          style: TextStyle(color: Color(0xFF3C3D3D), fontSize: 10),
                        ),
                      ),
                      const Positioned(
                        right: 40,
                        top: 36,
                        child: Text(
                          'توقع',
                          style: TextStyle(color: Color(0xFF880D0D), fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF7EE),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF1C5D1E), width: 2.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'للتوازن',
                        style: TextStyle(color: Color(0xFF1C5D1E), fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        hasOverrun
                            ? 'قلل المصاريف اليومية بـ ${dailyCut}₪ للتوازن'
                            : 'استمر على نفس النسق، وضعك متوازن',
                        style: const TextStyle(color: Color(0xFF1C5D1E), fontSize: 16),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CommitmentScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6856A5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: const Text(
                      'Fix it الان',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AiAssistantScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(50),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6856A5),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: const Text(
                        'CONIZY AI ✨',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ],
                ),
              );
            },
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddExpenseScreen()),
            );
          },
          backgroundColor: const Color(0xFF6856A5),
          shape: const CircleBorder(),
          child: const Icon(Icons.add, color: Colors.white),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: BottomAppBar(
          shape: const CircularNotchedRectangle(),
          notchMargin: 8,
          color: Colors.white,
          elevation: 12,
          child: SizedBox(
            height: 74,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.person_outline,
                  label: 'حسابي',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AccountScreen()),
                    );
                  },
                ),
                _NavItem(
                  icon: Icons.emoji_events_outlined,
                  label: 'الانجازات',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AchievementsScreen()),
                    );
                  },
                ),
                const SizedBox(width: 36),
                const _NavItem(icon: Icons.analytics_outlined, label: 'تحليل', active: true),
                _NavItem(
                  icon: Icons.home_rounded,
                  label: 'الرئيسية',
                  onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  color: const Color(0xFF6856A5),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                          ),
                          const Spacer(),
                          FutureBuilder<String>(
                            future: _AppStorage.getCurrentUserName(),
                            builder: (context, snapshot) {
                              final userName = snapshot.data ?? 'مستخدم';
                              final firstChar = userName.isNotEmpty ? userName[0].toUpperCase() : 'م';
                              return Row(
                                children: [
                                  CircleAvatar(
                                    radius: 32,
                                    backgroundColor: const Color(0xFF534388),
                                    child: Text(
                                      firstChar,
                                      style: const TextStyle(color: Colors.white, fontSize: 30),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        userName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'موظف عن بعد',
                                        style: TextStyle(color: Colors.white, fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Row(
                        children: [
                          Expanded(child: _ProfileStatCard(title: '5 🔥', subtitle: 'يوم Streak')),
                          SizedBox(width: 6),
                          Expanded(child: _ProfileStatCard(title: '7 🏆', subtitle: 'انجازات')),
                          SizedBox(width: 6),
                          Expanded(child: _ProfileStatCard(title: '8', subtitle: 'الاهداف')),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Column(
                    children: [
                      const _SectionTitle('الإعدادات المالية'),
                      _SettingsBox(
                        children: const [
                          _ValueRow(label: 'الدخل الشهري', value: '2,000₪'),
                          _ValueRow(label: 'الميزانية الشهرية', value: '1,000₪'),
                          _SwitchRow(label: 'توزيع 20/50/30', enabled: true),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const _SectionTitle('التنبيهات'),
                      _SettingsBox(
                        children: const [
                          _SwitchRow(label: 'تنبيه يومي', enabled: true),
                          _SwitchRow(label: 'تحذير التجاوز', enabled: true),
                          _SwitchRow(label: 'ملخص اسبوعي', enabled: false),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _SettingsBox(
                        children: const [
                          _ValueRow(label: 'اللغة', value: 'العربية'),
                          _ValueRow(label: 'العملة', value: 'شيكل ₪'),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                builder: (_) => const Directionality(
                                  textDirection: TextDirection.rtl,
                                  child: LoginScreen(),
                                ),
                              ),
                              (route) => false,
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFF87B8D)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          child: const Text(
                            'تسجيل خروج',
                            style: TextStyle(color: Color(0xFFEF4961), fontSize: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddExpenseScreen()),
            );
          },
          backgroundColor: const Color(0xFF6856A5),
          shape: const CircleBorder(),
          child: const Icon(Icons.add, color: Colors.white),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: BottomAppBar(
          shape: const CircularNotchedRectangle(),
          notchMargin: 8,
          color: Colors.white,
          elevation: 12,
          child: SizedBox(
            height: 74,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                const _NavItem(icon: Icons.person_outline, label: 'حسابي', active: true),
                _NavItem(
                  icon: Icons.emoji_events_outlined,
                  label: 'الانجازات',
                  active: true,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AchievementsScreen()),
                    );
                  },
                ),
                const SizedBox(width: 36),
                _NavItem(
                  icon: Icons.analytics_outlined,
                  label: 'تحليل',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AnalysisScreen()),
                    );
                  },
                ),
                _NavItem(
                  icon: Icons.home_rounded,
                  label: 'الرئيسية',
                  onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileStatCard extends StatelessWidget {
  final String title;
  final String subtitle;
  const _ProfileStatCard({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0x21D9D9D9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}

class _SettingsBox extends StatelessWidget {
  final List<Widget> children;
  const _SettingsBox({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x19B2AEC1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: children
            .map(
              (child) => Column(
                children: [
                  child,
                  if (child != children.last) const Divider(height: 1, color: Colors.white),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  final String label;
  final String value;
  const _ValueRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            const Icon(Icons.chevron_left, color: Color(0x803C3D3D), size: 18),
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFF6856A5),
                fontSize: 12,
                letterSpacing: 0.24,
              ),
            ),
            const Spacer(),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF3C3D3D),
                fontSize: 12,
                letterSpacing: 0.24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool enabled;
  const _SwitchRow({required this.label, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Switch(
              value: enabled,
              onChanged: (_) {},
              activeColor: Colors.white,
              activeTrackColor: const Color(0xFF6856A5),
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: const Color(0xFFC5C4C7),
            ),
            const Spacer(),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF3C3D3D),
                fontSize: 12,
                letterSpacing: 0.24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.black87),
                    ),
                    const Spacer(),
                    const Text(
                      'الانجازات',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0x146856A5),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        '3 من 12 إنجاز محقق',
                        style: TextStyle(color: Color(0xFF4A5565), fontSize: 14),
                      ),
                      const SizedBox(height: 10),
                      const _ProgressPill(value: 0.24),
                      const SizedBox(height: 14),
                      Container(
                        width: 114,
                        height: 64,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6856A5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('🔥 5', style: TextStyle(color: Colors.white, fontSize: 15)),
                            SizedBox(height: 2),
                            Text('يوم Streak', style: TextStyle(color: Colors.white, fontSize: 13)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'إنجازاتك',
                    style: TextStyle(
                      color: Color(0xFF364153),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 12,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 0.88,
                  children: const [
                    _AchievementCard(
                      title: '30 يوم',
                      subtitle: 'متتابع',
                      icon: Icons.star_border_rounded,
                      bg: Color(0xFFFEF9C2),
                    ),
                    _AchievementCard(
                      title: 'هدف أول',
                      subtitle: 'محقق',
                      icon: Icons.check_circle_outline_rounded,
                      bg: Color(0xFFDCFCE7),
                    ),
                    _AchievementCard(
                      title: '5 أيام',
                      subtitle: 'Streak',
                      icon: Icons.diamond_outlined,
                      bg: Color(0xFFF3E8FF),
                    ),
                    _LockedAchievementCard(title: 'أسبوع صفر'),
                    _LockedAchievementCard(title: '7 أيام streak'),
                    _LockedAchievementCard(title: '100₪ تقدير'),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Column(
                    children: [
                      Row(
                        children: [
                          Text(
                            '75%',
                            style: TextStyle(color: Color(0xFF4A5565), fontSize: 12),
                          ),
                          Spacer(),
                          Text(
                            'الإنجاز القادم',
                            style: TextStyle(
                              color: Color(0xFF364153),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'وفر الـ 100',
                          style: TextStyle(color: Color(0xFF6856A5), fontSize: 14),
                        ),
                      ),
                      SizedBox(height: 8),
                      _ProgressPill(value: 0.75),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddExpenseScreen()),
            );
          },
          backgroundColor: const Color(0xFF6856A5),
          shape: const CircleBorder(),
          child: const Icon(Icons.add, color: Colors.white),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: BottomAppBar(
          shape: const CircularNotchedRectangle(),
          notchMargin: 8,
          color: Colors.white,
          elevation: 12,
          child: SizedBox(
            height: 74,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.person_outline,
                  label: 'حسابي',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AccountScreen()),
                    );
                  },
                ),
                const _NavItem(icon: Icons.emoji_events_outlined, label: 'الانجازات', active: true),
                const SizedBox(width: 36),
                _NavItem(
                  icon: Icons.analytics_outlined,
                  label: 'تحليل',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AnalysisScreen()),
                    );
                  },
                ),
                _NavItem(
                  icon: Icons.home_rounded,
                  label: 'الرئيسية',
                  onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressPill extends StatelessWidget {
  final double value;
  const _ProgressPill({required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFA5A5A5),
              borderRadius: BorderRadius.circular(50),
            ),
          ),
          FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF6856A5),
                borderRadius: BorderRadius.circular(50),
              ),
            ),
          ),
          Positioned(
            right: (value.clamp(0.0, 1.0) * 320) - 10,
            top: -1,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: Color(0xFF6856A5),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color bg;
  const _AchievementCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x19000000), blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: const Color(0xFF6856A5)),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontSize: 14, color: Color(0xFF1E2939))),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF4A5565))),
        ],
      ),
    );
  }
}

class _LockedAchievementCard extends StatelessWidget {
  final String title;
  const _LockedAchievementCard({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD1D5DC), width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lock_outline_rounded, color: Color(0xFF9CA3AF)),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFF1E2939)),
          ),
          const SizedBox(height: 2),
          const Text('🔥', style: TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final TextEditingController _controller = TextEditingController();
  final List<_ChatMessage> _messages = [];
  bool _sending = false;
  String _userName = 'مستخدم';

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    final name = await _AppStorage.getCurrentUserName();
    if (!mounted) return;
    setState(() {
      _userName = name;
      _messages.add(
        _ChatMessage(
          text: 'مرحبا $_userName! 👋 أنا AI CONIZY مساعدك المالي الذكي كيف أقدر أساعدك اليوم؟',
          isAi: true,
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _sendMessage([String? text]) async {
    final prompt = (text ?? _controller.text).trim();
    if (prompt.isEmpty || _sending) return;
    _controller.clear();
    setState(() {
      _sending = true;
      _messages.add(_ChatMessage(text: prompt, isAi: false));
    });

    final reply = await _ConizyAiService.ask(prompt);
    if (!mounted) return;
    setState(() {
      _messages.add(_ChatMessage(text: reply, isAi: true));
      _sending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F3FF),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0C000000),
                        blurRadius: 4,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back, color: Color(0xFF6856A5)),
                      ),
                      const SizedBox(width: 2),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6856A5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.shield_moon_outlined, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'CONIZY AI',
                        style: TextStyle(
                          color: Color(0xFF0A0A0A),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AiPremiumScreen()),
                          );
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFDC700), Color(0xFFF0B100)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'بريميوم',
                            style: TextStyle(color: Color(0xFF0A0A0A), fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'اليوم 9:43 صباحا',
                style: TextStyle(color: Color(0x990A0A0A), fontSize: 12),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _messages.length + (_sending ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, index) {
                    if (_sending && index == _messages.length) {
                      return const _AiBubble(message: '... جاري التفكير', isAi: true);
                    }
                    final item = _messages[index];
                    return _AiBubble(message: item.text, isAi: item.isAi);
                  },
                ),
              ),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _AiActionChip(
                          'خطط توفير إضافية',
                          onTap: () => _sendMessage('اعطني خطط توفير إضافية لهذا الشهر'),
                        ),
                        SizedBox(width: 8),
                        _AiActionChip(
                          'توقع الشهر',
                          onTap: () => _sendMessage('اعطني توقع صرفي لنهاية الشهر'),
                        ),
                        SizedBox(width: 8),
                        _AiActionChip(
                          'نصيحة اليوم',
                          onTap: () => _sendMessage('اعطني نصيحة مالية سريعة لليوم'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        InkWell(
                          onTap: _sending ? null : _sendMessage,
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: const BoxDecoration(
                              color: Color(0xFF6856A5),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _sending ? Icons.hourglass_top_rounded : Icons.send_outlined,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            height: 52,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4F3FF),
                              borderRadius: BorderRadius.circular(30),
                            ),
                            alignment: Alignment.center,
                            child: TextField(
                              controller: _controller,
                              textAlign: TextAlign.right,
                              onSubmitted: (_) => _sendMessage(),
                              decoration: const InputDecoration(
                                hintText: 'اسأل CONIZY AI...',
                                hintStyle: TextStyle(
                                  color: Color(0x7F0A0A0A),
                                  fontSize: 16,
                                ),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'حساب 5 رسائل / يوم - بريميوم: غير محدود',
                      style: TextStyle(color: Color(0x800A0A0A), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiBubble extends StatelessWidget {
  final String message;
  final bool isAi;
  const _AiBubble({required this.message, required this.isAi});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isAi ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 338),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: isAi ? const Color(0xFF4E95CF) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(isAi ? 5 : 30),
            topRight: Radius.circular(isAi ? 30 : 5),
            bottomLeft: const Radius.circular(30),
            bottomRight: const Radius.circular(30),
          ),
          boxShadow: const [
            BoxShadow(color: Color(0x19000000), blurRadius: 6, offset: Offset(0, 4), spreadRadius: -4),
            BoxShadow(color: Color(0x19000000), blurRadius: 15, offset: Offset(0, 10), spreadRadius: -3),
          ],
        ),
        child: Text(
          message,
          textAlign: TextAlign.right,
          style: TextStyle(
            color: isAi ? Colors.white : const Color(0xFF1E2939),
            fontSize: 13,
            height: 1.7,
          ),
        ),
      ),
    );
  }
}

class _AiActionChip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _AiActionChip(this.label, {this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F3FF),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF4F39F6),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class AiPremiumScreen extends StatelessWidget {
  const AiPremiumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F3FF),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: Color(0xFF1E2939)),
                    ),
                    const Spacer(),
                    const Text(
                      'CONIZY AI Premium',
                      style: TextStyle(
                        color: Color(0xFF0A0A0A),
                        fontSize: 28,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2B300),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x19000000),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Premium',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'ميزات PREMIUM',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Color(0xFF99A1AF),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),
                const _PremiumFeatureCard(
                  icon: Icons.auto_awesome,
                  title: 'AI CONIZY غير محدود',
                  subtitle: 'رسائل غير محدودة مع المساعد الذكي',
                ),
                const SizedBox(height: 12),
                const _PremiumFeatureCard(
                  icon: Icons.trending_up_rounded,
                  title: 'تحليل سلوكي متقدم',
                  subtitle: 'Insights عميقة وتوجيهات دقيقة',
                ),
                const SizedBox(height: 12),
                const _PremiumFeatureCard(
                  icon: Icons.gps_fixed_rounded,
                  title: 'أهداف ذكية متابعة',
                  subtitle: 'AI يضبط أهدافك بناءً على سلوكك',
                ),
                const SizedBox(height: 12),
                const _PremiumFeatureCard(
                  icon: Icons.notifications_none_rounded,
                  title: 'تنبيهات ذكية متقدمة',
                  subtitle: 'Insights على النشاط لحظتك',
                ),
                const SizedBox(height: 12),
                const _PremiumFeatureCard(
                  icon: Icons.show_chart_rounded,
                  title: 'توقع مالي شهري',
                  subtitle: 'توقع النفقات قبل بداية الشهر',
                ),
                const Spacer(),
                const Text(
                  'مكافآت: تتبع مصاريف + إضافة أهداف + Story Card توقعه + 5 رسائل',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF99A1AF),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PremiumFeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _PremiumFeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF3F4F6)),
        boxShadow: const [
          BoxShadow(color: Color(0x19000000), blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF4F39F6)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Color(0xFF1E2939),
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Color(0xFF6A7282),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  String _amount = '0';
  String _selectedCategory = 'قهوة';

  static const List<Map<String, dynamic>> _categories = [
    {'name': 'طعام', 'icon': Icons.restaurant_rounded},
    {'name': 'مواصلات', 'icon': Icons.directions_car_filled_rounded},
    {'name': 'قهوة', 'icon': Icons.local_cafe_rounded},
    {'name': 'تسوق', 'icon': Icons.shopping_bag_rounded},
    {'name': 'صحة', 'icon': Icons.favorite_outline_rounded},
    {'name': 'ترفيه', 'icon': Icons.sports_esports_rounded},
    {'name': 'التعليم', 'icon': Icons.menu_book_rounded},
    {'name': 'تسوق', 'icon': Icons.shopping_cart_outlined},
  ];

  void _appendDigit(String digit) {
    setState(() {
      if (_amount == '0') {
        _amount = digit;
      } else {
        _amount += digit;
      }
    });
  }

  void _backspace() {
    setState(() {
      if (_amount.length <= 1) {
        _amount = '0';
      } else {
        _amount = _amount.substring(0, _amount.length - 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 412),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                  children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.black87),
                    ),
                    const Spacer(),
                    const Text(
                      'اضافة مصروف',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text('الفئة', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.2,
                  ),
                  itemCount: _categories.length,
                  itemBuilder: (_, index) {
                    final category = _categories[index];
                    return _ExpenseCategoryTile(
                      label: category['name'] as String,
                      icon: category['icon'] as IconData,
                      active: _selectedCategory == category['name'],
                      onTap: () {
                        setState(() {
                          _selectedCategory = category['name'] as String;
                        });
                      },
                    );
                  },
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD9D4E8),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0xFFAEB6BB)),
                  ),
                  child: Column(
                    children: [
                      const Text('المبلغ', style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 8),
                      Text(
                        '${_amount}₪',
                        style: const TextStyle(fontSize: 42, height: 1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 284,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 37,
                    runSpacing: 16,
                    children: [
                      for (var i = 1; i <= 9; i++)
                        _NumpadButton(
                          label: '$i',
                          onTap: () => _appendDigit('$i'),
                        ),
                      const SizedBox(width: 70, height: 70),
                      _NumpadButton(
                        label: '0',
                        onTap: () => _appendDigit('0'),
                      ),
                      _NumpadButton(
                        label: '⌫',
                        small: true,
                        onTap: _backspace,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ExpenseDetailsScreen(
                            amount: _amount,
                            category: _selectedCategory,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6856A5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: const Text(
                      'التالي',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
                  ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ExpenseDetailsScreen extends StatefulWidget {
  final String amount;
  final String category;
  const ExpenseDetailsScreen({
    super.key,
    required this.amount,
    required this.category,
  });

  @override
  State<ExpenseDetailsScreen> createState() => _ExpenseDetailsScreenState();
}

class _ExpenseDetailsScreenState extends State<ExpenseDetailsScreen> {
  late String _selectedCategory;
  String _selectedPayment = 'كاش';
  final TextEditingController _noteController = TextEditingController();

  static const List<Map<String, dynamic>> _categories = [
    {'name': 'طعام', 'icon': Icons.restaurant_rounded},
    {'name': 'مواصلات', 'icon': Icons.directions_car_filled_rounded},
    {'name': 'قهوة', 'icon': Icons.local_cafe_rounded},
    {'name': 'تسوق', 'icon': Icons.shopping_bag_rounded},
    {'name': 'صحة', 'icon': Icons.favorite_outline_rounded},
    {'name': 'ترفيه', 'icon': Icons.sports_esports_rounded},
    {'name': 'التعليم', 'icon': Icons.menu_book_rounded},
    {'name': 'تسوق', 'icon': Icons.shopping_cart_outlined},
  ];

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.category;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.black87),
                    ),
                    const Spacer(),
                    const Text(
                      'تفاصيل المصروف',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F3FF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFD1D5DC)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text(
                          'تعديل',
                          style: TextStyle(color: Color(0xFF0A0A0A), fontSize: 14),
                        ),
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'المبلغ',
                            style: TextStyle(color: Color(0xFF6A7282), fontSize: 14),
                          ),
                          Text(
                            '${widget.amount}₪',
                            style: const TextStyle(
                              color: Color(0xFF6856A5),
                              fontSize: 32,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text('الفئة', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.2,
                  ),
                  itemCount: _categories.length,
                  itemBuilder: (_, index) {
                    final category = _categories[index];
                    return _ExpenseCategoryTile(
                      label: category['name'] as String,
                      icon: category['icon'] as IconData,
                      active: _selectedCategory == category['name'],
                      onTap: () {
                        setState(() {
                          _selectedCategory = category['name'] as String;
                        });
                      },
                    );
                  },
                ),
                const SizedBox(height: 18),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text('طريقة الدفع', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _PaymentMethodCard(
                        label: 'كاش',
                        icon: Icons.payments_outlined,
                        active: _selectedPayment == 'كاش',
                        onTap: () => setState(() => _selectedPayment = 'كاش'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PaymentMethodCard(
                        label: 'بطاقة',
                        icon: Icons.credit_card_rounded,
                        active: _selectedPayment == 'بطاقة',
                        onTap: () => setState(() => _selectedPayment = 'بطاقة'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _PaymentMethodCard(
                        label: 'تحويل',
                        icon: Icons.swap_horiz_rounded,
                        active: _selectedPayment == 'تحويل',
                        onTap: () => setState(() => _selectedPayment = 'تحويل'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text('ملاحظة (اختياري)', style: TextStyle(fontSize: 15)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _noteController,
                  maxLines: 4,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    hintText: 'مثال: غذاء مع الزملاء',
                    hintStyle: const TextStyle(color: Color(0x7F0A0A0A), fontSize: 14),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFF6856A5)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: () async {
                      final parsedAmount = int.tryParse(
                            widget.amount.replaceAll(RegExp(r'[^0-9]'), ''),
                          ) ??
                          0;
                      await _AppStorage.addExpense(
                        amount: parsedAmount,
                        category: _selectedCategory,
                        paymentMethod: _selectedPayment,
                        note: _noteController.text.trim(),
                      );
                      showDialog<void>(
                        context: context,
                        barrierColor: Colors.black.withValues(alpha: 0.58),
                        builder: (dialogContext) => _ExpenseSavedDialog(
                          amount: widget.amount,
                          category: _selectedCategory,
                          paymentMethod: _selectedPayment,
                          onGoHome: () {
                            Navigator.of(dialogContext).pop();
                            Navigator.of(context).popUntil((route) => route.isFirst);
                          },
                          onAddAnother: () {
                            Navigator.of(dialogContext).pop();
                            Navigator.of(context).pop();
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const AddExpenseScreen()),
                            );
                          },
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6856A5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: const Text(
                      'حفظ المصروف',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ExpensesHistoryScreen extends StatefulWidget {
  const ExpensesHistoryScreen({super.key});

  @override
  State<ExpensesHistoryScreen> createState() => _ExpensesHistoryScreenState();
}

class _ExpensesHistoryScreenState extends State<ExpensesHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _expensesFuture;

  @override
  void initState() {
    super.initState();
    _expensesFuture = _AppStorage.getExpenses();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _expensesFuture,
            builder: (context, snapshot) {
              final expenses = snapshot.data ?? const <Map<String, dynamic>>[];
              final total = expenses.fold<int>(0, (sum, e) => sum + ((e['amount'] as num?)?.toInt() ?? 0));
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back, color: Colors.black87),
                        ),
                        const Spacer(),
                        const Text(
                          'سجل كل المصاريف',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F3FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(
                      children: [
                        Text('الإجمالي: ${total}₪', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('عدد العمليات: ${expenses.length}', style: const TextStyle(fontSize: 14, color: Color(0xFF6A7282))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: expenses.isEmpty
                        ? const Center(
                            child: Text(
                              'لا يوجد مصاريف محفوظة بعد',
                              style: TextStyle(fontSize: 16, color: Color(0xFF6A7282)),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: expenses.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, index) {
                              final e = expenses[index];
                              final amount = (e['amount'] as num?)?.toInt() ?? 0;
                              final category = (e['category'] as String?) ?? 'أخرى';
                              final payment = (e['paymentMethod'] as String?) ?? 'كاش';
                              final note = (e['note'] as String?) ?? '';
                              final createdAt = (e['createdAt'] as String?) ?? '';
                              final dt = DateTime.tryParse(createdAt);
                              final dateLabel = dt == null
                                  ? '-'
                                  : '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFE5E7EB)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          '$amount₪',
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF6856A5),
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          category,
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'الدفع: $payment',
                                      style: const TextStyle(fontSize: 13, color: Color(0xFF6A7282)),
                                    ),
                                    if (note.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'ملاحظة: $note',
                                        style: const TextStyle(fontSize: 13, color: Color(0xFF6A7282)),
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      dateLabel,
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF9AA0AC)),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _PaymentMethodCard({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 69,
        decoration: BoxDecoration(
          color: active ? const Color(0xFFF4F3FF) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? const Color(0xFF6856A5) : const Color(0xFF6A7282),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: active ? const Color(0xFF6856A5) : const Color(0xFF6A7282)),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                color: active ? const Color(0xFF6856A5) : const Color(0xFF6A7282),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseSavedDialog extends StatelessWidget {
  final String amount;
  final String category;
  final String paymentMethod;
  final VoidCallback onGoHome;
  final VoidCallback onAddAnother;

  const _ExpenseSavedDialog({
    required this.amount,
    required this.category,
    required this.paymentMethod,
    required this.onGoHome,
    required this.onAddAnother,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Stack(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 20),
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 81,
                  height: 81,
                  decoration: const BoxDecoration(
                    color: Color(0xFF6856A5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 42),
                ),
                const SizedBox(height: 14),
                const Text(
                  'تم تسجيل المصروف',
                  style: TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 2),
                const Text(
                  'بتوفر وبتتحسن كل يوم',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF9F5),
                    border: Border.all(color: const Color(0xFFB9B9B9)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      _SummaryRow(label: 'المبلغ', value: '₪ $amount', highlight: true),
                      const SizedBox(height: 12),
                      _SummaryRow(label: 'الفئة', value: category),
                      const SizedBox(height: 12),
                      _SummaryRow(label: 'طريقة الدفع', value: paymentMethod, highlight: true),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 47,
                  child: ElevatedButton(
                    onPressed: onGoHome,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6856A5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text(
                      'الرجوع للرئيسية',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: onAddAnother,
                  child: const Text(
                    'اضافة مصروف جديد',
                    style: TextStyle(
                      color: Color(0xFF3C3D3D),
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 30,
            left: 10,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _SummaryRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          value,
          style: TextStyle(
            color: highlight ? const Color(0xFF6856A5) : const Color(0xFF3C3D3D),
            fontSize: 14,
          ),
        ),
        const Spacer(),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF3C3D3D),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _ExpenseCategoryTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _ExpenseCategoryTile({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: active ? const Color(0xFF6856A5) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE4E4E4)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: active ? Colors.white : const Color(0xFF6856A5)),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: active ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumpadButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool small;
  const _NumpadButton({
    required this.label,
    required this.onTap,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(35),
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x33000000)),
          color: Colors.white,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: small ? 22 : 32,
            color: const Color(0xFF14121E),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class AddGoalScreen extends StatefulWidget {
  const AddGoalScreen({super.key});

  @override
  State<AddGoalScreen> createState() => _AddGoalScreenState();
}

class _AddGoalScreenState extends State<AddGoalScreen> {
  final TextEditingController _goalNameController = TextEditingController();
  String _selectedGoalType = 'توفير مبلغ';

  final List<_GoalTypeItem> _goalTypes = const [
    _GoalTypeItem(
      title: 'توفير مبلغ',
      subtitle: 'وفّر مبلغ معين خلال مدة',
      icon: Icons.savings_outlined,
    ),
    _GoalTypeItem(
      title: 'تقليل مصاريف',
      subtitle: 'قلل فئة معينة شهريا',
      icon: Icons.trending_down_rounded,
    ),
    _GoalTypeItem(
      title: 'صندوق طوارئ',
      subtitle: '3-6 أشهر من مصاريفك',
      icon: Icons.priority_high_rounded,
    ),
    _GoalTypeItem(
      title: 'هدف حر',
      subtitle: 'خصص هدفك بنفسك',
      icon: Icons.gesture_rounded,
    ),
  ];

  @override
  void dispose() {
    _goalNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.black87),
                    ),
                    const Spacer(),
                    const Text(
                      'اضافة هدف جديد',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text('اسم الهدف', style: TextStyle(fontSize: 13)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _goalNameController,
                  textAlign: TextAlign.right,
                  decoration: InputDecoration(
                    hintText: 'مثال: توفير لرحلة، طوارئ',
                    hintStyle: const TextStyle(color: Color(0xFF707070), fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFD9D9D9)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFD9D9D9)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF6856A5)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text('نوع الهدف', style: TextStyle(fontSize: 13)),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: GridView.builder(
                    itemCount: _goalTypes.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 15,
                      childAspectRatio: 1.37,
                    ),
                    itemBuilder: (_, index) {
                      final item = _goalTypes[index];
                      final active = item.title == _selectedGoalType;
                      return InkWell(
                        onTap: () => setState(() => _selectedGoalType = item.title),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          decoration: BoxDecoration(
                            color: active ? const Color(0xFF6856A5) : const Color(0xFFEDEDED),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: active ? const Color(0xFF9C8DCF) : const Color(0xFFD5D7D8),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                item.icon,
                                size: 34,
                                color: active ? Colors.white : const Color(0xFF6856A5),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                item.title,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 20,
                                  color: active ? Colors.white : Colors.black,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                item.subtitle,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: active ? const Color(0xFFF7F7F7) : const Color(0xFF3C3D3D),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0x91E67A8A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFEF4961)),
                  ),
                  child: const Text(
                    'وفّر ولو 10% من دخلك شهرياً — بعد سنة رح تتفاجأ بالنتيجة!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFEF4961), fontSize: 12),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => GoalAmountDurationScreen(
                            goalName: _goalNameController.text.trim(),
                            goalType: _selectedGoalType,
                          ),
                        ),
                      );
                    },
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.chevron_left, color: Colors.white),
                    label: const Text(
                      'التالي',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6856A5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoalTypeItem {
  final String title;
  final String subtitle;
  final IconData icon;
  const _GoalTypeItem({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

class GoalAmountDurationScreen extends StatefulWidget {
  final String goalName;
  final String goalType;
  const GoalAmountDurationScreen({
    super.key,
    required this.goalName,
    required this.goalType,
  });

  @override
  State<GoalAmountDurationScreen> createState() => _GoalAmountDurationScreenState();
}

class _GoalAmountDurationScreenState extends State<GoalAmountDurationScreen> {
  String _amount = '0';
  String _selectedDuration = 'شهر';
  final List<String> _durations = const ['شهر', '3 أشهر', '6 أشهر', 'سنة'];

  void _appendDigit(String digit) {
    setState(() {
      if (_amount == '0') {
        _amount = digit;
      } else {
        _amount += digit;
      }
    });
  }

  void _backspace() {
    setState(() {
      if (_amount.length <= 1) {
        _amount = '0';
      } else {
        _amount = _amount.substring(0, _amount.length - 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.black87),
                    ),
                    const Spacer(),
                    const Text(
                      'المبلغ والمدة',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerRight,
                  child: Text('المبلغ المستهدف', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD9D4E8),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0x6B3B1C5D)),
                  ),
                  child: Column(
                    children: [
                      const Text('المبلغ', style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 8),
                      Text(
                        '${_amount}₪',
                        style: const TextStyle(fontSize: 42, height: 1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 284,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 37,
                    runSpacing: 16,
                    children: [
                      for (var i = 1; i <= 9; i++)
                        _NumpadButton(
                          label: '$i',
                          onTap: () => _appendDigit('$i'),
                        ),
                      const SizedBox(width: 70, height: 70),
                      _NumpadButton(
                        label: '0',
                        onTap: () => _appendDigit('0'),
                      ),
                      _NumpadButton(
                        label: '⌫',
                        small: true,
                        onTap: _backspace,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F5FA),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFCCCCCC)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('المدة الزمنية', style: TextStyle(fontSize: 16)),
                      const SizedBox(height: 10),
                      Row(
                        children: _durations
                            .map(
                              (duration) => Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 3),
                                  child: InkWell(
                                    onTap: () => setState(() => _selectedDuration = duration),
                                    borderRadius: BorderRadius.circular(5),
                                    child: Container(
                                      height: 49,
                                      decoration: BoxDecoration(
                                        color: _selectedDuration == duration ? const Color(0xFF6856A5) : Colors.white,
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(
                                          color: _selectedDuration == duration
                                              ? const Color(0xFF716793)
                                              : const Color(0xFFC1C2C2),
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        duration,
                                        style: TextStyle(
                                          color: _selectedDuration == duration ? Colors.white : const Color(0xFF3C3D3D),
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => GoalPreviewScreen(
                            goalName: widget.goalName.isEmpty ? 'هدفي الجديد' : widget.goalName,
                            goalType: widget.goalType,
                            targetAmount: _amount,
                            duration: _selectedDuration,
                          ),
                        ),
                      );
                    },
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.chevron_left, color: Colors.white),
                    label: const Text(
                      'التالي - معاينة',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6856A5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class GoalPreviewScreen extends StatefulWidget {
  final String goalName;
  final String goalType;
  final String targetAmount;
  final String duration;
  const GoalPreviewScreen({
    super.key,
    required this.goalName,
    required this.goalType,
    required this.targetAmount,
    required this.duration,
  });

  @override
  State<GoalPreviewScreen> createState() => _GoalPreviewScreenState();
}

class _GoalPreviewScreenState extends State<GoalPreviewScreen> {
  String _reminder = 'يومي';

  int get _days {
    switch (widget.duration) {
      case 'شهر':
        return 30;
      case '3 أشهر':
        return 90;
      case '6 أشهر':
        return 180;
      case 'سنة':
        return 365;
      default:
        return 30;
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = int.tryParse(widget.targetAmount) ?? 0;
    final daily = _days == 0 ? 0 : (target / _days).ceil();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.black87),
                    ),
                    const Spacer(),
                    const Text(
                      'معاينة الهدف',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF9F5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFC2C3C4)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Text('نشط', style: TextStyle(color: Color(0xFF2AA92E), fontSize: 12)),
                          const Spacer(),
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: const Color(0x35574365),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.savings_outlined, color: Color(0xFF6856A5)),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(widget.goalName, style: const TextStyle(fontSize: 18)),
                              Text(widget.goalType, style: const TextStyle(color: Color(0xFF838383), fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                      const Divider(color: Color(0xFFC5C5C5)),
                      _GoalDetailRow(label: 'المبلغ المستهدف', value: '₪ $target', highlight: true),
                      const SizedBox(height: 10),
                      const _GoalDetailRow(label: 'المدخر حتى الان', value: '₪ 0'),
                      const SizedBox(height: 10),
                      _GoalDetailRow(label: 'المدة', value: widget.duration),
                      const SizedBox(height: 10),
                      _GoalDetailRow(label: 'يجب توفير يوميا', value: '₪ $daily / يوم', highlight: true),
                      const SizedBox(height: 10),
                      Row(
                        children: const [
                          Text('0%', style: TextStyle(fontSize: 14)),
                          Spacer(),
                          Text('0%', style: TextStyle(fontSize: 14)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(50),
                        child: const LinearProgressIndicator(
                          minHeight: 13,
                          value: 0,
                          color: Color(0xFF6856A5),
                          backgroundColor: Color(0xFFC4C4C4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  height: 51,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6856A5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'كل ₪ بتوفرها بتقربك من هدفك. ابدأ اليوم!',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9F5FA),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFCCCCCC)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('تذكير تلقائي', style: TextStyle(fontSize: 16)),
                      const SizedBox(height: 10),
                      Row(
                        children: ['يومي', 'أسبوعي', 'بدون']
                            .map(
                              (value) => Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 3),
                                  child: InkWell(
                                    onTap: () => setState(() => _reminder = value),
                                    borderRadius: BorderRadius.circular(5),
                                    child: Container(
                                      height: 49,
                                      decoration: BoxDecoration(
                                        color: _reminder == value ? const Color(0xFF6856A5) : Colors.white,
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(color: const Color(0xFFC1C2C2)),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        value,
                                        style: TextStyle(
                                          color: _reminder == value ? Colors.white : const Color(0xFF3C3D3D),
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: () async {
                      await _AppStorage.addGoal(
                        name: widget.goalName,
                        goalType: widget.goalType,
                        targetAmount: target,
                        duration: widget.duration,
                        reminder: _reminder,
                      );
                      final rootNav = Navigator.of(context, rootNavigator: true);
                      showDialog<void>(
                        context: context,
                        barrierColor: Colors.black.withValues(alpha: 0.58),
                        builder: (dialogContext) => _GoalCreatedDialog(
                          goalName: widget.goalName,
                          amount: target.toString(),
                          duration: widget.duration,
                          dailyAmount: daily.toString(),
                          onShowGoals: () {
                            rootNav.pop();
                            rootNav.push(
                              MaterialPageRoute(builder: (_) => const GoalsScreen()),
                            );
                          },
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6856A5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                    child: const Text(
                      'حفظ الهدف',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoalDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _GoalDetailRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          value,
          style: TextStyle(
            color: highlight ? const Color(0xFF6856A5) : const Color(0xFF3C3D3D),
            fontSize: 12,
          ),
        ),
        const Spacer(),
        Text(label, style: const TextStyle(color: Color(0xFF45413C), fontSize: 12)),
      ],
    );
  }
}

class _GoalCreatedDialog extends StatelessWidget {
  final String goalName;
  final String amount;
  final String duration;
  final String dailyAmount;
  final VoidCallback onShowGoals;

  const _GoalCreatedDialog({
    required this.goalName,
    required this.amount,
    required this.duration,
    required this.dailyAmount,
    required this.onShowGoals,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Stack(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 20),
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 81,
                  height: 81,
                  decoration: const BoxDecoration(
                    color: Color(0xFF6856A5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.track_changes_outlined, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 12),
                const Text('تم إنشاء الهدف!', style: TextStyle(fontSize: 22)),
                const SizedBox(height: 4),
                const Text(
                  '"هدف جديد" أُضيف لقائمة أهدافك — يلّا نبدأ!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF9F5),
                    border: Border.all(color: const Color(0xFFB9B9B9)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      _GoalCreatedRow(label: 'الهدف', value: goalName),
                      const SizedBox(height: 10),
                      _GoalCreatedRow(label: 'المبلغ', value: '₪ $amount', highlight: true),
                      const SizedBox(height: 10),
                      _GoalCreatedRow(label: 'المدة', value: duration),
                      const SizedBox(height: 10),
                      _GoalCreatedRow(label: 'وفر يوميا', value: '₪ $dailyAmount', highlight: true),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 47,
                  child: ElevatedButton(
                    onPressed: onShowGoals,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6856A5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text(
                      'عرض أهدافي',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 30,
            left: 8,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalCreatedRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _GoalCreatedRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          value,
          style: TextStyle(
            color: highlight ? const Color(0xFF6856A5) : const Color(0xFF3C3D3D),
            fontSize: 14,
          ),
        ),
        const Spacer(),
        Text(label, style: const TextStyle(color: Color(0xFF3C3D3D), fontSize: 14)),
      ],
    );
  }
}

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  late Future<List<Map<String, dynamic>>> _goalsFuture;

  @override
  void initState() {
    super.initState();
    _goalsFuture = _AppStorage.getGoals();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _goalsFuture,
            builder: (context, snapshot) {
              final goals = snapshot.data ?? const <Map<String, dynamic>>[];
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.black87),
                    ),
                    const Spacer(),
                    const Text(
                      'الاهداف',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AddGoalScreen()),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD9D4E8),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 16, color: Color(0xFF6856A5)),
                          SizedBox(width: 6),
                          Text(
                            'اضافة هدف',
                            style: TextStyle(color: Color(0xFF6856A5), fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (goals.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 26),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF6856A5), width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.add, color: Color(0xFF6856A5)),
                        SizedBox(height: 8),
                        Text(
                          'أضف هدفًا جديدًا ،ابدأ رحلتك نحو الاستقرار المالي',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF6F7474), fontSize: 14),
                        ),
                      ],
                    ),
                  )
                else
                  ...goals.map((goal) {
                    final target = (goal['targetAmount'] as num?)?.toInt() ?? 0;
                    final saved = (goal['savedAmount'] as num?)?.toInt() ?? 0;
                    final ratio = target <= 0 ? 0.0 : (saved / target).clamp(0.0, 1.0);
                    final percent = (ratio * 100).round();
                    final remain = math.max(0, target - saved);
                    final duration = (goal['duration'] as String?) ?? 'شهر';
                    final days = duration == 'سنة'
                        ? 365
                        : duration == '6 أشهر'
                            ? 180
                            : duration == '3 أشهر'
                                ? 90
                                : 30;
                    final daily = days == 0 ? 0 : (remain / days).ceil();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _GoalSummaryCard(
                        danger: percent > 100,
                        statusLabel: percent > 100 ? 'تحذير' : 'نشط',
                        statusColor: percent > 100 ? const Color(0xFFD81633) : const Color(0xFF22BB27),
                        title: '${goal['name']}',
                        subtitle: duration,
                        leftTop: '$saved ₪ من $target ₪',
                        leftPercent: '$percent%',
                        progress: ratio,
                        footerText: 'وفّر $daily ₪ يوميًا لتحقق الهدف',
                      ),
                    );
                  }),
              ],
            ),
              );
            },
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddGoalScreen()),
            );
          },
          backgroundColor: const Color(0xFF6856A5),
          shape: const CircleBorder(),
          child: const Icon(Icons.add, color: Colors.white),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: BottomAppBar(
          shape: const CircularNotchedRectangle(),
          notchMargin: 8,
          color: Colors.white,
          elevation: 12,
          child: SizedBox(
            height: 74,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.person_outline,
                  label: 'حسابي',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AccountScreen()),
                    );
                  },
                ),
                _NavItem(
                  icon: Icons.emoji_events_outlined,
                  label: 'الانجازات',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AchievementsScreen()),
                    );
                  },
                ),
                const SizedBox(width: 36),
                _NavItem(
                  icon: Icons.analytics_outlined,
                  label: 'تحليل',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AnalysisScreen()),
                    );
                  },
                ),
                _NavItem(
                  icon: Icons.home_rounded,
                  label: 'الرئيسية',
                  onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoalSummaryCard extends StatelessWidget {
  final bool danger;
  final String statusLabel;
  final Color statusColor;
  final String title;
  final String subtitle;
  final String leftTop;
  final String leftPercent;
  final double progress;
  final String footerText;

  const _GoalSummaryCard({
    required this.danger,
    required this.statusLabel,
    required this.statusColor,
    required this.title,
    required this.subtitle,
    required this.leftTop,
    required this.leftPercent,
    required this.progress,
    required this.footerText,
  });

  @override
  Widget build(BuildContext context) {
    final bg = danger ? const Color(0xFFFFE7E8) : const Color(0xFFEDEDED);
    final border = danger ? const Color(0x72DE0303) : const Color(0xFFCCCCCC);
    final bar = danger ? const Color(0xB7DE0306) : const Color(0xFF6856A5);
    final footerBg = danger ? const Color(0xFFE74346) : const Color(0xFF6856A5);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 14)),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14)),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF6A6A6A))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(leftTop, style: const TextStyle(fontSize: 14)),
              const Spacer(),
              Text(leftPercent, style: TextStyle(color: statusColor, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(50),
            child: LinearProgressIndicator(
              minHeight: 13,
              value: progress.clamp(0.0, 1.0),
              color: bar,
              backgroundColor: const Color(0xFFA5A5A5),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            height: 39,
            decoration: BoxDecoration(
              color: footerBg,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              danger ? 'Fix It الان' : footerText,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          if (danger)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                footerText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF860C0C), fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
