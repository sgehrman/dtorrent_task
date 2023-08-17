import 'dart:developer';
import 'dart:io';
import 'dart:math';

import 'package:dtorrent_task/src/stream/torrent_stream.dart';
import 'package:http/http.dart';
import 'package:mime/mime.dart';

import 'package:dtorrent_task/dtorrent_task.dart';

class Range {
  int? start;
  int? end;
  Range(this.start, this.end);
}

class RangeParser {
  final ranges = <Range>[];
  String type = 'bytes';

  RangeParser(String rangeString, int fileLength) {
    type = rangeString.split('=')[0];
    var rangesStr = rangeString.split('=')[1];
    var parseRanges = rangesStr.split(',').map((r) => r.trim());

    for (var range in parseRanges) {
      var tmp = range.split('-');
      var start = int.tryParse(tmp[0]);
      var end = int.tryParse(tmp[1]);
      var tmpRange = Range(start ?? 0, end ?? fileLength);
      ranges.add(tmpRange);
    }
  }
}

Stream<T> streamDelayer<T>(Stream<T> inputStream, Duration delay) async* {
  await for (final val in inputStream) {
    yield val;
    await Future.delayed(delay);
  }
}

class StreamingServer {
  DownloadFileManager _fileManager;
  HttpServer? _server;
  TorrentStream _torrentStream;

  StreamingServer(
    this._fileManager,
    this._torrentStream,
  );

  int getPiece(int position) {
    var pieceIndex = position ~/ _fileManager.metainfo.pieceLength;
    return pieceIndex;
  }

  Future<void> requestProcessor(HttpRequest request) async {
    var file = await _fileManager.metainfo.files
        .firstWhere((element) => element.name.contains('mp4'));
    var range = request.headers['range'];
    RangeParser? ranges;
    if (range != null) {
      ranges = RangeParser(range[0], file.length);
    }

    request.response.headers.add('Accept-Ranges', 'bytes');
    request.response.headers.add('Connection', 'keep-alive');
    request.response.headers.add('Keep-Alive', 'timeout=5');
    request.response.headers.add('transferMode.dlna.org', 'Streaming');
    request.response.headers.add('contentFeatures.dlna.org',
        'DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000');
    var mime = lookupMimeType(file.name);
    if (mime != null) {
      request.response.headers.contentType = ContentType.parse(mime);
    }

    Stream<List<int>>? bytes;
    if (range == null) {
      request.response.headers.contentLength = file.length;
      if (request.method == 'HEAD') return request.response.close();
      bytes = _torrentStream.createStream(
          filePosition: 0, endPosition: file.length, fileName: file.name);
    } else if (ranges != null &&
        ranges.ranges.isNotEmpty &&
        ranges.ranges[0].start != null) {
      request.response.statusCode = 206;
      request.response.headers.contentLength =
          ranges.ranges[0].end! - ranges.ranges[0].start!;
      request.response.headers.add('Content-Range',
          'bytes ${ranges.ranges[0].start!}-${ranges.ranges[0].end}/${file.length}');
      if (request.method == 'HEAD') return request.response.close();
      bytes = _torrentStream.createStream(
          filePosition: ranges.ranges.first.start ?? 0,
          endPosition: ranges.ranges.first.end ?? file.length,
          fileName: file.name);
    }
    if (bytes == null) return;
    // request.response.headers.chunkedTransferEncoding = true;
    await request.response.addStream(bytes);
    await request.response.close();
  }

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 9090);
    _server?.listen(requestProcessor);
  }

  void stop() {
    _server?.close();
  }
}
