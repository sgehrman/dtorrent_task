import 'package:dtorrent_task/src/peer/protocol/peer.dart';

import 'piece.dart';
import 'piece_provider.dart';
import 'piece_selector.dart';

///
/// Sequential piece selector.
///
class SequentialPieceSelector implements PieceSelector {
  final Set<int> _priorityPieces = {};

  @override
  void setPriorityPieces(Iterable<int> pieces) {
    _priorityPieces.clear();
    _priorityPieces.addAll(pieces);
  }

  @override
  Piece? selectPiece(Peer peer, PieceProvider provider,
      [bool random = false, Set<int>? suggestPieces]) {
    // Check if the current downloading piece can be used by this peer.
    // TODO: sort remoteHavePieces

    for (var piece in _priorityPieces) {
      var p = provider.pieces[piece];
      if (p == null ||
          p.isCompleted ||
          !p.haveAvailableSubPiece() ||
          !peer.remoteCompletePieces.contains(piece)) continue;
      return p;
    }
    for (var remoteHavePiece in peer.remoteCompletePieces) {
      var p = provider.pieces[remoteHavePiece];
      if (p == null) return null;
      if (!p.isCompleted && p.haveAvailableSubPiece()) return p;
    }

    return null;
  }
}
