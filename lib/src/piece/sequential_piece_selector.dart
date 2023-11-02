import 'package:collection/collection.dart';
import 'package:dtorrent_task/src/peer/peer.dart';

import 'piece.dart';
import 'piece_provider.dart';
import 'piece_selector.dart';

///
/// Sequential piece selector.
///
class SequentialPieceSelector implements PieceSelector {
  @override
  Piece? selectPiece(
      Peer peer, List<int> remoteHavePieces, PieceProvider provider,
      [bool random = false, Set<int>? suggestPieces]) {
    // Check if the current downloading piece can be used by this peer.
    var p = provider.pieces.firstWhereOrNull((piece) =>
        remoteHavePieces.contains(piece.index) &&
        !piece.isCompleted &&
        piece.haveAvailableSubPiece());
    return p;
  }
}
