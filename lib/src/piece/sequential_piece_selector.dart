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
    // TODO: sort remoteHavePieces
    for (var remoteHavePiece in remoteHavePieces) {
      var p = provider.pieces[remoteHavePiece];
      if (p == null) return null;
      if (!p.isCompleted && p.haveAvailableSubPiece()) return p;
    }

    return null;
  }
}
