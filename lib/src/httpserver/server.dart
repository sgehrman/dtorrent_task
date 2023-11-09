import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task/dtorrent_task.dart';
import 'package:mime/mime.dart';

class Range {
  int start;
  int end;
  Range(this.start, this.end);

  @override
  String toString() => 'Range(start: $start, end: $end)';

  Map<String, dynamic> toMap() {
    return {
      'start': start,
      'end': end,
    };
  }

  String toJson() => json.encode(toMap());
}

class RangeParser {
  final ranges = <Range>[];
  String type = 'bytes';

  RangeParser(String rangeString, int fileLength) {
    var rangeStringList = rangeString.split('=');
    String rangesStr;
    if (rangeStringList.length > 1) {
      type = rangeStringList[0].trim();
      rangesStr = rangeStringList[1].trim();
    } else {
      rangesStr = rangeStringList[0].trim();
    }
    var parseRanges = rangesStr.split(',').map((r) => r.trim());

    for (var range in parseRanges) {
      var tmp = range.split('-');
      var start = int.tryParse(tmp[0]);
      var end = int.tryParse(tmp[1]) ?? fileLength - 1;
      var tmpRange = Range(start ?? fileLength - end, end);
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
  final DownloadFileManager _fileManager;
  HttpServer? _server;
  final TorrentStream _torrentStream;
  StreamSubscription<HttpRequest>? _streamSubscription;
  InternetAddress address = InternetAddress.anyIPv4;
  int port;
  bool running = false;

  StreamingServer(
    this._fileManager,
    this._torrentStream, {
    InternetAddress? address,
    this.port = 9090,
  }) : address = address ?? InternetAddress.anyIPv4;

  int getPiece(int position) {
    var pieceIndex = position ~/ _fileManager.metainfo.pieceLength;
    return pieceIndex;
  }

  String toPlaylistEntry(int i, TorrentFile file) {
    return '#EXTINF:-1,${file.path}\nhttp://${address.host}:$port/$i';
  }

  Map<String, dynamic> toJsonEntry(int index, TorrentFile file) {
    return {
      'name': file.name,
      'url': 'http://${address.host}:$port/$index',
      'length': file.length
    };
  }

  String toPlaylist(List<TorrentFile> files) {
    return '#EXTM3U\n${files.mapIndexed(toPlaylistEntry).join('\n')}';
  }

  Map<String, dynamic> toJson(List<TorrentFile> files) {
    return {
      'totalLength': _fileManager.metainfo.length,
      'downloaded': _fileManager.downloaded,
      // 'uploaded':_fileManager.uploaded,
      'downloadSpeed': _torrentStream.averageDownloadSpeed,
      'uploadSpeed': _torrentStream.averageUploadSpeed,
      'totalPeers': _torrentStream.allPeersNumber,
      // 'activePeers': _torrentStream.activePeersNumber,
      'files': files.mapIndexed(toJsonEntry).toList()
    };
  }

  Future<void> requestProcessor(HttpRequest request) async {
    // Allow CORS requests to specify arbitrary headers, e.g. 'Range',
    // by responding to the OPTIONS preflight request with the specified
    // origin and requested headers.
    if (request.method == 'OPTIONS' &&
        request.headers['access-control-request-headers'] != null) {
      if (request.headers['origin'] != null &&
          request.headers['origin']!.isNotEmpty) {
        request.response.headers
            .add('Access-Control-Allow-Origin', request.headers['origin']![0]);
      }
      request.response.headers
          .add('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
      if (request.response.headers['access-control-request-headers'] != null &&
          request
              .response.headers['access-control-request-headers']!.isNotEmpty) {
        request.response.headers.add('Access-Control-Allow-Headers',
            request.response.headers['access-control-request-headers']![0]);
      }
      request.response.headers.add('Access-Control-Max-Age', '1728000');

      request.response.close();
      return;
    }
    if (request.uri.path == "/.m3u") {
      var buffer = toPlaylist(_fileManager.metainfo.files).codeUnits;

      request.response.headers.contentType =
          ContentType.parse('application/x-mpegurl; charset=utf-8');
      request.response.contentLength = buffer.length;
      request.response.add(buffer);
      await request.response.close();
      return;
    }
    if (request.uri.path == "/.json") {
      JsonEncoder encoder = JsonEncoder.withIndent('  ');
      var buffer =
          encoder.convert(toJson(_fileManager.metainfo.files)).codeUnits;

      request.response.headers.contentType =
          ContentType.parse('application/json; charset=utf-8');
      request.response.contentLength = buffer.length;
      request.response.add(buffer);
      await request.response.close();
      return;
    }
    var file = _fileManager.metainfo.files
        .firstWhere((element) => element.name.contains('mp4'));
    var range = request.headers['range'];
    RangeParser? ranges;
    if (range != null) {
      ranges = RangeParser(range[0], file.length);
    }

    StreamWithLength<List<int>>? bytes;
    int startPosition = ranges?.ranges.first.start ?? 0;
    int endPosition =
        ranges != null ? ranges.ranges.first.end + 1 : file.length;
    if (startPosition >= file.length) {
      request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      request.response.close();
      return;
    }

    bytes = _torrentStream.createStream(
        filePosition: startPosition,
        endPosition: endPosition,
        fileName: file.name);
    if (request.method == 'HEAD') return request.response.close();

    if (bytes == null) return;
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
    request.response.headers.contentLength = bytes.length;
    if (ranges != null && ranges.ranges.isNotEmpty) {
      request.response.statusCode = 206;
      request.response.headers.add('Content-Range',
          'bytes ${ranges.ranges[0].start}-${ranges.ranges[0].end}/${file.length}');
    }

    await request.response.addStream(bytes.stream);
    try {
      await request.response.close();
    } catch (e) {
      print('streamed data did not finish');
    }
  }

  Future<StreamingServerStarted> start() async {
    _server = await HttpServer.bind(address, port);
    _streamSubscription = _server?.listen(requestProcessor);
    running = true;
    return StreamingServerStarted(port: port, internetAddress: address);
  }

  void stop() {
    running = false;
    _server?.close();
    _streamSubscription?.cancel();
  }
}
