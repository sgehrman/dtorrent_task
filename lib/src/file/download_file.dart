import 'dart:async';
import 'dart:developer';
import 'dart:io';

const READ = 'read';
const FLUSH = 'flush';
const WRITE = 'write';

typedef FileDownloadCompleteHandle = void Function(String filePath);

class DownloadFile {
  final String filePath;
  final String originalFileName;

  final int start;

  final int length;

  File? _file;

  RandomAccessFile? _writeAccess;

  RandomAccessFile? _readAccess;

  StreamController? _streamController;

  StreamSubscription? _streamSubscription;

  DownloadFile(this.filePath, this.start, this.length, this.originalFileName);

  int get end => start + length;

  bool _closed = false;

  bool get isClosed => _closed;

  /// Notify this class write the [block] (from [start] to [end]) into the downloading file ,
  /// content start position is [position]
  ///
  /// **NOTE** :
  ///
  /// Invoke this method does not mean this class should write content immediately , it will wait for other
  /// `READ`/`WRITE` which first come in the operation stack completing.
  ///
  Future<bool> requestWrite(
      int position, List<int> block, int start, int end) async {
    _writeAccess ??= await getRandomAccessFile(WRITE);
    var completer = Completer<bool>();
    _streamController?.add({
      'type': WRITE,
      'position': position,
      'block': block,
      'start': start,
      'end': end,
      'completer': completer
    });
    return completer.future;
  }

  Future<List<int>> requestRead(int position, int length) async {
    _readAccess ??= await getRandomAccessFile(READ);
    var completer = Completer<List<int>>();
    _streamController?.add({
      'type': READ,
      'position': position,
      'length': length,
      'completer': completer
    });
    return completer.future;
  }

  /// Process read and write requests.
  ///
  /// Only one request is processed at a time. The Stream is paused through StreamSubscription
  /// upon entering this method, and it resumes reading from the channel only after processing
  /// the current request.
  void _processRequest(event) async {
    _streamSubscription?.pause();
    if (event['type'] == WRITE) {
      await _write(event);
    }
    if (event['type'] == READ) {
      await _read(event);
    }
    if (event['type'] == FLUSH) {
      await _flush(event);
    }
    _streamSubscription?.resume();
  }

  Future _write(event) async {
    Completer completer = event['completer'];
    try {
      int position = event['position'];
      int start = event['start'];
      int end = event['end'];
      List<int> block = event['block'];

      _writeAccess = await getRandomAccessFile(WRITE);
      _writeAccess = await _writeAccess?.setPosition(position);
      _writeAccess = await _writeAccess?.writeFrom(block, start, end);
      completer.complete(true);
    } catch (e) {
      log('Write file error:', error: e, name: runtimeType.toString());
      completer.complete(false);
    }
  }

  /// Request to write the buffer to disk.
  Future<bool> requestFlush() async {
    _writeAccess ??= await getRandomAccessFile(WRITE);
    var completer = Completer<bool>();
    _streamController?.add({'type': FLUSH, 'completer': completer});
    return completer.future;
  }

  Future _flush(event) async {
    Completer completer = event['completer'];
    try {
      _writeAccess = await getRandomAccessFile(WRITE);
      await _writeAccess?.flush();
      completer.complete(true);
    } catch (e) {
      log('Flush error:', error: e, name: runtimeType.toString());
      completer.complete(false);
    }
  }

  Future _read(event) async {
    Completer completer = event['completer'];
    try {
      int position = event['position'];
      int length = event['length'];

      var access = await getRandomAccessFile(READ);
      access = await access.setPosition(position);
      var contents = await access.read(length);
      completer.complete(contents);
    } catch (e) {
      log('Read file error:', error: e, name: runtimeType.toString());
      completer.complete(<int>[]);
    }
  }

  ///
  /// Get the corresponding file, and if the file does not exist, create a new file.
  Future<File?> _getOrCreateFile() async {
    _file ??= File(filePath);
    var exists = await _file?.exists();
    if (exists != null && !exists) {
      _file = await _file?.create(recursive: true);
      var access = await _file?.open(mode: FileMode.write);
      access = await access?.truncate(length);
      await access?.close();
    }
    return _file;
  }

  Future<bool>? get exists {
    return File(filePath).exists();
  }

  Future<RandomAccessFile> getRandomAccessFile(String type) async {
    var file = await _getOrCreateFile();
    RandomAccessFile? access;
    if (type == WRITE) {
      _writeAccess ??= await file?.open(mode: FileMode.writeOnlyAppend);
      access = _writeAccess;
    } else if (type == READ) {
      _readAccess ??= await file?.open(mode: FileMode.read);
      access = _readAccess;
    }
    if (_streamController == null) {
      _streamController = StreamController();
      _streamSubscription = _streamController?.stream.listen(_processRequest);
    }
    return access!;
  }

  Future close() async {
    if (isClosed) return;
    _closed = true;
    try {
      await _streamSubscription?.cancel();
      await _streamController?.close();
      await _writeAccess?.flush();
      await _writeAccess?.close();
      await _readAccess?.close();
    } catch (e) {
      log('Close file error:', error: e, name: runtimeType.toString());
    } finally {
      _writeAccess = null;
      _readAccess = null;
      _streamSubscription = null;
      _streamController = null;
    }
    return;
  }

  Future flush() async {
    try {
      await _writeAccess?.flush();
    } catch (e) {
      log('Flush file error:', error: e, name: runtimeType.toString());
    }
  }

  Future delete() async {
    try {
      await close();
    } finally {
      var temp = _file;
      _file = null;
      var r = await temp?.delete();
      return r;
    }
  }

  @override
  bool operator ==(other) {
    if (other is DownloadFile) {
      return other.filePath == filePath;
    }
    return false;
  }

  @override
  int get hashCode => filePath.hashCode;
}
