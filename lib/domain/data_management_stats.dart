/// Counts only: no database rows or storage implementation reach the page.
class DataManagementStats {
  const DataManagementStats({
    required this.memoryCount,
    required this.knowledgeCount,
    required this.scheduledCount,
  });
  final int memoryCount;
  final int knowledgeCount;
  final int scheduledCount;
}
