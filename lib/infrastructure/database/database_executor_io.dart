import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<QueryExecutor> createDatabaseExecutor() async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File(p.join(directory.path, 'mobile_agent.sqlite'));
  return NativeDatabase.createInBackground(file);
}
