import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'job_board.dart';

export '../../infrastructure/database/app_database.dart' show Conversation;
export '../task_service.dart' show DevelopmentTaskInfo;
export 'job_board.dart';

/// 任务列表与收件箱。
final jobBoardProvider = FutureProvider<JobBoard>(
    (ref) async => JobBoard(await ref.watch(databaseProvider.future)));

/// 收件箱未读数，用于入口角标。
final inboxUnreadProvider = FutureProvider<int>(
    (ref) async => (await ref.watch(jobBoardProvider.future)).unreadCount());
