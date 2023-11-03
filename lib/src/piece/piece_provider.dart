import 'piece.dart';

abstract class PieceProvider {
  // Piece getPiece(int index);

  Piece? operator [](int index);

  int get length;
  Iterable<Piece> get downloadingPieces;
  final List<Piece> _pieces = [];
  List<Piece> get pieces => _pieces;
}
