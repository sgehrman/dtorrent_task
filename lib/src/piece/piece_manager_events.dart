abstract class PieceManagerEvent {}

class PieceCompleted implements PieceManagerEvent {
  int pieceIndex;
  PieceCompleted(
    this.pieceIndex,
  );
}
