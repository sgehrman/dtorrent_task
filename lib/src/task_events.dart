abstract class TaskEvent {}

class TaskStopped implements TaskEvent {}

class TaskCompleted implements TaskEvent {}

class TaskPaused implements TaskEvent {}

class TaskResumed implements TaskEvent {}

class TaskFileCompleted implements TaskEvent {
  final String filePath;
  TaskFileCompleted(
    this.filePath,
  );
}
