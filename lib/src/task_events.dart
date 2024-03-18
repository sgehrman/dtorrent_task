import 'package:dtorrent_task/src/file/download_file_manager_events.dart';

abstract class TaskEvent {}

class TaskStopped implements TaskEvent {}

class TaskCompleted implements TaskEvent {}

class TaskPaused implements TaskEvent {}

class TaskResumed implements TaskEvent {}

class TaskStarted implements TaskEvent {}

class TaskFileCompleted implements TaskEvent {
  final String filePath;
  TaskFileCompleted(
    this.filePath,
  );
}

class StateFileUpdated implements DownloadFileManagerEvent, TaskEvent {}
