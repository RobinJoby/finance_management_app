import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AppDatabase {
  static const _expensesKey = 'db_expenses';
  static const _incomesKey = 'db_incomes';

  // In-memory cache populated from SharedPreferences on first use
  final List<Expense> _expenses = [];
  final List<Income> _incomes = [];
  bool _initialized = false;

  // ─── Initialisation ──────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();

    // Load expenses
    final expJson = prefs.getString(_expensesKey);
    if (expJson != null) {
      try {
        final list = jsonDecode(expJson) as List<dynamic>;
        _expenses
          ..clear()
          ..addAll(
            list.map((e) => Expense.fromJson(e as Map<String, dynamic>)),
          );
      } catch (_) {
        _expenses.clear();
      }
    }

    // Load incomes
    final incJson = prefs.getString(_incomesKey);
    if (incJson != null) {
      try {
        final list = jsonDecode(incJson) as List<dynamic>;
        _incomes
          ..clear()
          ..addAll(list.map((i) => Income.fromJson(i as Map<String, dynamic>)));
      } catch (_) {
        _incomes.clear();
      }
    }
  }

  // ─── Persistence helpers ──────────────────────────────────────────────────

  Future<void> _saveExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _expensesKey,
      jsonEncode(_expenses.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _saveIncomes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _incomesKey,
      jsonEncode(_incomes.map((i) => i.toJson()).toList()),
    );
  }

  // ─── Expense API ─────────────────────────────────────────────────────────

  // Alias for backwards compatibility
  List<dynamic> get expenses => _expenses;

  Future<void> addExpense(Expense expense) async {
    await initialize();
    _expenses.add(expense);
    await _saveExpenses();
  }

  Future<List<Expense>> getAllExpenses() async {
    await initialize();
    return List.from(_expenses);
  }

  Future<void> deleteExpense(String id) async {
    await initialize();
    _expenses.removeWhere((e) => e.id == id);
    await _saveExpenses();
  }

  Future<void> updateExpense(Expense expense) async {
    await initialize();
    final index = _expenses.indexWhere((e) => e.id == expense.id);
    if (index >= 0) {
      _expenses[index] = expense;
      await _saveExpenses();
    }
  }

  Future<List<Expense>> getExpensesByCategory(String category) async {
    await initialize();
    return _expenses.where((e) => e.category == category).toList();
  }

  Future<List<Expense>> getExpensesByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    await initialize();
    return _expenses
        .where(
          (e) =>
              e.timestamp.isAfter(startDate) && e.timestamp.isBefore(endDate),
        )
        .toList();
  }

  // ─── Income API ───────────────────────────────────────────────────────────

  Future<void> addIncome(Income income) async {
    await initialize();
    _incomes.add(income);
    await _saveIncomes();
  }

  Future<List<Income>> getAllIncomes() async {
    await initialize();
    return List.from(_incomes);
  }

  Future<void> deleteIncome(String id) async {
    await initialize();
    _incomes.removeWhere((i) => i.id == id);
    await _saveIncomes();
  }

  Future<void> updateIncome(Income income) async {
    await initialize();
    final index = _incomes.indexWhere((i) => i.id == income.id);
    if (index >= 0) {
      _incomes[index] = income;
      await _saveIncomes();
    }
  }

  Future<List<Income>> getIncomesByCategory(String category) async {
    await initialize();
    return _incomes.where((i) => i.category == category).toList();
  }

  Future<List<Income>> getIncomesByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    await initialize();
    return _incomes
        .where(
          (i) =>
              i.timestamp.isAfter(startDate) && i.timestamp.isBefore(endDate),
        )
        .toList();
  }
}

// ─── Models ───────────────────────────────────────────────────────────────────

class Expense {
  final String id;
  final double amount;
  final String category;
  final bool isWant;
  final DateTime timestamp;
  final bool isSynced;

  Expense({
    required this.id,
    required this.amount,
    required this.category,
    required this.isWant,
    required this.timestamp,
    this.isSynced = false,
  });

  // Convert to JSON
  Map<String, dynamic> toJson() => {
    'id': id,
    'amount': amount,
    'category': category,
    'isWant': isWant,
    'timestamp': timestamp.toIso8601String(),
    'isSynced': isSynced,
  };

  // Create from JSON
  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
    id: json['id'] as String,
    amount: (json['amount'] as num).toDouble(),
    category: json['category'] as String,
    isWant: json['isWant'] as bool,
    timestamp: DateTime.parse(json['timestamp'] as String),
    isSynced: json['isSynced'] as bool? ?? false,
  );

  // Copy with method
  Expense copyWith({
    String? id,
    double? amount,
    String? category,
    bool? isWant,
    DateTime? timestamp,
    bool? isSynced,
  }) => Expense(
    id: id ?? this.id,
    amount: amount ?? this.amount,
    category: category ?? this.category,
    isWant: isWant ?? this.isWant,
    timestamp: timestamp ?? this.timestamp,
    isSynced: isSynced ?? this.isSynced,
  );
}

class Income {
  final String id;
  final double amount;
  final String category;
  final DateTime timestamp;
  final bool isSynced;

  Income({
    required this.id,
    required this.amount,
    required this.category,
    required this.timestamp,
    this.isSynced = false,
  });

  // Convert to JSON
  Map<String, dynamic> toJson() => {
    'id': id,
    'amount': amount,
    'category': category,
    'timestamp': timestamp.toIso8601String(),
    'isSynced': isSynced,
  };

  // Create from JSON
  factory Income.fromJson(Map<String, dynamic> json) => Income(
    id: json['id'] as String,
    amount: (json['amount'] as num).toDouble(),
    category: json['category'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    isSynced: json['isSynced'] as bool? ?? false,
  );

  // Copy with method
  Income copyWith({
    String? id,
    double? amount,
    String? category,
    DateTime? timestamp,
    bool? isSynced,
  }) => Income(
    id: id ?? this.id,
    amount: amount ?? this.amount,
    category: category ?? this.category,
    timestamp: timestamp ?? this.timestamp,
    isSynced: isSynced ?? this.isSynced,
  );
}
