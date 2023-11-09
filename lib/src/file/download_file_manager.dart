import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task/src/file/download_file_manager_events.dart';
import 'package:events_emitter2/events_emitter2.dart';
import '../peer/peer_base.dart';

import '../piece/piece.dart';
import 'download_file.dart';
import 'state_file.dart';

class DownloadFileManager with EventsEmittable<DownloadFileManagerEvent> {
  final Torrent metainfo;

  final List<DownloadFile> _files = [];

  List<DownloadFile> get files => _files;

  final List<Piece> _pieces;

  Map<Piece, List<DownloadFile>> get piece2fileMap {
    Map<Piece, List<DownloadFile>> map = {};
    for (var file in _files) {
      for (var piece in file.pieces) {
        map[piece] ??= [];
        map[piece]!.add(file);
      }
    }
    return map;
  }

  MapEntry<Piece, List<DownloadFile>>? getPieceFiles(int pieceIndex) =>
      piece2fileMap.entries
          .firstWhereOrNull((element) => element.key.index == pieceIndex);

  final StateFile _stateFile;

  /// TODO: File read caching
  DownloadFileManager(this.metainfo, this._stateFile, this._pieces);

  static Future<DownloadFileManager> createFileManager(Torrent metainfo,
      String localDirectory, StateFile stateFile, List<Piece> pieces) {
    var manager = DownloadFileManager(metainfo, stateFile, pieces);
    // manager._totalDownloaded = stateFile.downloaded;
    return manager._init(localDirectory);
  }

  Future<DownloadFileManager> _init(String directory) async {
    var lastChar = directory.substring(directory.length - 1);
    if (lastChar != Platform.pathSeparator) {
      directory = directory + Platform.pathSeparator;
    }
    _initFileMap(directory);
    return this;
  }

  Bitfield get localBitfield => _stateFile.bitfield;

  bool localHave(int index) {
    return _stateFile.bitfield.getBit(index);
  }

  bool get isAllComplete {
    return _stateFile.bitfield.piecesNum ==
        _stateFile.bitfield.completedPieces.length;
  }

  int get piecesNumber => _stateFile.bitfield.piecesNum;

  Future<bool> updateBitfield(int index, [bool have = true]) {
    return _stateFile.updateBitfield(index, have);
  }

  // Future<bool> updateBitfields(List<int> indices, [List<bool> haves]) {
  //   return _stateFile.updateBitfields(indices, haves);
  // }

  Future<bool> updateUpload(int uploaded) {
    return _stateFile.updateUploaded(uploaded);
  }

  int get downloaded => _stateFile.downloaded;

  /// This method appears to only write the buffer content to the disk, but in
  /// reality,every time the cache is written, it is considered that the [Piece]
  /// corresponding to [pieceIndex] has been completed. Therefore, it will
  /// remove the file's corresponding piece index from the _file2pieceMap. When
  /// all the pieces have been removed, a File Complete event will be triggered.
  Future<bool> flushFiles(Set<int> pieceIndices) async {
    var d = _stateFile.downloaded;
    var flushed = <String>{};
    for (var pieceIndex in pieceIndices) {
      var piece2files = getPieceFiles(pieceIndex);
      if (piece2files == null || piece2files.value.isEmpty) continue;
      piece2files.key.flushed = true;
      for (var file in piece2files.value) {
        if (flushed.add(file.filePath)) {
          await file.requestFlush();
        }
        if (file.completed) {
          //TODO: is this check enough ?
          events.emit(DownloadManagerFileCompleted(file.filePath));
        }
      }
    }

    var msg =
        'downloaded：${d / (1024 * 1024)} mb , Progress ${((d / metainfo.length) * 10000).toInt() / 100} %';
    log(msg, name: runtimeType.toString());
    return true;
  }

  void _initFileMap(String directory) {
    for (var i = 0; i < metainfo.files.length; i++) {
      var file = metainfo.files[i];
      var fileStart = file.offset;
      var fileEnd = file.offset + file.length;
      var startPiece = fileStart ~/ metainfo.pieceLength;
      var endPiece = fileEnd ~/ metainfo.pieceLength;
      if (fileEnd.remainder(metainfo.pieceLength) == 0) endPiece--;
      var pieces = _pieces
          .where((element) =>
              element.index >= startPiece && element.index <= endPiece)
          .toList();
      var df = DownloadFile(
          directory + file.path, file.offset, file.length, file.name, pieces);
      _files.add(df);
    }
  }

  Future<List<int>?> readFile(int pieceIndex, int begin, int length) async {
    var tempFiles = getPieceFiles(pieceIndex);
    var ps = pieceIndex * metainfo.pieceLength + begin;
    var pe = ps + length;
    if (tempFiles == null || tempFiles.value.isEmpty) return null;
    var futures = <Future<List<int>>>[];
    for (var i = 0; i < tempFiles.value.length; i++) {
      var tempFile = tempFiles.value[i];
      var re = _mapDownloadFilePosition(ps, pe, length, tempFile);
      if (re == null) continue;
      var substart = re['begin'];
      var position = re['position'];
      var subend = re['end'];
      futures.add(tempFile.requestRead(position, subend - substart));
    }
    var blocks = await Future.wait(futures);
    var block = blocks.fold<List<int>>(<int>[], (previousValue, element) {
      previousValue.addAll(element);
      return previousValue;
    });
    events.emit(SubPieceReadCompleted(pieceIndex, begin, block));

    return block;
  }

  ///
  // Writes the content of a Sub Piece to the file. After completion, a sub piece complete event will be sent.
  /// If it fails, a sub piece failed event will be sent.
  ///
  /// The Sub Piece is from the Piece corresponding to [pieceIndex], and the content is [block] starting from [begin].
  /// This class does not validate if the written Sub Piece is a duplicate; it simply overwrites the previous content.
  void writeFile(int pieceIndex, int begin, List<int> block) {
    var tempFiles = getPieceFiles(pieceIndex);
    var ps = pieceIndex * metainfo.pieceLength + begin;
    var blockSize = block.length;
    var pe = ps + blockSize;
    if (tempFiles == null || tempFiles.value.isEmpty) return;
    var futures = <Future<bool>>[];
    for (var i = 0; i < tempFiles.value.length; i++) {
      var tempFile = tempFiles.value[i];
      var re = _mapDownloadFilePosition(ps, pe, blockSize, tempFile);
      if (re == null) continue;
      var substart = re['begin'];
      var position = re['position'];
      var subend = re['end'];
      futures.add(tempFile.requestWrite(position, block, substart, subend));
    }
    Stream.fromFutures(futures).fold<bool>(true, (p, a) {
      return p && a;
    }).then((result) {
      if (result) {
        events.emit(SubPieceWriteCompleted(pieceIndex, begin, blockSize));
      } else {
        events.emit(SubPieceWriteFailed(pieceIndex, begin, blockSize));
      }
    });
    return;
  }

  Map? _mapDownloadFilePosition(
      int pieceStart, int pieceEnd, int length, DownloadFile tempFile) {
    var fs = tempFile.offset;
    var fe = fs + tempFile.length;
    if (pieceEnd < fs || pieceStart > fe) return null;
    var position = 0;
    var substart = 0;
    if (fs <= pieceStart) {
      position = pieceStart - fs;
      substart = 0;
    } else {
      position = 0;
      substart = fs - pieceStart;
    }
    var subend = substart;
    if (fe >= pieceEnd) {
      subend = length;
    } else {
      subend = fe - pieceStart;
    }
    return {'position': position, 'begin': substart, 'end': subend};
  }

  Future close() async {
    events.dispose();
    await _stateFile.close();
    for (var i = 0; i < _files.length; i++) {
      var file = _files.elementAt(i);
      await file.close();
    }
  }

  Future delete() async {
    await _stateFile.delete();
    for (var i = 0; i < _files.length; i++) {
      var file = _files.elementAt(i);
      await file.delete();
    }
  }
}
