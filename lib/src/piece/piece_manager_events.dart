abstract class PieceManagerEvent {}

class PieceWriteCompleted implements PieceManagerEvent {
  int pieceIndex;
  PieceWriteCompleted(
    this.pieceIndex,
  );
}
