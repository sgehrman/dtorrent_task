import 'piece.dart';

abstract class PieceProvider {
  // Piece getPiece(int index);

  Piece? operator [](int index);

  int get length;
  Iterable<Piece> get downloadingPieces;
  final Set<Piece> _pieces = {};
  Set<Piece> get pieces => _pieces;
}
