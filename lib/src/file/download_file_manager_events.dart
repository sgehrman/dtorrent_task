abstract class DownloadFileManagerEvent {}

class SubPieceCompleted implements DownloadFileManagerEvent {
  int pieceIndex;
  int begin;
  int length;
  SubPieceCompleted(
    this.pieceIndex,
    this.begin,
    this.length,
  );
}

class SubPieceWriteFailed implements DownloadFileManagerEvent {
  int pieceIndex;
  int begin;
  int length;
  SubPieceWriteFailed(
    this.pieceIndex,
    this.begin,
    this.length,
  );
}

class SubPieceWriteCompleted implements DownloadFileManagerEvent {
  int pieceIndex;
  int begin;
  int length;
  SubPieceWriteCompleted(
    this.pieceIndex,
    this.begin,
    this.length,
  );
}

class SubPieceReadCompleted implements DownloadFileManagerEvent {
  int pieceIndex;
  int begin;
  List<int> block;
  SubPieceReadCompleted(
    this.pieceIndex,
    this.begin,
    this.block,
  );
}

class DownloadManagerFileCompleted implements DownloadFileManagerEvent {
  final String filePath;
  DownloadManagerFileCompleted(
    this.filePath,
  );
}
