import 'app_database.dart';

class DatabaseProvider {
  DatabaseProvider._();

  static final instance = DatabaseProvider._();
  AppDatabase? _database;

  Future<AppDatabase> get database async => _database ??= await openAppDatabase();
}
