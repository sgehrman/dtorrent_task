import 'dart:collection';

import '../peer/peer.dart';
import '../utils.dart';

class Piece {
  final String hashString;

  final int byteLength;

  final int index;

  final Set<Peer> _availablePeers = <Peer>{};
  Set<Peer> get availablePeers => _availablePeers;

  late Queue<int> _subPiecesQueue;

  final Set<int> _downloadedSubPieces = <int>{};

  final Set<int> _writingSubPieces = <int>{};

  int _subPiecesCount = 0;

  bool flushed = false;

  Piece(this.hashString, this.index, this.byteLength,
      {int requestLength = DEFAULT_REQUEST_LENGTH, bool isComplete = false}) {
    if (requestLength <= 0) {
      throw Exception('Request length should bigger than zero');
    }
    if (requestLength > DEFAULT_REQUEST_LENGTH) {
      throw Exception('Request length should smaller than 16kb');
    }
    _subPiecesCount = byteLength ~/ requestLength;
    if (_subPiecesCount * requestLength != byteLength) {
      _subPiecesCount++;
    }
    _subPiecesQueue =
        Queue.from(List.generate(_subPiecesCount, (index) => index));
    if (isComplete) {
      flushed = true;
      for (var subPiece in _subPiecesQueue) {
        subPieceWriteComplete(subPiece * requestLength);
      }
    }
  }

  bool get isDownloading {
    if (subPiecesCount == 0) return false;
    if (isCompleted) return false;
    return subPiecesCount !=
        _downloadedSubPieces.length +
            _subPiecesQueue.length +
            _writingSubPieces.length;
  }

  Queue<int> get subPieceQueue => _subPiecesQueue;

  int get subPiecesCount => _subPiecesCount;

  double get completed {
    if (subPiecesCount == 0) return 0;
    return _downloadedSubPieces.length / subPiecesCount;
  }

  int get downloadedSubPiecesCount => _downloadedSubPieces.length;

  int get writingSubPiecesCount => _writingSubPieces.length;

  bool haveAvailableSubPiece() {
    if (_subPiecesCount == 0) return false;
    return _subPiecesQueue.isNotEmpty;
  }

  int get availablePeersCount => _availablePeers.length;

  int get availableSubPieceCount {
    if (_subPiecesCount == 0) return 0;
    return _subPiecesQueue.length;
  }

  bool get isCompleted {
    if (subPiecesCount == 0) return false;
    return _downloadedSubPieces.length == subPiecesCount;
  }

  ///
  /// SubPiece download completed.
  ///
  /// Put the subpiece into the _writingSubPieces queue and mark it as completed.
  /// If the subpiece has already been marked, return false; if it hasn't been marked
  /// yet, mark it as completed and return true.
  bool subPieceDownloadComplete(int begin) {
    var subindex = begin ~/ DEFAULT_REQUEST_LENGTH;
    _subPiecesQueue.remove(subindex);
    return _writingSubPieces.add(subindex);
  }

  bool subPieceWriteComplete(int begin) {
    var subindex = begin ~/ DEFAULT_REQUEST_LENGTH;
    // _subPiecesQueue.remove(subindex); // Is this possible?
    _writingSubPieces.remove(subindex);
    var re = _downloadedSubPieces.add(subindex);
    if (isCompleted) {
      clearAvailablePeer();
    }
    return re;
  }

  ///
  /// Whether the sub-piece [subIndex] is still available.
  ///
  /// When a sub-piece is popped from the stack for download or if the sub-piece has already been downloaded,
  /// the piece is considered to no longer contain that sub-piece.
  bool containsSubpiece(int subIndex) {
    return subPieceQueue.contains(subIndex);
  }

  bool containsAvailablePeer(Peer peer) {
    return _availablePeers.contains(peer);
  }

  bool removeSubpiece(int subIndex) {
    return subPieceQueue.remove(subIndex);
  }

  bool addAvailablePeer(Peer peer) {
    return _availablePeers.add(peer);
  }

  bool removeAvailablePeer(Peer peer) {
    return _availablePeers.remove(peer);
  }

  void clearAvailablePeer() {
    _availablePeers.clear();
  }

  int? popSubPiece() {
    if (subPieceQueue.isNotEmpty) return subPieceQueue.removeFirst();
    return null;
  }

  bool pushSubPiece(int subIndex) {
    if (subPieceQueue.contains(subIndex) ||
        _writingSubPieces.contains(subIndex) ||
        _downloadedSubPieces.contains(subIndex)) return false;
    subPieceQueue.addFirst(subIndex);
    return true;
  }

  int? popLastSubPiece() {
    if (subPieceQueue.isNotEmpty) return subPieceQueue.removeLast();
    return null;
  }

  bool pushSubPieceLast(int index) {
    if (subPieceQueue.contains(index) ||
        _writingSubPieces.contains(index) ||
        _downloadedSubPieces.contains(index)) return false;
    subPieceQueue.addLast(index);
    return true;
  }

  bool pushSubPieceBack(int index) {
    if (subPieceQueue.contains(index)) return false;
    _writingSubPieces.remove(index);
    _downloadedSubPieces.remove(index);
    subPieceQueue.addLast(index);
    return true;
  }

  bool _disposed = false;

  bool get isDisposed => _disposed;

  void dispose() {
    if (isDisposed) return;
    _disposed = true;
    _availablePeers.clear();
    _downloadedSubPieces.clear();
    _writingSubPieces.clear();
  }

  @override
  int get hashCode => hashString.hashCode;

  @override
  bool operator ==(other) {
    if (other is Piece) {
      return other.hashString == hashString;
    }
    return false;
  }
}
