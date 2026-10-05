import 'package:sqflite/sqflite.dart';

/// A repository-scoped handle. Existing repository transactions join the caller
/// transaction, so domain writes, guards, revision triggers and journal commit
/// together. No zone/global transaction or change to normal desktop callers.
class TransactionDatabase implements Database {
  TransactionDatabase(this.transactionHandle);
  final Transaction transactionHandle;

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action, {bool? exclusive}) =>
      action(transactionHandle);
  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) =>
      transactionHandle.execute(sql, arguments);
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) =>
      transactionHandle.rawQuery(sql, arguments);
  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) =>
      transactionHandle.rawInsert(sql, arguments);
  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) =>
      transactionHandle.rawUpdate(sql, arguments);
  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) =>
      transactionHandle.rawDelete(sql, arguments);
  @override
  Future<List<Map<String, Object?>>> query(String table, {bool? distinct,
    List<String>? columns, String? where, List<Object?>? whereArgs,
    String? groupBy, String? having, String? orderBy, int? limit, int? offset}) =>
      transactionHandle.query(table, distinct: distinct, columns: columns,
        where: where, whereArgs: whereArgs, groupBy: groupBy, having: having,
        orderBy: orderBy, limit: limit, offset: offset);
  @override
  Future<int> insert(String table, Map<String, Object?> values,
    {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) =>
      transactionHandle.insert(table, values, nullColumnHack: nullColumnHack,
        conflictAlgorithm: conflictAlgorithm);
  @override
  Future<int> update(String table, Map<String, Object?> values,
    {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) =>
      transactionHandle.update(table, values, where: where, whereArgs: whereArgs,
        conflictAlgorithm: conflictAlgorithm);
  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) =>
      transactionHandle.delete(table, where: where, whereArgs: whereArgs);
  @override
  Batch batch() => transactionHandle.batch();
  @override
  Future<void> close() => throw StateError('Scoped transaction cannot close the database');
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unsupported scoped database operation');
}
