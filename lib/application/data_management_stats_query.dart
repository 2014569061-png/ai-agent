import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/data_management_stats.dart';
import '../infrastructure/database/app_database.dart';
import 'providers.dart';

class DataManagementStatsQuery {
  const DataManagementStatsQuery({required this.database});
  final Future<AppDatabase> Function() database;

  Future<DataManagementStats> load() async =>
      (await database()).dataManagementStats();
}

final dataManagementStatsQueryProvider = Provider<DataManagementStatsQuery>(
  (ref) => DataManagementStatsQuery(
    database: () => ref.read(databaseProvider.future),
  ),
);
