import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

void main() {
  runApp(const LuxeBudgetApp());
}

class LuxeBudgetApp extends StatelessWidget {
  const LuxeBudgetApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: LuxeColors.ink,
      fontFamily: 'SF Pro Display',
      colorScheme: const ColorScheme.dark(
        primary: LuxeColors.orange,
        secondary: LuxeColors.gold,
        surface: LuxeColors.panel,
      ),
      useMaterial3: true,
      textTheme: Theme.of(context).textTheme.apply(
            bodyColor: Colors.white,
            displayColor: Colors.white,
          ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Luxe Budget Desktop',
      theme: theme,
      home: const ExpenseDashboardPage(),
    );
  }
}

class LuxeColors {
  static const orange = Color(0xFFF57A29);
  static const orangeSoft = Color(0xFFFFA351);
  static const ember = Color(0xFFC45027);
  static const gold = Color(0xFFF9C56C);
  static const ink = Color(0xFF0E0E12);
  static const panel = Color(0xFF17181D);
  static const panelSoft = Color(0xFF212229);
  static const line = Color(0x22FFFFFF);
  static const textSoft = Color(0xB8FFFFFF);
}

enum EntryType {
  expense,
  income;

  String get label => name[0].toUpperCase() + name.substring(1);
}

enum EntryTypeFilter {
  all,
  expense,
  income;
}

class CategoryDefinition {
  CategoryDefinition({
    required this.id,
    required this.name,
    required this.type,
  });

  final String id;
  String name;
  EntryType type;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
      };

  factory CategoryDefinition.fromJson(Map<String, dynamic> json) {
    return CategoryDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      type: EntryType.values.byName(json['type'] as String),
    );
  }
}

class ExpenseEntry {
  ExpenseEntry({
    required this.id,
    required this.title,
    required this.amount,
    required this.date,
    required this.type,
    required this.category,
    this.note = '',
  });

  final String id;
  String title;
  double amount;
  DateTime date;
  EntryType type;
  String category;
  String note;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'amount': amount,
        'date': date.toIso8601String(),
        'type': type.name,
        'category': category,
        'note': note,
      };

  factory ExpenseEntry.fromJson(Map<String, dynamic> json) {
    return ExpenseEntry(
      id: json['id'] as String,
      title: json['title'] as String,
      amount: (json['amount'] as num).toDouble(),
      date: DateTime.parse(json['date'] as String),
      type: EntryType.values.byName(json['type'] as String),
      category: json['category'] as String,
      note: (json['note'] as String?) ?? '',
    );
  }
}

class ExpenseSummary {
  const ExpenseSummary({
    required this.income,
    required this.expenses,
  });

  final double income;
  final double expenses;

  double get balance => income - expenses;
}

class ChartSliceData {
  const ChartSliceData({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;
}

class TrendPoint {
  const TrendPoint({
    required this.date,
    required this.amount,
  });

  final DateTime date;
  final double amount;
}

class RecurringEntry {
  RecurringEntry({
    required this.id,
    required this.title,
    required this.amount,
    required this.dayOfMonth,
    required this.type,
    required this.category,
    this.note = '',
    this.active = true,
  });

  final String id;
  String title;
  double amount;
  int dayOfMonth;
  EntryType type;
  String category;
  String note;
  bool active;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'amount': amount,
        'dayOfMonth': dayOfMonth,
        'type': type.name,
        'category': category,
        'note': note,
        'active': active,
      };

  factory RecurringEntry.fromJson(Map<String, dynamic> json) {
    return RecurringEntry(
      id: json['id'] as String,
      title: json['title'] as String,
      amount: (json['amount'] as num).toDouble(),
      dayOfMonth: (json['dayOfMonth'] as num).toInt(),
      type: EntryType.values.byName(json['type'] as String),
      category: json['category'] as String,
      note: (json['note'] as String?) ?? '',
      active: (json['active'] as bool?) ?? true,
    );
  }

  String occurrenceId(DateTime month) => 'recurring_${id}_${month.year}_${month.month}';

  ExpenseEntry toEntry(DateTime month) {
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    final day = dayOfMonth.clamp(1, lastDay);
    return ExpenseEntry(
      id: occurrenceId(month),
      title: title,
      amount: amount,
      date: DateTime(month.year, month.month, day),
      type: type,
      category: category,
      note: note.isEmpty ? 'Recurring entry' : note,
    );
  }
}

class DashboardInsights {
  const DashboardInsights({
    required this.biggestExpense,
    required this.topCategory,
    required this.averageDailySpend,
    required this.safeToSpend,
    required this.projectedMonthEnd,
  });

  final ExpenseEntry? biggestExpense;
  final MapEntry<String, double>? topCategory;
  final double averageDailySpend;
  final double safeToSpend;
  final double projectedMonthEnd;
}

class ExpenseRepository {
  ExpenseRepository();

  Directory get _baseDir {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    final base = Directory('$home/.luxe_budget_desktop');
    if (!base.existsSync()) {
      base.createSync(recursive: true);
    }
    return base;
  }

  File get _entriesFile => File('${_baseDir.path}/entries.json');
  File get _categoriesFile => File('${_baseDir.path}/categories.json');
  File get _budgetsFile => File('${_baseDir.path}/budgets.json');
  File get _recurringFile => File('${_baseDir.path}/recurring.json');

  Future<List<CategoryDefinition>> loadCategories() async {
    if (!_categoriesFile.existsSync()) {
      await _categoriesFile.writeAsString(
        jsonEncode(defaultCategories.map((e) => e.toJson()).toList()),
      );
      return defaultCategories;
    }

    final raw = await _categoriesFile.readAsString();
    final decoded = (jsonDecode(raw) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(CategoryDefinition.fromJson)
        .toList();

    return decoded;
  }

  Future<List<ExpenseEntry>> loadEntries() async {
    if (!_entriesFile.existsSync()) {
      await _entriesFile.writeAsString(
        jsonEncode(sampleEntries.map((e) => e.toJson()).toList()),
      );
      return sampleEntries;
    }

    final raw = await _entriesFile.readAsString();
    final decoded = (jsonDecode(raw) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(ExpenseEntry.fromJson)
        .toList();
    decoded.sort((a, b) => b.date.compareTo(a.date));
    return decoded;
  }

  Future<void> saveEntries(List<ExpenseEntry> entries) async {
    await _entriesFile.writeAsString(
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> saveCategories(List<CategoryDefinition> categories) async {
    await _categoriesFile.writeAsString(
      jsonEncode(categories.map((e) => e.toJson()).toList()),
    );
  }

  Future<Map<String, double>> loadBudgets() async {
    if (!_budgetsFile.existsSync()) return {};
    final raw = await _budgetsFile.readAsString();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((key, value) => MapEntry(key, (value as num).toDouble()));
  }

  Future<void> saveBudgets(Map<String, double> budgets) async {
    await _budgetsFile.writeAsString(jsonEncode(budgets));
  }

  Future<List<RecurringEntry>> loadRecurringEntries() async {
    if (!_recurringFile.existsSync()) return [];
    final raw = await _recurringFile.readAsString();
    return (jsonDecode(raw) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(RecurringEntry.fromJson)
        .toList();
  }

  Future<void> saveRecurringEntries(List<RecurringEntry> recurringEntries) async {
    await _recurringFile.writeAsString(
      jsonEncode(recurringEntries.map((entry) => entry.toJson()).toList()),
    );
  }

  Future<File> exportCsv(List<ExpenseEntry> entries) async {
    final file = File('${_baseDir.path}/expense_export.csv');
    final rows = <String>[
      'Date,Title,Type,Category,Amount,Note',
      ...entries.map(
        (e) => [
          dateLabel(e.date),
          _csv(e.title),
          e.type.label,
          _csv(e.category),
          e.amount.toStringAsFixed(2),
          _csv(e.note),
        ].join(','),
      ),
    ];
    await file.writeAsString(rows.join('\n'));
    return file;
  }

  Future<List<ExpenseEntry>> importCsv(String path, List<CategoryDefinition> categories) async {
    final file = File(path.trim());
    if (!file.existsSync()) {
      throw const FileSystemException('CSV file does not exist');
    }

    final lines = await file.readAsLines();
    final imported = <ExpenseEntry>[];
    for (int i = 1; i < lines.length; i++) {
      final values = parseCsvLine(lines[i]);
      if (values.length < 5) continue;

      final date = parseFlexibleDate(values[0]);
      final amount = double.tryParse(values[4].replaceAll('₹', '').replaceAll(',', '').trim());
      if (date == null || amount == null) continue;

      final typeText = values[2].trim().toLowerCase();
      final type = EntryType.values.firstWhere(
        (entryType) => entryType.name == typeText || entryType.label.toLowerCase() == typeText,
        orElse: () => EntryType.expense,
      );
      final fallbackCategory = categories.firstWhere(
        (item) => item.type == type,
        orElse: () => defaultCategories.firstWhere((item) => item.type == type),
      );
      final category = values[3].trim().isEmpty ? fallbackCategory.name : values[3].trim();

      imported.add(
        ExpenseEntry(
          id: 'import_${DateTime.now().microsecondsSinceEpoch}_$i',
          title: values[1].trim().isEmpty ? 'Imported entry' : values[1].trim(),
          amount: amount,
          date: date,
          type: type,
          category: category,
          note: values.length > 5 ? values[5].trim() : '',
        ),
      );
    }
    return imported;
  }

  String _csv(String value) => '"${value.replaceAll('"', '""')}"';
}

final defaultCategories = <CategoryDefinition>[
  CategoryDefinition(id: 'housing', name: 'Housing', type: EntryType.expense),
  CategoryDefinition(id: 'food', name: 'Food', type: EntryType.expense),
  CategoryDefinition(id: 'transport', name: 'Transport', type: EntryType.expense),
  CategoryDefinition(id: 'shopping', name: 'Shopping', type: EntryType.expense),
  CategoryDefinition(id: 'entertainment', name: 'Entertainment', type: EntryType.expense),
  CategoryDefinition(id: 'health', name: 'Health', type: EntryType.expense),
  CategoryDefinition(id: 'travel', name: 'Travel', type: EntryType.expense),
  CategoryDefinition(id: 'utilities', name: 'Utilities', type: EntryType.expense),
  CategoryDefinition(id: 'other_expense', name: 'Other Expense', type: EntryType.expense),
  CategoryDefinition(id: 'salary', name: 'Salary', type: EntryType.income),
  CategoryDefinition(id: 'freelance', name: 'Freelance', type: EntryType.income),
  CategoryDefinition(id: 'other_income', name: 'Other Income', type: EntryType.income),
];

final sampleEntries = <ExpenseEntry>[
  ExpenseEntry(
    id: 'e1',
    title: 'Salary',
    amount: 4200,
    date: DateTime.now(),
    type: EntryType.income,
    category: 'Salary',
    note: 'Monthly paycheck',
  ),
  ExpenseEntry(
    id: 'e2',
    title: 'Rent',
    amount: 1450,
    date: DateTime.now().subtract(const Duration(days: 2)),
    type: EntryType.expense,
    category: 'Housing',
    note: 'Apartment rent',
  ),
  ExpenseEntry(
    id: 'e3',
    title: 'Groceries',
    amount: 126.84,
    date: DateTime.now().subtract(const Duration(days: 3)),
    type: EntryType.expense,
    category: 'Food',
    note: 'Weekly grocery run',
  ),
  ExpenseEntry(
    id: 'e4',
    title: 'Internet',
    amount: 79.99,
    date: DateTime.now().subtract(const Duration(days: 4)),
    type: EntryType.expense,
    category: 'Utilities',
  ),
  ExpenseEntry(
    id: 'e5',
    title: 'Design Contract',
    amount: 680,
    date: DateTime.now().subtract(const Duration(days: 6)),
    type: EntryType.income,
    category: 'Freelance',
    note: 'Side project',
  ),
  ExpenseEntry(
    id: 'e6',
    title: 'Dinner Out',
    amount: 61.45,
    date: DateTime.now().subtract(const Duration(days: 7)),
    type: EntryType.expense,
    category: 'Entertainment',
  ),
];

class ExpenseDashboardPage extends StatefulWidget {
  const ExpenseDashboardPage({super.key});

  @override
  State<ExpenseDashboardPage> createState() => _ExpenseDashboardPageState();
}

class _ExpenseDashboardPageState extends State<ExpenseDashboardPage> {
  final repository = ExpenseRepository();
  final searchController = TextEditingController();
  final titleController = TextEditingController();
  final amountController = TextEditingController();
  final noteController = TextEditingController();

  List<ExpenseEntry> entries = [];
  List<CategoryDefinition> categories = [];
  Map<String, double> budgets = {};
  List<RecurringEntry> recurringEntries = [];

  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  EntryTypeFilter typeFilter = EntryTypeFilter.all;
  CategoryDefinition? categoryFilter;
  EntryType newType = EntryType.expense;
  String? newCategory;
  String statusMessage = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    searchController.dispose();
    titleController.dispose();
    amountController.dispose();
    noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final loadedCategories = await repository.loadCategories();
    final loadedEntries = await repository.loadEntries();
    final loadedBudgets = await repository.loadBudgets();
    final loadedRecurring = await repository.loadRecurringEntries();

    setState(() {
      categories = loadedCategories;
      entries = loadedEntries;
      budgets = loadedBudgets;
      recurringEntries = loadedRecurring;
      newCategory = categoriesFor(newType).isNotEmpty ? categoriesFor(newType).first.name : null;
    });
  }

  List<CategoryDefinition> categoriesFor(EntryType type) {
    final filtered = categories.where((c) => c.type == type).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return filtered;
  }

  List<ExpenseEntry> get filteredEntries {
    return entries.where((entry) {
      final monthMatch = entry.date.year == selectedMonth.year && entry.date.month == selectedMonth.month;
      final typeMatch = typeFilter == EntryTypeFilter.all || entry.type.name == typeFilter.name;
      final categoryMatch = categoryFilter == null || entry.category == categoryFilter!.name;
      final query = searchController.text.trim().toLowerCase();
      final searchMatch = query.isEmpty ||
          entry.title.toLowerCase().contains(query) ||
          entry.note.toLowerCase().contains(query);
      return monthMatch && typeMatch && categoryMatch && searchMatch;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  List<ExpenseEntry> get monthEntries {
    return entries.where((entry) {
      return entry.date.year == selectedMonth.year && entry.date.month == selectedMonth.month;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  ExpenseSummary get summary {
    double income = 0;
    double expense = 0;
    for (final entry in filteredEntries) {
      if (entry.type == EntryType.income) {
        income += entry.amount;
      } else {
        expense += entry.amount;
      }
    }
    return ExpenseSummary(income: income, expenses: expense);
  }

  ExpenseSummary get monthSummary {
    double income = 0;
    double expense = 0;
    for (final entry in monthEntries) {
      if (entry.type == EntryType.income) {
        income += entry.amount;
      } else {
        expense += entry.amount;
      }
    }
    return ExpenseSummary(income: income, expenses: expense);
  }

  Map<String, double> get monthExpenseTotalsByCategory {
    final totals = <String, double>{};
    for (final entry in monthEntries.where((entry) => entry.type == EntryType.expense)) {
      totals.update(entry.category, (value) => value + entry.amount, ifAbsent: () => entry.amount);
    }
    return totals;
  }

  DashboardInsights get insights {
    final expenses = monthEntries.where((entry) => entry.type == EntryType.expense).toList();
    final biggest = expenses.isEmpty ? null : expenses.reduce((a, b) => a.amount >= b.amount ? a : b);
    final categoryTotals = monthExpenseTotalsByCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final now = DateTime.now();
    final lastDay = DateTime(selectedMonth.year, selectedMonth.month + 1, 0).day;
    final elapsedDays = selectedMonth.year == now.year && selectedMonth.month == now.month ? now.day : lastDay;
    final averageDaily = elapsedDays == 0 ? 0.0 : monthSummary.expenses / elapsedDays;
    final projectedExpenses = averageDaily * lastDay;
    return DashboardInsights(
      biggestExpense: biggest,
      topCategory: categoryTotals.isEmpty ? null : categoryTotals.first,
      averageDailySpend: averageDaily,
      safeToSpend: math.max(0, monthSummary.balance / math.max(1, lastDay - elapsedDays + 1)),
      projectedMonthEnd: monthSummary.income - projectedExpenses,
    );
  }

  List<ChartSliceData> get categorySlices {
    final palette = [
      LuxeColors.orange,
      LuxeColors.orangeSoft,
      LuxeColors.gold,
      LuxeColors.ember,
      Colors.deepOrange.shade300,
      Colors.amber.shade400,
    ];

    final totals = <String, double>{};
    for (final entry in filteredEntries.where((e) => e.type == EntryType.expense)) {
      totals.update(entry.category, (value) => value + entry.amount, ifAbsent: () => entry.amount);
    }
    final sorted = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (int i = 0; i < sorted.length; i++)
        ChartSliceData(
          label: sorted[i].key,
          value: sorted[i].value,
          color: palette[i % palette.length],
        ),
    ];
  }

  List<TrendPoint> get trendPoints {
    final totals = <DateTime, double>{};
    for (final entry in filteredEntries.where((e) => e.type == EntryType.expense)) {
      final day = DateTime(entry.date.year, entry.date.month, entry.date.day);
      totals.update(day, (value) => value + entry.amount, ifAbsent: () => entry.amount);
    }

    final firstDay = DateTime(selectedMonth.year, selectedMonth.month, 1);
    final lastDay = DateTime(selectedMonth.year, selectedMonth.month + 1, 0);
    final points = <TrendPoint>[];

    for (int day = 1; day <= lastDay.day; day++) {
      final date = DateTime(selectedMonth.year, selectedMonth.month, day);
      points.add(TrendPoint(date: date, amount: totals[date] ?? 0));
    }

    if (points.every((point) => point.amount == 0)) {
      return [
        TrendPoint(date: firstDay, amount: 0),
        TrendPoint(date: lastDay, amount: 0),
      ];
    }

    return points;
  }

  Future<void> _persist() async {
    await repository.saveEntries(entries);
    await repository.saveCategories(categories);
    await repository.saveBudgets(budgets);
    await repository.saveRecurringEntries(recurringEntries);
  }

  Future<void> _addEntry() async {
    final amount = double.tryParse(amountController.text.trim());
    if (titleController.text.trim().isEmpty || amount == null || newCategory == null) {
      _setStatus('Please fill in title, amount, and category.');
      return;
    }

    final entry = ExpenseEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: titleController.text.trim(),
      amount: amount,
      date: selectedMonth.copyWith(day: DateTime.now().day),
      type: newType,
      category: newCategory!,
      note: noteController.text.trim(),
    );

    setState(() {
      entries.insert(0, entry);
      titleController.clear();
      amountController.clear();
      noteController.clear();
      newType = EntryType.expense;
      newCategory = categoriesFor(EntryType.expense).isNotEmpty ? categoriesFor(EntryType.expense).first.name : null;
    });
    await repository.saveEntries(entries);
    _setStatus('Entry added.');
  }

  Future<void> _deleteEntry(ExpenseEntry entry) async {
    setState(() {
      entries.removeWhere((e) => e.id == entry.id);
    });
    await repository.saveEntries(entries);
    _setStatus('Entry deleted.');
  }

  Future<void> _editEntry(ExpenseEntry entry) async {
    final edited = await showDialog<ExpenseEntry>(
      context: context,
      builder: (context) => EditEntryDialog(
        entry: entry,
        categories: categoriesFor(entry.type),
      ),
    );

    if (edited == null) return;
    setState(() {
      final index = entries.indexWhere((e) => e.id == edited.id);
      if (index != -1) {
        entries[index] = edited;
      }
    });
    await repository.saveEntries(entries);
    _setStatus('Entry updated.');
  }

  Future<void> _manageCategories() async {
    await showDialog<void>(
      context: context,
      builder: (context) => CategoryManagerDialog(
        categories: categories,
        onAdd: (name, type) {
          final trimmed = name.trim();
          if (trimmed.isEmpty) return;
          setState(() {
            categories.add(
              CategoryDefinition(
                id: DateTime.now().microsecondsSinceEpoch.toString(),
                name: trimmed,
                type: type,
              ),
            );
            if (newType == type && newCategory == null) {
              newCategory = trimmed;
            }
          });
        },
        onRename: (category, newName) {
          final trimmed = newName.trim();
          if (trimmed.isEmpty) return;
          setState(() {
            final oldName = category.name;
            category.name = trimmed;
            if (budgets.containsKey(oldName)) {
              budgets[trimmed] = budgets.remove(oldName)!;
            }
            for (final entry in entries) {
              if (entry.type == category.type && entry.category == oldName) {
                entry.category = trimmed;
              }
            }
            for (final recurring in recurringEntries) {
              if (recurring.type == category.type && recurring.category == oldName) {
                recurring.category = trimmed;
              }
            }
            if (newCategory == oldName) {
              newCategory = trimmed;
            }
            if (categoryFilter?.name == oldName) {
              categoryFilter = category;
            }
          });
        },
        onDelete: (category) {
          final fallback = categories
              .where((c) => c.type == category.type && c.id != category.id)
              .map((c) => c.name)
              .cast<String?>()
              .firstWhere((_) => true, orElse: () => null);
          setState(() {
            categories.removeWhere((c) => c.id == category.id);
            budgets.remove(category.name);
            if (fallback != null) {
              for (final entry in entries) {
                if (entry.category == category.name && entry.type == category.type) {
                  entry.category = fallback;
                }
              }
              for (final recurring in recurringEntries) {
                if (recurring.category == category.name && recurring.type == category.type) {
                  recurring.category = fallback;
                }
              }
            }
            if (newCategory == category.name) {
              newCategory = categoriesFor(newType).isNotEmpty ? categoriesFor(newType).first.name : null;
            }
            if (categoryFilter?.id == category.id) {
              categoryFilter = null;
            }
          });
        },
      ),
    );

    await _persist();
    _setStatus('Categories updated.');
  }

  Future<void> _manageBudgets() async {
    final updated = await showDialog<Map<String, double>>(
      context: context,
      builder: (context) => BudgetManagerDialog(
        expenseCategories: categoriesFor(EntryType.expense),
        budgets: budgets,
        spending: monthExpenseTotalsByCategory,
      ),
    );
    if (updated == null) return;
    setState(() => budgets = updated);
    await repository.saveBudgets(budgets);
    _setStatus('Budgets updated.');
  }

  Future<void> _manageRecurring() async {
    await showDialog<void>(
      context: context,
      builder: (context) => RecurringManagerDialog(
        recurringEntries: recurringEntries,
        categories: categories,
        onAdd: (entry) {
          setState(() => recurringEntries.add(entry));
        },
        onDelete: (entry) {
          setState(() => recurringEntries.removeWhere((item) => item.id == entry.id));
        },
      ),
    );
    await repository.saveRecurringEntries(recurringEntries);
    _setStatus('Recurring entries updated.');
  }

  Future<void> _applyRecurringEntries() async {
    final additions = recurringEntries
        .where((entry) => entry.active)
        .where((entry) => entries.every((existing) => existing.id != entry.occurrenceId(selectedMonth)))
        .map((entry) => entry.toEntry(selectedMonth))
        .toList();

    if (additions.isEmpty) {
      _setStatus('No new recurring entries for ${monthLabel(selectedMonth)}.');
      return;
    }

    setState(() {
      entries.insertAll(0, additions);
    });
    await repository.saveEntries(entries);
    _setStatus('${additions.length} recurring entr${additions.length == 1 ? 'y' : 'ies'} added.');
  }

  Future<void> _exportCsv() async {
    final file = await repository.exportCsv(entries);
    _setStatus('CSV exported to ${file.path}');
  }

  Future<void> _importCsv() async {
    final path = await showDialog<String>(
      context: context,
      builder: (context) => const ImportCsvDialog(),
    );
    if (path == null || path.trim().isEmpty) return;

    try {
      final imported = await repository.importCsv(path, categories);
      if (imported.isEmpty) {
        _setStatus('No valid entries found in CSV.');
        return;
      }
      setState(() {
        entries.insertAll(0, imported);
        for (final entry in imported) {
          final exists = categories.any((category) => category.name == entry.category && category.type == entry.type);
          if (!exists) {
            categories.add(
              CategoryDefinition(
                id: 'imported_category_${DateTime.now().microsecondsSinceEpoch}_${entry.category}',
                name: entry.category,
                type: entry.type,
              ),
            );
          }
        }
      });
      await _persist();
      _setStatus('${imported.length} entr${imported.length == 1 ? 'y' : 'ies'} imported.');
    } catch (error) {
      _setStatus('Import failed: $error');
    }
  }

  void _setStatus(String message) {
    setState(() {
      statusMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final displayEntries = filteredEntries;

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            categories: categories,
            selectedCategory: categoryFilter,
            summary: summary,
            onSelectCategory: (category) => setState(() => categoryFilter = category),
            onManageCategories: _manageCategories,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final dashboardWidth = math.max(constraints.maxWidth, 1500.0);
                final contentWidth = dashboardWidth - 48;
                final tableWidth = contentWidth - 320 - 18;
                final analyticsCardWidth = (contentWidth - 18) / 2;

                return Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: dashboardWidth,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SummaryHeader(
                              selectedMonth: selectedMonth,
                              summary: summary,
                              insights: insights,
                              onMonthChanged: (date) {
                                setState(() {
                                  selectedMonth = DateTime(date.year, date.month);
                                });
                              },
                            ),
                            const SizedBox(height: 18),
                            _FiltersRow(
                              controller: searchController,
                              typeFilter: typeFilter,
                              onTypeFilterChanged: (value) => setState(() => typeFilter = value),
                              onSearchChanged: (_) => setState(() {}),
                              onExport: _exportCsv,
                              onImport: _importCsv,
                              onManageRecurring: _manageRecurring,
                              onApplyRecurring: _applyRecurringEntries,
                              statusMessage: statusMessage,
                            ),
                            const SizedBox(height: 18),
                            _BudgetOverview(
                              budgets: budgets,
                              spending: monthExpenseTotalsByCategory,
                              onManageBudgets: _manageBudgets,
                            ),
                            const SizedBox(height: 18),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: tableWidth,
                                  child: _TransactionTable(
                                    entries: displayEntries,
                                    onDelete: _deleteEntry,
                                    onEdit: _editEntry,
                                  ),
                                ),
                                const SizedBox(width: 18),
                                SizedBox(
                                  width: 320,
                                  child: _AddEntryCard(
                                    titleController: titleController,
                                    amountController: amountController,
                                    noteController: noteController,
                                    type: newType,
                                    categories: categoriesFor(newType),
                                    selectedCategory: newCategory,
                                    onTypeChanged: (value) {
                                      setState(() {
                                        newType = value;
                                        final list = categoriesFor(value);
                                        newCategory = list.isNotEmpty ? list.first.name : null;
                                      });
                                    },
                                    onCategoryChanged: (value) => setState(() => newCategory = value),
                                    onSubmit: _addEntry,
                                    onManageCategories: _manageCategories,
                                    onManageBudgets: _manageBudgets,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Analytics',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: analyticsCardWidth,
                                  child: _AnalyticsCard(
                                    title: 'Spending Breakdown',
                                    subtitle: 'Category share for this month',
                                    child: _CategoryAnalytics(
                                      slices: categorySlices,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 18),
                                SizedBox(
                                  width: analyticsCardWidth,
                                  child: _AnalyticsCard(
                                    title: 'Spending Over Time',
                                    subtitle: 'Daily expense totals in the current month',
                                    child: _LineChart(points: trendPoints),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.categories,
    required this.selectedCategory,
    required this.summary,
    required this.onSelectCategory,
    required this.onManageCategories,
  });

  final List<CategoryDefinition> categories;
  final CategoryDefinition? selectedCategory;
  final ExpenseSummary summary;
  final ValueChanged<CategoryDefinition?> onSelectCategory;
  final Future<void> Function() onManageCategories;

  @override
  Widget build(BuildContext context) {
    final expenseCategories = categories.where((c) => c.type == EntryType.expense).toList();
    final incomeCategories = categories.where((c) => c.type == EntryType.income).toList();

    return Container(
      width: 240,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.black, LuxeColors.panel, LuxeColors.panelSoft],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(right: BorderSide(color: LuxeColors.line)),
      ),
      padding: const EdgeInsets.all(20),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Categories', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: LuxeColors.orangeSoft)),
              const SizedBox(height: 10),
              _SidebarButton(
                selected: selectedCategory == null,
                label: 'All Categories',
                onTap: () => onSelectCategory(null),
              ),
              const SizedBox(height: 12),
              const _SidebarGroupTitle('EXPENSES'),
              ...expenseCategories.map(
                (category) => _SidebarButton(
                  selected: selectedCategory?.id == category.id,
                  label: category.name,
                  onTap: () => onSelectCategory(category),
                ),
              ),
              const SizedBox(height: 12),
              const _SidebarGroupTitle('INCOME'),
              ...incomeCategories.map(
                (category) => _SidebarButton(
                  selected: selectedCategory?.id == category.id,
                  label: category.name,
                  onTap: () => onSelectCategory(category),
                ),
              ),
              const SizedBox(height: 28),
              _Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Portfolio', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: LuxeColors.gold)),
                    const SizedBox(height: 8),
                    Text(formatCurrency(summary.balance), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('Net balance in current view', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: LuxeColors.textSoft)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: LuxeColors.orange,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: onManageCategories,
                child: const Text('Manage Categories'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarGroupTitle extends StatelessWidget {
  const _SidebarGroupTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: LuxeColors.textSoft,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? LuxeColors.orange.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(child: Text(label)),
              if (selected) const Icon(Icons.check_circle, color: LuxeColors.gold, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.selectedMonth,
    required this.summary,
    required this.insights,
    required this.onMonthChanged,
  });

  final DateTime selectedMonth;
  final ExpenseSummary summary;
  final DashboardInsights insights;
  final ValueChanged<DateTime> onMonthChanged;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('LUXE BUDGET', style: Theme.of(context).textTheme.labelMedium?.copyWith(letterSpacing: 2, color: LuxeColors.gold, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('Monthly Snapshot', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Track spending, income, and balance for ${monthLabel(selectedMonth)}.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: LuxeColors.textSoft)),
                ],
              ),
              const Spacer(),
              FilledButton.tonal(
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedMonth,
                    firstDate: DateTime(now.year - 3),
                    lastDate: DateTime(now.year + 3),
                  );
                  if (picked != null) {
                    onMonthChanged(DateTime(picked.year, picked.month));
                  }
                },
                child: Text(monthLabel(selectedMonth)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _MetricCard(title: 'Income', value: summary.income, color: LuxeColors.orangeSoft)),
              const SizedBox(width: 16),
              Expanded(child: _MetricCard(title: 'Expenses', value: summary.expenses, color: LuxeColors.ember)),
              const SizedBox(width: 16),
              Expanded(child: _MetricCard(title: 'Balance', value: summary.balance, color: summary.balance >= 0 ? LuxeColors.gold : LuxeColors.orange)),
            ],
          ),
          const SizedBox(height: 16),
          _InsightsRow(insights: insights),
        ],
      ),
    );
  }
}

class _InsightsRow extends StatelessWidget {
  const _InsightsRow({required this.insights});

  final DashboardInsights insights;

  @override
  Widget build(BuildContext context) {
    final biggest = insights.biggestExpense;
    final topCategory = insights.topCategory;
    return Row(
      children: [
        Expanded(
          child: _InsightTile(
            title: 'Biggest Expense',
            value: biggest == null ? 'None yet' : formatCurrency(biggest.amount),
            subtitle: biggest?.title ?? 'No expenses this month',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _InsightTile(
            title: 'Top Category',
            value: topCategory == null ? 'None yet' : topCategory.key,
            subtitle: topCategory == null ? 'No category spend' : formatCurrency(topCategory.value),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _InsightTile(
            title: 'Daily Average',
            value: formatCurrency(insights.averageDailySpend),
            subtitle: 'Average spend so far',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _InsightTile(
            title: 'Safe To Spend',
            value: formatCurrency(insights.safeToSpend),
            subtitle: 'Per remaining day',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _InsightTile(
            title: 'Projected Balance',
            value: formatCurrency(insights.projectedMonthEnd),
            subtitle: 'At month end',
          ),
        ),
      ],
    );
  }
}

class _InsightTile extends StatelessWidget {
  const _InsightTile({
    required this.title,
    required this.value,
    required this.subtitle,
  });

  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: LuxeColors.gold.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: LuxeColors.textSoft)),
          const SizedBox(height: 8),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: LuxeColors.textSoft)),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.color,
  });

  final String title;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.black.withValues(alpha: 0.34), LuxeColors.panelSoft],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.24)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.10), blurRadius: 18, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: LuxeColors.textSoft)),
          const SizedBox(height: 10),
          Text(formatCurrency(value), style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: color, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _FiltersRow extends StatelessWidget {
  const _FiltersRow({
    required this.controller,
    required this.typeFilter,
    required this.onTypeFilterChanged,
    required this.onSearchChanged,
    required this.onExport,
    required this.onImport,
    required this.onManageRecurring,
    required this.onApplyRecurring,
    required this.statusMessage,
  });

  final TextEditingController controller;
  final EntryTypeFilter typeFilter;
  final ValueChanged<EntryTypeFilter> onTypeFilterChanged;
  final ValueChanged<String> onSearchChanged;
  final Future<void> Function() onExport;
  final Future<void> Function() onImport;
  final Future<void> Function() onManageRecurring;
  final Future<void> Function() onApplyRecurring;
  final String statusMessage;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Row(
        children: [
          SizedBox(
            width: 320,
            child: TextField(
              controller: controller,
              onChanged: onSearchChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search title or note',
              ),
            ),
          ),
          const SizedBox(width: 16),
          SegmentedButton<EntryTypeFilter>(
            segments: const [
              ButtonSegment(value: EntryTypeFilter.all, label: Text('All')),
              ButtonSegment(value: EntryTypeFilter.expense, label: Text('Expense')),
              ButtonSegment(value: EntryTypeFilter.income, label: Text('Income')),
            ],
            selected: {typeFilter},
            onSelectionChanged: (selection) => onTypeFilterChanged(selection.first),
          ),
          const Spacer(),
          if (statusMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(statusMessage, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: LuxeColors.gold)),
            ),
          OutlinedButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Import CSV'),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: onManageRecurring,
            icon: const Icon(Icons.repeat_rounded),
            label: const Text('Recurring'),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: onApplyRecurring,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Apply'),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: onExport,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Export CSV'),
          ),
        ],
      ),
    );
  }
}

class _BudgetOverview extends StatelessWidget {
  const _BudgetOverview({
    required this.budgets,
    required this.spending,
    required this.onManageBudgets,
  });

  final Map<String, double> budgets;
  final Map<String, double> spending;
  final Future<void> Function() onManageBudgets;

  @override
  Widget build(BuildContext context) {
    final activeBudgets = budgets.entries.where((entry) => entry.value > 0).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final totalBudget = activeBudgets.fold<double>(0, (sum, entry) => sum + entry.value);
    final totalSpend = activeBudgets.fold<double>(0, (sum, entry) => sum + (spending[entry.key] ?? 0));

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Budgets', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    activeBudgets.isEmpty
                        ? 'Set monthly category limits to track overspending.'
                        : '${formatCurrency(totalSpend)} used of ${formatCurrency(totalBudget)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: LuxeColors.textSoft),
                  ),
                ],
              ),
              const Spacer(),
              FilledButton.tonal(
                onPressed: onManageBudgets,
                child: const Text('Manage Budgets'),
              ),
            ],
          ),
          if (activeBudgets.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final budget in activeBudgets.take(6))
                  _BudgetChip(
                    category: budget.key,
                    budget: budget.value,
                    spent: spending[budget.key] ?? 0,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BudgetChip extends StatelessWidget {
  const _BudgetChip({
    required this.category,
    required this.budget,
    required this.spent,
  });

  final String category;
  final double budget;
  final double spent;

  @override
  Widget build(BuildContext context) {
    final progress = budget <= 0 ? 0.0 : (spent / budget).clamp(0.0, 1.0);
    final over = spent > budget;
    return Container(
      width: 285,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: (over ? LuxeColors.ember : LuxeColors.gold).withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(category, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
              Text('${(progress * 100).round()}%', style: TextStyle(color: over ? LuxeColors.ember : LuxeColors.gold, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation(over ? LuxeColors.ember : LuxeColors.orange),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${formatCurrency(spent)} / ${formatCurrency(budget)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: LuxeColors.textSoft),
          ),
        ],
      ),
    );
  }
}

class _TransactionTable extends StatelessWidget {
  const _TransactionTable({
    required this.entries,
    required this.onDelete,
    required this.onEdit,
  });

  final List<ExpenseEntry> entries;
  final Future<void> Function(ExpenseEntry) onDelete;
  final Future<void> Function(ExpenseEntry) onEdit;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Transactions', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          if (entries.isEmpty)
            Container(
              height: 420,
              alignment: Alignment.center,
              child: Text('No entries match this view.', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: LuxeColors.textSoft)),
            )
          else
            Table(
              columnWidths: const {
                0: FixedColumnWidth(110),
                1: FixedColumnWidth(240),
                2: FixedColumnWidth(150),
                3: FixedColumnWidth(100),
                4: FixedColumnWidth(120),
                5: FixedColumnWidth(160),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                _headerRow(context),
                for (final entry in entries) _dataRow(context, entry),
              ],
            ),
        ],
      ),
    );
  }

  TableRow _headerRow(BuildContext context) {
    final headers = ['Date', 'Title', 'Category', 'Type', 'Amount', 'Actions'];
    return TableRow(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [LuxeColors.orange.withValues(alpha: 0.34), LuxeColors.ember.withValues(alpha: 0.22)],
        ),
      ),
      children: headers
          .map(
            (header) => Padding(
              padding: const EdgeInsets.all(12),
              child: Text(header, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
          )
          .toList(),
    );
  }

  TableRow _dataRow(BuildContext context, ExpenseEntry entry) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return TableRow(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      children: [
        _cell(Text(dateLabel(entry.date), style: style)),
        _cell(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.title, style: style?.copyWith(fontWeight: FontWeight.w600)),
              if (entry.note.isNotEmpty)
                Text(entry.note, style: style?.copyWith(color: LuxeColors.textSoft, fontSize: 12)),
            ],
          ),
        ),
        _cell(Text(entry.category, style: style)),
        _cell(Text(entry.type.label, style: style?.copyWith(color: entry.type == EntryType.income ? LuxeColors.orangeSoft : LuxeColors.ember))),
        _cell(Text(formatCurrency(entry.amount), style: style?.copyWith(fontWeight: FontWeight.w700))),
        _cell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(onPressed: () => onEdit(entry), child: const Text('Edit')),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => onDelete(entry),
                child: const Text('Delete', style: TextStyle(color: LuxeColors.ember)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cell(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: child,
    );
  }
}

class _AddEntryCard extends StatelessWidget {
  const _AddEntryCard({
    required this.titleController,
    required this.amountController,
    required this.noteController,
    required this.type,
    required this.categories,
    required this.selectedCategory,
    required this.onTypeChanged,
    required this.onCategoryChanged,
    required this.onSubmit,
    required this.onManageCategories,
    required this.onManageBudgets,
  });

  final TextEditingController titleController;
  final TextEditingController amountController;
  final TextEditingController noteController;
  final EntryType type;
  final List<CategoryDefinition> categories;
  final String? selectedCategory;
  final ValueChanged<EntryType> onTypeChanged;
  final ValueChanged<String?> onCategoryChanged;
  final Future<void> Function() onSubmit;
  final Future<void> Function() onManageCategories;
  final Future<void> Function() onManageBudgets;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add Entry', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: 12),
          TextField(controller: amountController, decoration: const InputDecoration(labelText: 'Amount')),
          const SizedBox(height: 12),
          SegmentedButton<EntryType>(
            segments: const [
              ButtonSegment(value: EntryType.expense, label: Text('Expense')),
              ButtonSegment(value: EntryType.income, label: Text('Income')),
            ],
            selected: {type},
            onSelectionChanged: (selection) => onTypeChanged(selection.first),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: selectedCategory,
            decoration: const InputDecoration(labelText: 'Category'),
            items: categories
                .map((category) => DropdownMenuItem<String>(
                      value: category.name,
                      child: Text(category.name),
                    ))
                .toList(),
            onChanged: onCategoryChanged,
          ),
          const SizedBox(height: 12),
          TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Note')),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: LuxeColors.orange),
                  onPressed: onSubmit,
                  child: const Text('Save Entry'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: onManageCategories,
                  child: const Text('Categories'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onManageBudgets,
            icon: const Icon(Icons.savings_rounded),
            label: const Text('Budgets'),
          ),
        ],
      ),
    );
  }
}

class _AnalyticsCard extends StatelessWidget {
  const _AnalyticsCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: LuxeColors.textSoft)),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _CategoryAnalytics extends StatelessWidget {
  const _CategoryAnalytics({required this.slices});

  final List<ChartSliceData> slices;

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty) {
      return const SizedBox(
        height: 280,
        child: Center(child: Text('No expense data yet')),
      );
    }

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 280,
            child: CustomPaint(
              painter: BarChartPainter(slices: slices),
            ),
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 220,
          child: Column(
            children: [
              SizedBox(
                height: 180,
                child: CustomPaint(
                  painter: DonutChartPainter(slices: slices),
                ),
              ),
              const SizedBox(height: 12),
              ...slices.map(
                (slice) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: slice.color, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(slice.label)),
                      Text(formatCurrency(slice.value, decimals: 0), style: const TextStyle(color: LuxeColors.textSoft)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LineChart extends StatelessWidget {
  const _LineChart({required this.points});

  final List<TrendPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const SizedBox(
        height: 280,
        child: Center(child: Text('No trend data yet')),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 280,
      child: CustomPaint(
        painter: LineChartPainter(points: points),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [LuxeColors.panelSoft.withValues(alpha: 0.98), LuxeColors.panel],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: LuxeColors.orange.withValues(alpha: 0.20)),
        boxShadow: [
          BoxShadow(color: LuxeColors.orange.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: child,
    );
  }
}

class BudgetManagerDialog extends StatefulWidget {
  const BudgetManagerDialog({
    super.key,
    required this.expenseCategories,
    required this.budgets,
    required this.spending,
  });

  final List<CategoryDefinition> expenseCategories;
  final Map<String, double> budgets;
  final Map<String, double> spending;

  @override
  State<BudgetManagerDialog> createState() => _BudgetManagerDialogState();
}

class _BudgetManagerDialogState extends State<BudgetManagerDialog> {
  late final Map<String, TextEditingController> controllers;

  @override
  void initState() {
    super.initState();
    controllers = {
      for (final category in widget.expenseCategories)
        category.name: TextEditingController(
          text: (widget.budgets[category.name] ?? 0) == 0 ? '' : (widget.budgets[category.name] ?? 0).toStringAsFixed(0),
        ),
    };
  }

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: LuxeColors.panel,
      title: const Text('Monthly Budgets'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final category in widget.expenseCategories)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(category.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(
                              'Spent ${formatCurrency(widget.spending[category.name] ?? 0)} this month',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: LuxeColors.textSoft),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: 180,
                        child: TextField(
                          controller: controllers[category.name],
                          decoration: const InputDecoration(labelText: 'Budget'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final updated = <String, double>{};
            for (final entry in controllers.entries) {
              final value = double.tryParse(entry.value.text.trim());
              if (value != null && value > 0) {
                updated[entry.key] = value;
              }
            }
            Navigator.of(context).pop(updated);
          },
          child: const Text('Save Budgets'),
        ),
      ],
    );
  }
}

class RecurringManagerDialog extends StatefulWidget {
  const RecurringManagerDialog({
    super.key,
    required this.recurringEntries,
    required this.categories,
    required this.onAdd,
    required this.onDelete,
  });

  final List<RecurringEntry> recurringEntries;
  final List<CategoryDefinition> categories;
  final void Function(RecurringEntry entry) onAdd;
  final void Function(RecurringEntry entry) onDelete;

  @override
  State<RecurringManagerDialog> createState() => _RecurringManagerDialogState();
}

class _RecurringManagerDialogState extends State<RecurringManagerDialog> {
  final titleController = TextEditingController();
  final amountController = TextEditingController();
  final dayController = TextEditingController(text: '1');
  final noteController = TextEditingController();
  late List<RecurringEntry> localEntries;
  EntryType type = EntryType.expense;
  String? category;

  @override
  void initState() {
    super.initState();
    localEntries = [...widget.recurringEntries];
    category = categoriesForType(type).isNotEmpty ? categoriesForType(type).first.name : null;
  }

  @override
  void dispose() {
    titleController.dispose();
    amountController.dispose();
    dayController.dispose();
    noteController.dispose();
    super.dispose();
  }

  List<CategoryDefinition> categoriesForType(EntryType entryType) {
    return widget.categories.where((item) => item.type == entryType).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Widget build(BuildContext context) {
    final availableCategories = categoriesForType(type);
    return AlertDialog(
      backgroundColor: LuxeColors.panel,
      title: const Text('Recurring Entries'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (localEntries.isEmpty)
                Text('No recurring entries yet.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: LuxeColors.textSoft))
              else
                for (final entry in localEntries)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('${entry.title} • ${formatCurrency(entry.amount)} • Day ${entry.dayOfMonth} • ${entry.category}'),
                        ),
                        TextButton(
                          onPressed: () {
                            widget.onDelete(entry);
                            setState(() => localEntries.removeWhere((item) => item.id == entry.id));
                          },
                          child: const Text('Delete', style: TextStyle(color: LuxeColors.ember)),
                        ),
                      ],
                    ),
                  ),
              const Divider(height: 28),
              Text('Add Recurring Entry', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Title'))),
                  const SizedBox(width: 12),
                  SizedBox(width: 140, child: TextField(controller: amountController, decoration: const InputDecoration(labelText: 'Amount'), keyboardType: TextInputType.number)),
                  const SizedBox(width: 12),
                  SizedBox(width: 120, child: TextField(controller: dayController, decoration: const InputDecoration(labelText: 'Day'), keyboardType: TextInputType.number)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SegmentedButton<EntryType>(
                    segments: const [
                      ButtonSegment(value: EntryType.expense, label: Text('Expense')),
                      ButtonSegment(value: EntryType.income, label: Text('Income')),
                    ],
                    selected: {type},
                    onSelectionChanged: (selection) {
                      setState(() {
                        type = selection.first;
                        final list = categoriesForType(type);
                        category = list.isEmpty ? null : list.first.name;
                      });
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: category,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: availableCategories.map((item) => DropdownMenuItem(value: item.name, child: Text(item.name))).toList(),
                      onChanged: (value) => setState(() => category = value),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Note')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        FilledButton(
          onPressed: () {
            final amount = double.tryParse(amountController.text.trim());
            final day = int.tryParse(dayController.text.trim());
            if (titleController.text.trim().isEmpty || amount == null || day == null || category == null) return;
            final entry = RecurringEntry(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              title: titleController.text.trim(),
              amount: amount,
              dayOfMonth: day.clamp(1, 31),
              type: type,
              category: category!,
              note: noteController.text.trim(),
            );
            widget.onAdd(entry);
            setState(() {
              localEntries.add(entry);
              titleController.clear();
              amountController.clear();
              noteController.clear();
            });
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class ImportCsvDialog extends StatefulWidget {
  const ImportCsvDialog({super.key});

  @override
  State<ImportCsvDialog> createState() => _ImportCsvDialogState();
}

class _ImportCsvDialogState extends State<ImportCsvDialog> {
  final pathController = TextEditingController();

  @override
  void dispose() {
    pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: LuxeColors.panel,
      title: const Text('Import CSV'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paste a CSV path. Expected columns: Date, Title, Type, Category, Amount, Note.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: LuxeColors.textSoft),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pathController,
              decoration: const InputDecoration(labelText: 'CSV file path'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(pathController.text), child: const Text('Import')),
      ],
    );
  }
}

class EditEntryDialog extends StatefulWidget {
  const EditEntryDialog({
    super.key,
    required this.entry,
    required this.categories,
  });

  final ExpenseEntry entry;
  final List<CategoryDefinition> categories;

  @override
  State<EditEntryDialog> createState() => _EditEntryDialogState();
}

class _EditEntryDialogState extends State<EditEntryDialog> {
  late final TextEditingController titleController;
  late final TextEditingController amountController;
  late final TextEditingController noteController;
  late EntryType type;
  late String category;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.entry.title);
    amountController = TextEditingController(text: widget.entry.amount.toString());
    noteController = TextEditingController(text: widget.entry.note);
    type = widget.entry.type;
    category = widget.entry.category;
  }

  @override
  void dispose() {
    titleController.dispose();
    amountController.dispose();
    noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: LuxeColors.panel,
      title: const Text('Edit Entry'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleController, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 12),
            TextField(controller: amountController, decoration: const InputDecoration(labelText: 'Amount')),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: widget.categories
                  .map((item) => DropdownMenuItem(value: item.name, child: Text(item.name)))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => category = value);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Note')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final amount = double.tryParse(amountController.text.trim());
            if (amount == null) return;
            Navigator.of(context).pop(
              ExpenseEntry(
                id: widget.entry.id,
                title: titleController.text.trim(),
                amount: amount,
                date: widget.entry.date,
                type: type,
                category: category,
                note: noteController.text.trim(),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class CategoryManagerDialog extends StatefulWidget {
  const CategoryManagerDialog({
    super.key,
    required this.categories,
    required this.onAdd,
    required this.onRename,
    required this.onDelete,
  });

  final List<CategoryDefinition> categories;
  final void Function(String name, EntryType type) onAdd;
  final void Function(CategoryDefinition category, String newName) onRename;
  final void Function(CategoryDefinition category) onDelete;

  @override
  State<CategoryManagerDialog> createState() => _CategoryManagerDialogState();
}

class _CategoryManagerDialogState extends State<CategoryManagerDialog> {
  final addController = TextEditingController();
  EntryType addType = EntryType.expense;

  @override
  void dispose() {
    addController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expenses = widget.categories.where((c) => c.type == EntryType.expense).toList();
    final income = widget.categories.where((c) => c.type == EntryType.income).toList();

    return AlertDialog(
      backgroundColor: LuxeColors.panel,
      title: const Text('Manage Categories'),
      content: SizedBox(
        width: 720,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _CategoryColumn(title: 'Expense', categories: expenses, onRename: widget.onRename, onDelete: widget.onDelete)),
                const SizedBox(width: 16),
                Expanded(child: _CategoryColumn(title: 'Income', categories: income, onRename: widget.onRename, onDelete: widget.onDelete)),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: addController,
              decoration: const InputDecoration(labelText: 'New category'),
            ),
            const SizedBox(height: 12),
            SegmentedButton<EntryType>(
              segments: const [
                ButtonSegment(value: EntryType.expense, label: Text('Expense')),
                ButtonSegment(value: EntryType.income, label: Text('Income')),
              ],
              selected: {addType},
              onSelectionChanged: (selection) => setState(() => addType = selection.first),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
        FilledButton(
          onPressed: () {
            widget.onAdd(addController.text, addType);
            addController.clear();
            setState(() {});
          },
          child: const Text('Add Category'),
        ),
      ],
    );
  }
}

class _CategoryColumn extends StatelessWidget {
  const _CategoryColumn({
    required this.title,
    required this.categories,
    required this.onRename,
    required this.onDelete,
  });

  final String title;
  final List<CategoryDefinition> categories;
  final void Function(CategoryDefinition category, String newName) onRename;
  final void Function(CategoryDefinition category) onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          for (final category in categories)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(child: Text(category.name)),
                  TextButton(
                    onPressed: () async {
                      final controller = TextEditingController(text: category.name);
                      final name = await showDialog<String>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: LuxeColors.panel,
                          title: const Text('Rename Category'),
                          content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Name')),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                            FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Save')),
                          ],
                        ),
                      );
                      if (name != null) {
                        onRename(category, name);
                      }
                    },
                    child: const Text('Edit'),
                  ),
                  TextButton(
                    onPressed: () => onDelete(category),
                    child: const Text('Delete', style: TextStyle(color: LuxeColors.ember)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class BarChartPainter extends CustomPainter {
  BarChartPainter({required this.slices});

  final List<ChartSliceData> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final maxValue = slices.map((e) => e.value).fold<double>(0, math.max);
    const left = 90.0;
    const rightPadding = 16.0;
    const top = 8.0;
    const rowHeight = 34.0;
    const gap = 12.0;
    final paint = Paint()..style = PaintingStyle.fill;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (var i = 0; i < slices.length; i++) {
      final slice = slices[i];
      final y = top + i * (rowHeight + gap);
      final availableWidth = size.width - left - rightPadding;
      final width = maxValue == 0 ? 0.0 : (slice.value / maxValue) * availableWidth;

      paint.shader = LinearGradient(
        colors: [slice.color, slice.color.withValues(alpha: 0.55)],
      ).createShader(Rect.fromLTWH(left, y, width, rowHeight));

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, y, width, rowHeight),
        const Radius.circular(10),
      );
      canvas.drawRRect(rrect, paint);

      textPainter.text = TextSpan(
        text: slice.label,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
      );
      textPainter.layout(maxWidth: left - 10);
      textPainter.paint(canvas, Offset(0, y + 8));

      textPainter.text = TextSpan(
        text: formatCurrency(slice.value, decimals: 0),
        style: const TextStyle(color: LuxeColors.textSoft, fontSize: 12, fontWeight: FontWeight.w600),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(left + width + 8, y + 8));
    }
  }

  @override
  bool shouldRepaint(covariant BarChartPainter oldDelegate) => oldDelegate.slices != slices;
}

class DonutChartPainter extends CustomPainter {
  DonutChartPainter({required this.slices});

  final List<ChartSliceData> slices;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<double>(0, (sum, slice) => sum + slice.value);
    if (total == 0) return;

    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: math.min(size.width, size.height) / 2 - 10);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28
      ..strokeCap = StrokeCap.round;

    double startAngle = -math.pi / 2;
    for (final slice in slices) {
      final sweep = (slice.value / total) * math.pi * 2;
      paint.color = slice.color;
      canvas.drawArc(rect, startAngle, sweep, false, paint);
      startAngle += sweep + 0.03;
    }

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: 'Share\n${formatCurrency(total, decimals: 0)}',
      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
    );
    textPainter.textAlign = TextAlign.center;
    textPainter.layout(maxWidth: 100);
    textPainter.paint(canvas, Offset(size.width / 2 - textPainter.width / 2, size.height / 2 - textPainter.height / 2));
  }

  @override
  bool shouldRepaint(covariant DonutChartPainter oldDelegate) => oldDelegate.slices != slices;
}

class LineChartPainter extends CustomPainter {
  LineChartPainter({required this.points});

  final List<TrendPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    const padding = EdgeInsets.fromLTRB(56, 20, 20, 40);
    final chartWidth = size.width - padding.left - padding.right;
    final chartHeight = size.height - padding.top - padding.bottom;
    if (chartWidth <= 0 || chartHeight <= 0) return;

    final rawMaxY = points.map((e) => e.amount).fold<double>(0, math.max);
    final maxY = _niceCeiling(rawMaxY <= 0 ? 100 : rawMaxY);
    final minX = points.first.date.millisecondsSinceEpoch.toDouble();
    final maxX = points.last.date.millisecondsSinceEpoch.toDouble();
    final xRange = (maxX - minX).clamp(1, double.infinity);
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    Offset mapPoint(TrendPoint point) {
      final x = padding.left + ((point.date.millisecondsSinceEpoch - minX) / xRange) * chartWidth;
      final y = padding.top + chartHeight - ((point.amount / maxY) * chartHeight);
      return Offset(x, y);
    }

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    final axisLabelStyle = const TextStyle(
      color: LuxeColors.textSoft,
      fontSize: 11,
      fontWeight: FontWeight.w500,
    );

    for (int i = 0; i < 4; i++) {
      final ratio = i / 3;
      final y = padding.top + (chartHeight * ratio);
      canvas.drawLine(Offset(padding.left, y), Offset(size.width - padding.right, y), gridPaint);

      final value = maxY * (1 - ratio);
      textPainter.text = TextSpan(
        text: compactCurrency(value),
        style: axisLabelStyle,
      );
      textPainter.layout(maxWidth: padding.left - 10);
      textPainter.paint(canvas, Offset(padding.left - textPainter.width - 10, y - textPainter.height / 2));
    }

    final baselineY = size.height - padding.bottom;
    final zeroLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(padding.left, baselineY), Offset(size.width - padding.right, baselineY), zeroLinePaint);

    final pointsOffsets = points.map(mapPoint).toList();
    final barWidth = math.max(4.0, chartWidth / (points.length * 1.9));
    final barPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          LuxeColors.orange.withValues(alpha: 0.30),
          LuxeColors.orangeSoft.withValues(alpha: 0.08),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(padding.left, padding.top, chartWidth, chartHeight));

    for (int i = 0; i < points.length; i++) {
      final offset = pointsOffsets[i];
      final rect = Rect.fromLTWH(offset.dx - (barWidth / 2), offset.dy, barWidth, baselineY - offset.dy);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        barPaint,
      );
    }

    final path = Path();
    final areaPath = Path();
    for (int i = 0; i < pointsOffsets.length; i++) {
      final offset = pointsOffsets[i];
      if (i == 0) {
        path.moveTo(offset.dx, offset.dy);
        areaPath.moveTo(offset.dx, baselineY);
        areaPath.lineTo(offset.dx, offset.dy);
      } else {
        final previous = pointsOffsets[i - 1];
        final controlX = (previous.dx + offset.dx) / 2;
        path.quadraticBezierTo(controlX, previous.dy, offset.dx, offset.dy);
        areaPath.quadraticBezierTo(controlX, previous.dy, offset.dx, offset.dy);
      }
    }
    final last = pointsOffsets.last;
    areaPath.lineTo(last.dx, baselineY);
    areaPath.close();

    final areaPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          LuxeColors.gold.withValues(alpha: 0.20),
          LuxeColors.orange.withValues(alpha: 0.10),
          Colors.transparent,
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(areaPath, areaPaint);

    final linePaint = Paint()
      ..shader = LinearGradient(
        colors: [LuxeColors.gold, LuxeColors.orangeSoft],
      ).createShader(Rect.fromLTWH(padding.left, padding.top, chartWidth, chartHeight))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = LuxeColors.orangeSoft;
    final haloPaint = Paint()..color = LuxeColors.gold.withValues(alpha: 0.16);
    for (int i = 0; i < points.length; i++) {
      if (points[i].amount <= 0) continue;
      final offset = pointsOffsets[i];
      canvas.drawCircle(offset, 8, haloPaint);
      canvas.drawCircle(offset, 4.5, dotPaint);
    }

    final labelIndexes = <int>{
      0,
      points.length > 1 ? points.length ~/ 4 : 0,
      points.length > 1 ? points.length ~/ 2 : 0,
      points.length > 1 ? (points.length * 3) ~/ 4 : 0,
      points.length - 1,
    }.toList()
      ..sort();

    for (final index in labelIndexes) {
      final point = points[index];
      final offset = pointsOffsets[index];
      textPainter.text = TextSpan(
        text: shortDayLabel(point.date),
        style: axisLabelStyle,
      );
      textPainter.layout();
      final labelX = (offset.dx - textPainter.width / 2).clamp(padding.left, size.width - padding.right - textPainter.width);
      textPainter.paint(canvas, Offset(labelX, baselineY + 10));
    }

    final peakIndex = points.indexWhere((point) => point.amount == rawMaxY);
    if (peakIndex >= 0 && rawMaxY > 0) {
      final peakOffset = pointsOffsets[peakIndex];
      final peakLabel = compactCurrency(rawMaxY);
      textPainter.text = TextSpan(
        text: peakLabel,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      );
      textPainter.layout();
      final labelWidth = textPainter.width + 16;
      final bubbleRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          (peakOffset.dx - labelWidth / 2).clamp(padding.left, size.width - padding.right - labelWidth),
          math.max(2, peakOffset.dy - 34),
          labelWidth,
          24,
        ),
        const Radius.circular(12),
      );
      final bubblePaint = Paint()..color = LuxeColors.panelSoft.withValues(alpha: 0.95);
      canvas.drawRRect(bubbleRect, bubblePaint);
      canvas.drawRRect(
        bubbleRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = LuxeColors.gold.withValues(alpha: 0.24),
      );
      textPainter.paint(
        canvas,
        Offset(bubbleRect.left + 8, bubbleRect.top + 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant LineChartPainter oldDelegate) => oldDelegate.points != points;
}

double _niceCeiling(double value) {
  if (value <= 0) return 100;
  final magnitude = math.pow(10, (math.log(value) / math.ln10).floor()).toDouble();
  final normalized = value / magnitude;
  final niceNormalized = normalized <= 1
      ? 1
      : normalized <= 2
          ? 2
          : normalized <= 5
              ? 5
              : 10;
  return niceNormalized * magnitude;
}

String monthLabel(DateTime date) {
  const months = [
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
  return '${months[date.month - 1]} ${date.year}';
}

String dateLabel(DateTime date) {
  if (!Platform.isWindows) {
    return '${date.month}/${date.day}/${date.year}';
  }
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

String shortDayLabel(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final day = date.day.toString().padLeft(2, '0');
  return Platform.isWindows ? '$day ${months[date.month - 1]}' : '${months[date.month - 1]} $day';
}

String compactCurrency(double value) {
  final symbol = Platform.isWindows ? '₹' : r'$';
  if (value >= 1000) {
    final short = value / 1000;
    return short == short.roundToDouble()
        ? '$symbol${short.toStringAsFixed(0)}k'
        : '$symbol${short.toStringAsFixed(1)}k';
  }
  return value == value.roundToDouble()
      ? '$symbol${value.toStringAsFixed(0)}'
      : '$symbol${value.toStringAsFixed(1)}';
}

String formatCurrency(double value, {int decimals = 2}) {
  final symbol = Platform.isWindows ? '₹' : r'$';
  return '$symbol${value.toStringAsFixed(decimals)}';
}

List<String> parseCsvLine(String line) {
  final values = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;

  for (int i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
        buffer.write('"');
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (char == ',' && !inQuotes) {
      values.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }

  values.add(buffer.toString());
  return values;
}

DateTime? parseFlexibleDate(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  final slashParts = trimmed.split('/');
  if (slashParts.length == 3) {
    final day = int.tryParse(slashParts[0]);
    final month = int.tryParse(slashParts[1]);
    final year = int.tryParse(slashParts[2]);
    if (day != null && month != null && year != null) {
      return DateTime(year, month, day);
    }
  }

  final dashParts = trimmed.split('-');
  if (dashParts.length == 3) {
    final yearFirst = int.tryParse(dashParts[0]);
    final month = int.tryParse(dashParts[1]);
    final day = int.tryParse(dashParts[2]);
    if (yearFirst != null && month != null && day != null && dashParts[0].length == 4) {
      return DateTime(yearFirst, month, day);
    }
  }

  return DateTime.tryParse(trimmed);
}
