import 'app_database.dart';

class DatabaseProvider {
  DatabaseProvider._();

  static final instance = DatabaseProvider._();
  Future<AppDatabase>? _databaseFuture;

  /// Cache the initialization Future so concurrent providers cannot open the
  /// same Drift database more than once while the first open is in flight.
  Future<AppDatabase> get database => _databaseFuture ??= openAppDatabase();
}
