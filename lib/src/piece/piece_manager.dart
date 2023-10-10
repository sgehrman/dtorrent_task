import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task/src/piece/piece_manager_events.dart';
import 'package:events_emitter2/events_emitter2.dart';
import '../peer/bitfield.dart';
import 'piece.dart';
import 'piece_provider.dart';
import 'piece_selector.dart';

class PieceManager
    with EventsEmittable<PieceManagerEvent>
    implements PieceProvider {
  bool _isFirst = true;

  final Map<int, Piece> _pieces = {};
  Map<int, Piece> get pieces => _pieces;

  // final Set<int> _completedPieces = <int>{};

  final Set<int> _downloadingPieces = <int>{};
  Set<int> get downloadingPieces => _downloadingPieces;

  final PieceSelector _pieceSelector;

  PieceManager(this._pieceSelector, int piecesNumber);

  static PieceManager createPieceManager(
      PieceSelector pieceSelector, Torrent metaInfo, Bitfield bitfield) {
    var p = PieceManager(pieceSelector, metaInfo.pieces.length);
    p.initPieces(metaInfo, bitfield);
    return p;
  }

  void initPieces(Torrent metaInfo, Bitfield bitfield) {
    for (var i = 0; i < metaInfo.pieces.length; i++) {
      var byteLength = metaInfo.pieceLength;
      if (i == metaInfo.pieces.length - 1) {
        byteLength = metaInfo.lastPieceLength;
      }
      var piece = Piece(metaInfo.pieces[i], i, byteLength);
      if (!bitfield.getBit(i)) _pieces[i] = piece;
    }
  }

  /// This interface is used for FileManager callback.
  ///
  /// Only when all sub-pieces have been written, the piece is considered complete.
  ///
  /// Because if we modify the bitfield only after downloading, it will cause the remote peer
  /// to request sub-pieces that are not yet present in the file system, leading to errors in data reading.
  void processSubPieceWriteComplete(int pieceIndex, int begin, int length) {
    var piece = _pieces[pieceIndex];
    if (piece != null) {
      piece.subPieceWriteComplete(begin);
      if (piece.isCompleted) _processCompletePiece(pieceIndex);
    }
  }

  Piece? selectPiece(String remotePeerId, List<int> remoteHavePieces,
      PieceProvider provider, final Set<int>? suggestPieces) {
    // Check if the current downloading piece can be used by this peer.
    var availablePiece = <int>[];
    // Prioritize downloading Suggest Pieces.
    if (suggestPieces != null && suggestPieces.isNotEmpty) {
      for (var i = 0; i < suggestPieces.length; i++) {
        var p = _pieces[suggestPieces.elementAt(i)];
        if (p != null && p.haveAvailableSubPiece()) {
          processDownloadingPiece(p.index);
          return p;
        }
      }
    }
    var candidatePieces = remoteHavePieces;
    for (var i = 0; i < _downloadingPieces.length; i++) {
      var p = _pieces[_downloadingPieces.elementAt(i)];
      if (p == null) continue;
      if (p.containsAvailablePeer(remotePeerId) && p.haveAvailableSubPiece()) {
        availablePiece.add(p.index);
      }
    }

    // If it is possible to download a piece that is currently being downloaded,
    // prioritize downloading that piece (following the principle of multiple
    // peers downloading the same piece to complete it as soon as possible).
    if (availablePiece.isNotEmpty) {
      candidatePieces = availablePiece;
    }
    var piece = _pieceSelector.selectPiece(
        remotePeerId, candidatePieces, this, _isFirst);
    _isFirst = false;
    if (piece == null) return null;
    processDownloadingPiece(piece.index);
    return piece;
  }

  void processDownloadingPiece(int pieceIndex) {
    _downloadingPieces.add(pieceIndex);
  }

  /// After completing a piece, some processing is required:
  /// - Remove it from the _pieces list.
  /// - Remove it from the _downloadingPieces list.
  /// - Notify the listeners.
  void _processCompletePiece(int index) {
    var piece = _pieces.remove(index);
    _downloadingPieces.remove(index);
    if (piece != null) {
      piece.dispose();
      events.emit(PieceCompleted(index));
    }
  }

  bool _disposed = false;

  bool get isDisposed => _disposed;

  void dispose() {
    if (isDisposed) return;
    events.dispose();
    _disposed = true;
    _pieces.forEach((key, value) {
      value.dispose();
    });
    _pieces.clear();
    _downloadingPieces.clear();
  }

  @override
  Piece? operator [](index) {
    return _pieces[index];
  }

  // @override
  // Piece getPiece(int index) {
  //   return _pieces[index];
  // }

  @override
  int get length => _pieces.length;
}
