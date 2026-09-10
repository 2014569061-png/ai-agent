import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<QueryExecutor> createDatabaseExecutor() async {
  final directory = await getApplicationDocumentsDirectory();
  final file = File(p.join(directory.path, 'mobile_agent.sqlite'));
  return NativeDatabase.createInBackground(
    file,
    // 这些 PRAGMA 必须**逐连接**设置，不能只在迁移里设一次：
    //   · journal_mode / foreign_keys / synchronous 都是 per-connection 状态；
    //   · createInBackground 会在后台 isolate 里另开连接，setup 会对每个连接执行。
    setup: (db) {
      // WAL：写入 run_events / log_records 与 UI 读取会话不再抢同一把锁，
      // 流式输出的高频写入不会阻塞读。
      db.execute('PRAGMA journal_mode=WAL;');
      // 外键约束默认关闭。当前 schema 尚未声明任何 REFERENCES，因此打开它今天
      // 是「安全的空操作」；一旦后续为 run_events/log_records 等补上 FK，级联
      // 才会真正生效（届时可移除手写级联）。开启没有任何现有写入会失败。
      db.execute('PRAGMA foreign_keys=ON;');
      // 页缓存约 8MB（负值表示 KB 数）。
      db.execute('PRAGMA cache_size=-8000;');
      // WAL 下的推荐档：写入更快，掉电最多丢最后一个事务，对本地 Agent 足够。
      db.execute('PRAGMA synchronous=NORMAL;');
    },
  );
}
