import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:torrent_client/src/peer/bitfield.dart';

import '../utils.dart';

const KEEP_ALIVE_MESSAGE = [0, 0, 0, 0];
const RESERVED = [0, 0, 0, 0, 0, 0, 0, 0];
const HAND_SHAKE_HEAD = [
  19,
  66,
  105,
  116,
  84,
  111,
  114,
  114,
  101,
  110,
  116,
  32,
  112,
  114,
  111,
  116,
  111,
  99,
  111,
  108
];

const PEER_EVENT_CONNECTED = 'connected';
const PEER_EVENT_REQUEST_TIMEOUT = 'request_timeout';
const PEER_EVENT_CLOSE = 'close';
const PEER_EVENT_HANDSHAKE = 'handshake';
const PEER_EVENT_CHOKE_CHANGE = 'choke_change';
const PEER_EVENT_REQUEST = 'request';
const PEER_EVENT_BITFIELD = 'bitfield';
const PEER_EVENT_HAVE = 'have';
const PEER_EVENT_INTERESTED_CHANGE = 'interested_change';
const PEER_EVENT_PIECE = 'piece';
const PEER_EVENT_CANCEL = 'cancel';
const PEER_EVENT_PORT = 'port';
const PEER_EVENT_KEEPALIVE = 'keep_alive';
const PEER_EVENT_HAVE_ALL = 'have_all';
const PEER_EVENT_HAVE_NONE = 'have_none';
const PEER_EVENT_SUGGEST_PIECE = 'suggest_piece';
const PEER_EVENT_ALLOW_FAST = 'allow_fast';
const PEER_EVENT_REJECT_REQUEST = 'reject_request';

const ID_CHOKE = 0;
const ID_UNCHOKE = 1;
const ID_INTERESTED = 2;
const ID_NOT_INTERESTED = 3;
const ID_HAVE = 4;
const ID_BITFIELD = 5;
const ID_REQUEST = 6;
const ID_PIECE = 7;
const ID_CANCEL = 8;
const ID_PORT = 9;

const OP_HAVE_ALL = 0x0e;
const OP_HAVE_NONE = 0x0f;
const OP_SUGGEST_PIECE = 0x0d;
const OP_REJECT_REQUEST = 0x10;
const OP_ALLOW_FAST = 0x11;

/// 30 Seconds
const DEFAULT_CONNECT_TIMEOUT = 30;

/// 带有 [index],[begin],[length]参数的方法
typedef PieceConfigHandle = void Function(
    Peer peer, int index, int begin, int length);
typedef NoneParamHandle = void Function(Peer peer);

typedef BoolHandle = void Function(Peer peer, bool value);

typedef SingleIntHandle = void Function(Peer peer, int value);

abstract class Peer {
  /// Countdown time , when peer don't receive or send any message from/to remote ,
  /// this class will invoke close.
  /// 单位:秒
  int countdownTime = 150;

  bool _isSeeder = false;

  final int _piecesNum;

  // Bitfield _localBitfield;

  Bitfield _remoteBitfield;

  bool _disposed = false;

  Timer _countdownTimer;

  /// 对方是否choke了我，初始默认true
  bool _chokeMe = true;

  /// 我是否choke了对方，默认true
  bool chokeRemote = true;

  /// 对方是否对我的资源感兴趣，默认false
  bool _interestedMe = false;

  /// 我是否对对方的资源感兴趣，默认false
  bool interestedRemote = false;

  /// Debug 使用
  // ignore: unused_field
  dynamic _disposeReason;

  final Uri address;

  int connectTimeOut;

  final Uint8List _infoHashBuffer;

  final String _localPeerId; // 本机的peer id。发送消息会用到

  String _remotePeerId;

  bool _handShaked = false;

  StreamSubscription _streamChunk;

  List<int> cacheBuffer = [];

  final _handleFunctions = <String, Set<Function>>{};

  final _requestBuffer = <List<int>>[];

  final _remoteRequestBuffer = <List<int>>[];

  /// Every request timeout timer. The key format is `<index>-<begin>`
  final _requestTimeoutMap = <String, Timer>{};

  final _requestTimestamp = <String, int>{};

  /// Max request count in one piple ,5
  static const MAX_REQUEST_COUNT = 5;

  /// single request timeout time, 30 seconds
  static const REQUEST_TIME_OUT = 30;

  final String _id;

  int _downloaded = 0;

  int _uploaded = 0;

  int _startTime = -1;

  bool remoteEnableFastPeer = false;

  bool localEnableFastPeer = true;

  final Set<int> _allowFastPieces = <int>{};

  final Set<int> _remoteAllowFastPieces = <int>{};

  final Set<int> _suggestPieces = <int>{};

  Peer(this._id, this._localPeerId, this.address, this._infoHashBuffer,
      this._piecesNum,
      {this.localEnableFastPeer = true}) {
    _remoteBitfield = Bitfield.createEmptyBitfield(_piecesNum);
  }

  Bitfield get remoteBitfield => _remoteBitfield;

  int get downloaded => _downloaded;

  int get uploaded => _uploaded;

  bool get isLeecher => !_isSeeder;

  bool get isSeeder => _isSeeder;

  String get remotePeerId => _remotePeerId;

  String get localPeerId => _localPeerId;

  List<List<int>> get remoteRequestbuffer => _remoteRequestBuffer;

  List<List<int>> get requestBuffer => _requestBuffer;

  set isSeeder(bool b) {
    if (_isSeeder != b) {
      _isSeeder = b;
      sendChoke(_isSeeder);
    }
  }

  String get id => _id;

  bool get isDisposed => _disposed;

  bool get chokeMe => _chokeMe;

  /// 平均下载速度，b/s
  double get downloadSpeed {
    if (_startTime == -1) return 0.0;
    return _downloaded *
        1000 /
        (DateTime.now().millisecondsSinceEpoch - _startTime);
  }

  set chokeMe(bool c) {
    if (c != _chokeMe) {
      _chokeMe = c;
      if (_chokeMe) _startTime = -1;
      _fireChokeChangeEvent(_chokeMe);
    }
  }

  bool remoteHave(int index) {
    return _remoteBitfield.getBit(index);
  }

  bool get interestedMe => _interestedMe;

  set interestedMe(bool i) {
    if (i != _interestedMe) {
      _interestedMe = i;
      _fireInterestedChangeEvent(_interestedMe);
    }
  }

  /// Connect remote peer
  Future connect([int timeout = DEFAULT_CONNECT_TIMEOUT]) async {
    try {
      _disposeReason = null;
      _disposed = false;
      _handShaked = false;
      var _stream = await connectRemote(timeout);
      _streamChunk = _stream.listen(_processReceiveData, onDone: () {
        _log('Connection is closed $address');
        dispose(RemoteCloseException());
      }, onError: (e) {
        dispose(e);
      });
      _fireConnectEvent();
    } catch (e) {
      return dispose(e);
    }
  }

  void _processReceiveData(dynamic data) {
    // 不管收到什么消息，只要不是空的，重置倒计时:
    if (data.isNotEmpty) _startToCountdown();
    // if (data.isNotEmpty) log('收到数据 $data');
    cacheBuffer.addAll(data); // 接受remote发送数据。缓冲到一处
    if (cacheBuffer.isEmpty) return;
    // 查看是不是handshake头
    if (cacheBuffer[0] == 19 && cacheBuffer.length >= 68) {
      if (_isHandShakeHead(cacheBuffer)) {
        if (_validateInfoHash(cacheBuffer)) {
          var temp = cacheBuffer.sublist(0, 68);
          cacheBuffer = cacheBuffer.sublist(68);
          _processHandShake(temp);
          if (cacheBuffer.isNotEmpty) {
            Future.delayed(Duration.zero, () => _processReceiveData(<int>[]));
          }
          return;
        } else {
          // If infohash buffer is incorret , dispose this peer
          dispose('Infohash is incorret');
          return;
        }
      }
    }
    if (cacheBuffer.length >= 4) {
      var length =
          ByteData.sublistView(Uint8List.fromList(cacheBuffer.sublist(0, 4)))
              .getUint32(0, Endian.big);
      if (length == 0) {
        cacheBuffer = cacheBuffer.sublist(4);
        _processMessage(<int>[]);
        if (cacheBuffer.isNotEmpty) {
          Future.delayed(Duration.zero, () => _processReceiveData(<int>[]));
        }
      } else {
        if (cacheBuffer.length - 4 >= length) {
          var temp = cacheBuffer.sublist(4, length + 4);
          cacheBuffer = cacheBuffer.sublist(length + 4);
          // print('receive $length datas : $temp , ${temp.length}');
          _processMessage(temp);
          if (cacheBuffer.isNotEmpty) {
            Future.delayed(Duration.zero, () => _processReceiveData(<int>[]));
          }
        }
      }
    }
  }

  bool _isHandShakeHead(buffer) {
    if (buffer.length < 68) return false;
    for (var i = 0; i < 20; i++) {
      if (buffer[i] != HAND_SHAKE_HEAD[i]) return false;
    }
    return true;
  }

  bool _validateInfoHash(buffer) {
    for (var i = 28; i < 48; i++) {
      if (buffer[i] != _infoHashBuffer[i - 28]) return false;
    }
    return true;
  }

  void _processMessage(List<int> message) {
    if (message.isEmpty) {
      _log('process keep alive $address');
      _fireKeepAlive();
      return;
    } else {
      switch (message[0]) {
        case ID_CHOKE:
          _log('remote choke me : $address');
          chokeMe = true; // choke message
          return;
        case ID_UNCHOKE:
          _log('remote unchoke me : $address');
          chokeMe = false; // unchoke message
          return;
        case ID_INTERESTED:
          _log('remote interested me : $address');
          interestedMe = true;
          return; // interested message
        case ID_NOT_INTERESTED:
          _log('remote not interseted me : $address');
          interestedMe = false;
          return; // not interseted message
        case ID_HAVE:
          _log('process have from : $address');
          var index = ByteData.sublistView(
                  Uint8List.fromList(message), 1, message.length)
              .getUint32(0);
          _processHave(index);
          return; // have message
        case ID_BITFIELD:
          // log('process bitfield from $address');
          initRemoteBitfield(message);
          return; // bitfield message
        case ID_REQUEST:
          _log('process request from ${address}');
          _processRemoteRequest(message);
          return; // request message
        case ID_PIECE:
          _log('process pices : $address');
          _processReceivePiece(Uint8List.fromList(message));
          return; // pices message
        case ID_CANCEL:
          _log('process cancel : $address');
          _processCancel(message);
          return; // cancel message
        case ID_PORT:
          _log('process port : $address');
          var port = ByteData.sublistView(
              Uint8List.fromList(message), 1, message.length);
          _processPortChange(port.getUint32(0));
          return; // port message
        case OP_HAVE_ALL:
          _log('process have all : $address');
          _processHaveAll();
          return;
        case OP_HAVE_NONE:
          _log('process have none : $address');
          _processHaveNone();
          return;
        case OP_SUGGEST_PIECE:
          _log('process suggest pieces : $address');
          _processSuggestPiece(message);
          return;
        case OP_REJECT_REQUEST:
          _log('process reject request : $address');
          _processRejectRequest(message);
          return;
        case OP_ALLOW_FAST:
          _log('process allow fast : $address');
          _processAllowFast(message);
          return;
      }
    }
    _log('Cannot process the message', 'Unknown message : ${message}');
  }

  /// 从requestbuffer中将request删除
  ///
  /// 每当得到了piece回应或者request超时，都会调用此方法
  void _removeRequestFromBuffer(int index, int begin) {
    var finish = -1;
    for (var i = 0; i < _requestBuffer.length; i++) {
      var r = _requestBuffer[i];
      if (r[0] == index && r[1] == begin) {
        finish = i;
        break;
      }
    }
    if (finish != -1) _requestBuffer.removeAt(finish);
  }

  void _processCancel(List<int> message, [int offset = 1]) {
    var view = ByteData.view(Uint8List.fromList(message).buffer);
    var index = view.getUint32(offset);
    var begin = view.getUint32(offset + 4);
    var length = view.getUint32(offset + 8);
    var requestIndex;
    for (var i = 0; i < _remoteRequestBuffer.length; i++) {
      var r = _remoteRequestBuffer[i];
      if (r[0] == index && r[1] == begin) {
        requestIndex = i;
        break;
      }
    }
    if (requestIndex != null) {
      _remoteRequestBuffer.removeAt(requestIndex);
      _fireCancel(index, begin, length);
    }
  }

  void _processPortChange(int port) {
    if (address.port == port) return;
    _firePortChange(port);
  }

  void _processHaveAll() {
    if (!remoteEnableFastPeer) {
      dispose('Remote disabled fast extension but receive \'have all\'');
      return;
    }
    for (var i = 0; i < _remoteBitfield.buffer.length - 1; i++) {
      _remoteBitfield.buffer[i] = 255;
    }
    var index = _remoteBitfield.buffer.length - 1;
    index = index * 8;
    for (var i = index; i < _remoteBitfield.piecesNum; i++) {
      _remoteBitfield.setBit(i, true);
    }
    _fireRemoteHaveAll();
  }

  void _processHaveNone() {
    if (!remoteEnableFastPeer) {
      dispose('Remote disabled fast extension but receive \'have none\'');
      return;
    }
    _remoteBitfield = Bitfield.createEmptyBitfield(_piecesNum);
    _fireRemoteHaveNone();
  }

  ///
  /// When the fast extension is disabled, if a peer receives a Suggest Piece message,
  /// the peer MUST close the connection.
  void _processSuggestPiece(List<int> message, [int offset = 1]) {
    if (!remoteEnableFastPeer) {
      dispose('Remote disabled fast extension but receive \'suggest piece\'');
      return;
    }
    var view = ByteData.view(Uint8List.fromList(message).buffer);
    var index = view.getUint32(offset);
    if (_suggestPieces.add(index)) _fireSuggestPiece(index);
  }

  void _processRejectRequest(List<int> message, [int offset = 1]) {
    if (!remoteEnableFastPeer) {
      dispose('Remote disabled fast extension but receive \'reject request\'');
      return;
    }

    var view = ByteData.view(Uint8List.fromList(message).buffer);
    var index = view.getUint32(offset);
    var begin = view.getUint32(offset + 4);
    var length = view.getUint32(offset + 8);
    var match = false;
    var requestIndex;
    for (var i = 0; i < _remoteRequestBuffer.length; i++) {
      var r = _remoteRequestBuffer[i];
      if (r[0] == index && r[1] == begin) {
        match = true;
        requestIndex = i;
        break;
      }
    }
    if (!match) {
      dispose('Never send request ($index,$begin) but recieve a rejection');
      return;
    }
    _remoteRequestBuffer.removeAt(requestIndex);
    _fireRejectRequest(index, begin, length);
  }

  void _processAllowFast(List<int> message, [int offset = 1]) {
    if (!remoteEnableFastPeer) {
      dispose('Remote disabled fast extension but receive \'allow fast\'');
      return;
    }
    var view = ByteData.view(Uint8List.fromList(message).buffer);
    var index = view.getUint32(offset);
    if (_remoteAllowFastPieces.add(index)) {
      _fireAllowFast(index);
    }
  }

  /// When the fast extension is enabled:
  ///
  /// - If a peer receives a request from a peer its choking, the peer receiving the
  /// request SHOULD send a reject unless the piece is in the allowed fast set.
  /// - If a peer receives an excessive number of requests from a peer it is choking,
  /// the peer receiving the requests MAY close the connection rather than reject the request.
  /// However, consider that it can take several seconds for buffers to drain and messages to propagate once a peer is choked.
  void _processRemoteRequest(List<int> message, [int offset = 1]) {
    if (_remoteRequestBuffer.length >= MAX_REQUEST_COUNT) {
      dispose('Too many requests from ${address}');
    }
    var view = ByteData.view(Uint8List.fromList(message).buffer);
    var index = view.getUint32(offset);
    var begin = view.getUint32(offset + 4);
    var length = view.getUint32(offset + 8);
    for (var i = 0; i < _remoteRequestBuffer.length; i++) {
      var re = _remoteRequestBuffer[i];
      if (re[0] == index && re[1] == begin && re[2] == length) return;
    }
    if (chokeRemote) {
      if (_allowFastPieces.contains(index)) {
        _remoteRequestBuffer.add([index, begin, length]);
        _fireRequest(index, begin, length);
        return;
      } else {
        sendRejectRequest(index, begin, length);
        return;
      }
    }
    _remoteRequestBuffer.add([index, begin, length]);
    _fireRequest(index, begin, length);
  }

  void _processReceivePiece(List<int> message, [int offset = 1]) {
    var view = ByteData.view(Uint8List.fromList(message).buffer);
    var index = view.getUint32(offset);
    var begin = view.getUint32(offset + 4);
    _removeRequestFromBuffer(index, begin);
    var timer = _requestTimeoutMap.remove('$index-$begin');
    var timestamp = _requestTimestamp.remove('$index-$begin');
    var timeout = false;
    if (timer == null) {
      // 说明这个piece是超时后收到的
      timeout = true;
    }
    var now = DateTime.now().millisecondsSinceEpoch;
    var passtime = 0.0;
    if (timestamp != null) {
      passtime = (now - timestamp) * 1.0;
      passtime = passtime / 1000;
    }
    timer?.cancel();
    var contentLength = message.length - offset - 8;
    _downloaded += contentLength;
    _log(
        '收到请求Piece ($index,$begin) 内容, 从当前Peer已下载 $downloaded bytes , 平均速度：${downloadSpeed} b/s ');
    _firePiece(index, begin, message.sublist(offset + 8), timeout);
  }

  void _processHave(int index) {
    updateRemoteBitfield(index, true);
    _fireHave(index);
  }

  void updateRemoteBitfield(int index, bool have) {
    _remoteBitfield.setBit(index, have);
  }

  List<int> get remoteCompletePieces {
    if (_remoteBitfield == null) return [];
    return _remoteBitfield.completedPieces;
  }

  void initRemoteBitfield(List<int> bitfield) {
    _remoteBitfield = Bitfield.copyFrom(_piecesNum, bitfield, 1);
    _fireBitfield(_remoteBitfield);
  }

  void _processHandShake(List<int> data) {
    _remotePeerId = _parseRemotePeerId(data);
    var reseverd = data.getRange(20, 28);
    var fast = reseverd.elementAt(7) & 0x04;
    remoteEnableFastPeer = (fast == 0x04);
    _fireHandshakeEvent(_remotePeerId, data);
  }

  String _parseRemotePeerId(dynamic data) {
    if (data is List<int>) {
      return String.fromCharCodes(data.sublist(48, 68));
    }
    return null;
  }

  /// Connect remote peer and return a [Stream] future
  ///
  /// [timeout] defaul value is 30 seconds
  /// Different type peer use different protocol , such as TCP,uTP,
  /// so this method should be implemented by sub-class
  Future<Stream> connectRemote(int timeout);

  /// Send message to remote
  ///
  /// this method will transform the [message] and id to be the peer protocol message bytes
  void sendMessage(int id, [List<int> message]) {
    if (isDisposed) return;
    if (id == null) {
      // it's keep alive
      sendByteMessage(KEEP_ALIVE_MESSAGE);
      _startToCountdown();
      return;
    }
    var m = _createByteMessage(id, message);
    sendByteMessage(m);
    _startToCountdown();
  }

  List<int> _createByteMessage(int id, List<int> message) {
    var m = <int>[];
    var l = Uint8List(4);
    var length = 0;
    if (message != null) length = message.length;
    length = length + 1;
    var view = ByteData.view(l.buffer);
    view.setUint32(0, length, Endian.big);
    m.addAll(l);
    m.add(id);
    if (message != null && message.isNotEmpty) {
      m.addAll(message);
    }
    return m;
  }

  /// Send the message buffer to remote
  ///
  /// See : [Peer protocol message](https://wiki.theory.org/BitTorrentSpecification#Messages)
  void sendByteMessage(List<int> bytes);

  /// 发送handshake消息。
  ///
  /// 在发送handshake后，会主动发送bitfield和have消息给对方
  void sendHandShake() {
    if (_handShaked) return;
    var message = <int>[];
    message.addAll(HAND_SHAKE_HEAD);
    if (localEnableFastPeer) {
      var r = List<int>.from(RESERVED);
      r[7] |= 0x04;
      message.addAll(r);
    } else {
      message.addAll(RESERVED);
    }
    message.addAll(_infoHashBuffer);
    message.addAll(utf8.encode(_localPeerId));
    sendByteMessage(message);
    _startToCountdown();
    _handShaked = true;
  }

  /// `keep-alive: <len=0000>`
  ///
  /// The `keep-alive` message is a message with zero bytes, specified with the length prefix set to zero.
  /// There is no message ID and no payload. Peers may close a connection if they receive no messages
  /// (keep-alive or any other message) for a certain period of time, so a keep-alive message must be
  /// sent to maintain the connection alive if no command have been sent for a given amount of time.
  /// This amount of time is generally two minutes.
  void sendKeeplive() {
    sendMessage(null);
  }

  /// `piece: <len=0009+X><id=7><index><begin><block>`
  ///
  /// The `piece` message is variable length, where X is the length of the block. The payload contains the following information:
  ///
  /// - index: integer specifying the zero-based piece index
  /// - begin: integer specifying the zero-based byte offset within the piece
  /// - block: block of data, which is a subset of the piece specified by index.
  bool sendPiece(int index, int begin, Uint8List block) {
    if (chokeRemote) {
      if (!remoteEnableFastPeer) {
        return false;
      } else if (!_allowFastPieces.contains(index)) {
        return false;
      }
    }
    var requestIndex;
    for (var i = 0; i < _remoteRequestBuffer.length; i++) {
      var r = _remoteRequestBuffer[i];
      if (r[0] == index && r[1] == begin) {
        requestIndex = i;
        break;
      }
    }
    if (requestIndex == null) return false;
    _remoteRequestBuffer.removeAt(requestIndex);

    var bytes = <int>[];
    var messageHead = Uint8List(8);
    var view = ByteData.view(messageHead.buffer);
    view.setUint32(0, index, Endian.big);
    view.setUint32(4, begin, Endian.big);
    bytes.addAll(messageHead);
    bytes.addAll(block);
    sendMessage(ID_PIECE, bytes);
    return true;
  }

  /// `request: <len=0013><id=6><index><begin><length>`
  ///
  /// The `request` message is fixed length, and is used to request a block.
  /// The payload contains the following information:
  ///
  /// - [index]: integer specifying the zero-based piece index
  /// - [begin]: integer specifying the zero-based byte offset within the piece
  /// - [length]: integer specifying the requested length.
  /// - [timeout]: when send request to remote , after [timeout] dont get response,
  /// it will fire [requestTimeout] event
  bool sendRequest(int index, int begin,
      [int length = DEFAULT_REQUEST_LENGTH, int timeout = REQUEST_TIME_OUT]) {
    if (_chokeMe) {
      if (!remoteEnableFastPeer || !_remoteAllowFastPieces.contains(index)) {
        return false;
      }
    }
    if (_requestBuffer.length >= MAX_REQUEST_COUNT) return false;
    _requestBuffer.add([index, begin, length]);
    if (_startTime == -1) _startTime = DateTime.now().millisecondsSinceEpoch;
    var t = Timer(Duration(seconds: timeout), () {
      _requestTimeout(index, begin, length);
    });
    _requestTimeoutMap['$index-$begin'] = t;
    _requestTimestamp['$index-$begin'] = DateTime.now().millisecondsSinceEpoch;
    var bytes = Uint8List(12);
    var view = ByteData.view(bytes.buffer);
    view.setUint32(0, index, Endian.big);
    view.setUint32(4, begin, Endian.big);
    view.setUint32(8, length, Endian.big);
    // print('send ($index,$begin) request to $address');
    sendMessage(ID_REQUEST, bytes);
    return true;
  }

  void _requestTimeout(int index, int begin, int length) {
    _requestTimeoutMap.remove('$index-$begin');
    // _removeRequestFromBuffer(index, begin);
    _fireRequestTimeoutEvent(index, begin, length);
  }

  /// `bitfield: <len=0001+X><id=5><bitfield>`
  ///
  /// The `bitfield` message may only be sent immediately after the handshaking sequence is completed,
  /// and before any other messages are sent. It is optional, and need not be sent if a client has no pieces.
  /// However,if no pieces to send and remote peer enable fast extension, it will send `Have None` message,
  /// and if have all pieces, it will send `Have All` message instead of bitfield buffer.
  ///
  /// The `bitfield` message is variable length, where X is the length of the bitfield. The payload is a
  /// bitfield representing the pieces that have been successfully downloaded. The high bit in the first byte
  /// corresponds to piece index 0. Bits that are cleared indicated a missing piece, and set bits indicate a
  /// valid and available piece. Spare bits at the end are set to zero.
  ///
  void sendBitfield(Bitfield bitfield) {
    _log('发送bitfile信息给对方 : ${bitfield.buffer}');
    if (remoteEnableFastPeer) {
      if (bitfield.haveNone()) {
        sendHaveNone();
      } else if (bitfield.haveAll()) {
        sendHaveAll();
      } else {
        sendMessage(ID_BITFIELD, bitfield.buffer);
      }
    } else if (bitfield.haveCompletePiece()) {
      sendMessage(ID_BITFIELD, bitfield.buffer);
    }
  }

  /// `have: <len=0005><id=4><piece index>`
  ///
  /// The `have` message is fixed length. The payload is the zero-based
  /// index of a piece that has just been successfully downloaded and verified via the hash.
  void sendHave(int index) {
    var bytes = Uint8List(4);
    _log('发送have信息给对方 : ${bytes},$index');
    ByteData.view(bytes.buffer).setUint32(0, index, Endian.big);
    sendMessage(ID_HAVE, bytes);
  }

  /// - `choke: <len=0001><id=0>`
  /// - `unchoke: <len=0001><id=1>`
  ///
  /// The `choke`/`unchoke` message is fixed-length and has no payload.
  void sendChoke(bool ichokeu) {
    if (chokeRemote == ichokeu) {
      return;
    }
    chokeRemote = ichokeu;
    var id = ID_CHOKE;
    if (!ichokeu) id = ID_UNCHOKE;
    sendMessage(id);
  }

  /// 发送`interested` 或 `not interested` 到 对方，表明自己是否对它拥有资源感兴趣
  ///
  /// - `interested: <len=0001><id=2>`
  /// - `not interested: <len=0001><id=3>`
  ///
  /// The `interested`/`not interested` message is fixed-length and has no payload.
  void sendInterested(bool iamInterested) {
    if (interestedRemote == iamInterested) {
      return;
    }
    interestedRemote = iamInterested;
    var id = ID_INTERESTED;
    if (!iamInterested) id = ID_NOT_INTERESTED;
    sendMessage(id);
  }

  /// `cancel: <len=0013><id=8><index><begin><length>`
  ///
  /// The `cancel` message is fixed length, and is used to cancel block requests.
  /// The payload is identical to that of the "request" message. It is typically used during "End Game"
  void sendCancel(int index, int begin, int length) {
    var bytes = Uint8List(12);
    var view = ByteData.view(bytes.buffer);
    view.setUint32(0, index, Endian.big);
    view.setUint32(4, begin, Endian.big);
    view.setUint32(8, length, Endian.big);
    sendMessage(ID_CANCEL, bytes);
  }

  /// `port: <len=0003><id=9><listen-port>`
  ///
  /// The [port] message is sent by newer versions of the Mainline that implements a DHT tracker.
  /// The listen port is the port this peer's DHT node is listening on. This peer should be
  /// inserted in the local routing table (if DHT tracker is supported).
  void sendPortChange(int port) {
    var bytes = Uint8List(8);
    ByteData.view(bytes.buffer).setUint32(0, port);
    sendMessage(ID_PORT, bytes);
  }

  /// BEP 0006
  ///
  /// Have all message
  void sendHaveAll() {
    if (remoteEnableFastPeer) {
      sendMessage(OP_HAVE_ALL);
    }
  }

  /// BEP 0006
  ///
  /// Have none message
  void sendHaveNone() {
    if (remoteEnableFastPeer) {
      sendMessage(OP_HAVE_NONE);
    }
  }

  /// BEP 0006
  /// `*Suggest Piece*: <len=0x0005><op=0x0D><index>`
  ///
  /// `Suggest Piece` is an advisory message meaning "you might like to download this piece."
  /// The intended usage is for 'super-seeding' without throughput reduction, to avoid redundant
  /// downloads, and so that a seed which is disk I/O bound can upload continguous or identical
  /// pieces to avoid excessive disk seeks.
  ///
  /// In all cases, the seed SHOULD operate to maintain a roughly equal number of copies of each
  /// piece in the network. A peer MAY send more than one suggest piece message at any given time.
  /// A peer receiving multiple suggest piece messages MAY interpret this as meaning that all of
  /// the suggested pieces are equally appropriate.
  ///
  void sendSuggestPiece(int index) {
    if (remoteEnableFastPeer) {
      var bytes = Uint8List(4);
      var view = ByteData.view(bytes.buffer);
      view.setUint32(0, index, Endian.big);
      sendMessage(OP_SUGGEST_PIECE, bytes);
    }
  }

  /// BEP 0006
  ///
  /// `*Reject Request*: <len=0x000D><op=0x10><index><begin><length>`
  ///
  /// Reject Request notifies a requesting peer that its request will not be satisfied.
  ///
  void sendRejectRequest(int index, int begin, int length) {
    if (remoteEnableFastPeer) {
      var bytes = Uint8List(12);
      var view = ByteData.view(bytes.buffer);
      view.setUint32(0, index, Endian.big);
      view.setUint32(4, begin, Endian.big);
      view.setUint32(8, length, Endian.big);
      sendMessage(OP_REJECT_REQUEST, bytes);
    }
  }

  /// BEP 0006
  ///
  /// `*Allowed Fast*: <len=0x0005><op=0x11><index>`
  ///
  /// `Allowed Fast` is an advisory message which means "if you ask for this piece,
  /// I'll give it to you even if you're choked."
  ///
  /// `Allowed Fast` thus shortens the awkward stage during which the peer obtains occasional
  ///  optimistic unchokes but cannot sufficiently reciprocate to remain unchoked.
  ///
  void sendAllowFast(int index) {
    if (remoteEnableFastPeer) {
      var bytes = Uint8List(4);
      var view = ByteData.view(bytes.buffer);
      view.setUint32(0, index, Endian.big);
      sendMessage(OP_ALLOW_FAST, bytes);
    }
  }

  /// 开始倒计时。
  ///
  /// Over 2 minutes , peer will close to disconnect remote.
  /// but if peer send any message or receive any message from remote during countdown,
  /// it will re-countdown.
  void _startToCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer(Duration(seconds: countdownTime), () {
      dispose(TimeoutException());
    });
  }

  /// 该Peer被dispose。
  ///
  /// 被dispose后的peer将无法再发送或监听数据，状态数据也恢复到初始状态，并且之前添加的事件监听
  /// 器都会被移除。
  Future dispose([dynamic reason]) async {
    _disposeReason = reason;
    if (_disposed) return;
    _disposed = true;
    _fireDisposeEvent(reason);
    _handleFunctions.clear();
    _handShaked = false;
    var re = _streamChunk?.cancel();
    _streamChunk = null;
    _requestTimeoutMap.forEach((key, value) {
      value.cancel();
    });
    _requestTimeoutMap.clear();
    _requestTimestamp.clear();
    _countdownTimer?.cancel();
    _countdownTimer = null;
    return re;
  }

  Set<Function> _getFunctionSet(String key) {
    var fSet = _handleFunctions[key];
    if (fSet == null) {
      fSet = <Function>{};
      _handleFunctions[key] = fSet;
    }
    return fSet;
  }

  void _fireConnectEvent() {
    var fSet = _handleFunctions[PEER_EVENT_CONNECTED];
    fSet?.forEach((f) {
      Timer.run(() => f(this));
    });
  }

  void _fireRequestTimeoutEvent(int index, int begin, int length) {
    var fSet = _handleFunctions[PEER_EVENT_REQUEST_TIMEOUT];
    fSet?.forEach((f) {
      Timer.run(() => f(this, index, begin, length));
    });
  }

  void _fireDisposeEvent([dynamic reason]) {
    var fSet = _handleFunctions[PEER_EVENT_CLOSE];
    fSet?.forEach((f) {
      Timer.run(() => f(this, reason));
    });
  }

  void _fireHandshakeEvent(String remotePeerId, dynamic data) {
    var fSet = _handleFunctions[PEER_EVENT_HANDSHAKE];
    fSet?.forEach((f) {
      Timer.run(() => f(this, remotePeerId, data));
    });
  }

  void _fireChokeChangeEvent(bool choke) {
    var fSet = _handleFunctions[PEER_EVENT_CHOKE_CHANGE];
    fSet?.forEach((f) {
      Timer.run(() => f(this, choke));
    });
  }

  void _fireInterestedChangeEvent(bool interested) {
    var fSet = _handleFunctions[PEER_EVENT_INTERESTED_CHANGE];
    fSet?.forEach((f) {
      Timer.run(() => f(this, interested));
    });
  }

  void _fireKeepAlive() {
    var fSet = _handleFunctions[PEER_EVENT_KEEPALIVE];
    fSet?.forEach((f) {
      Timer.run(() => f(this));
    });
  }

  void _fireRequest(int index, int begin, int length) {
    var fSet = _handleFunctions[PEER_EVENT_REQUEST];
    fSet?.forEach((f) {
      Timer.run(() => f(this, index, begin, length));
    });
  }

  void _fireBitfield(final Bitfield bitfield) {
    var fSet = _handleFunctions[PEER_EVENT_BITFIELD];
    fSet?.forEach((f) {
      Timer.run(() => f(this, bitfield));
    });
  }

  void _firePiece(int index, int begin, List<int> block,
      [bool afterTimeout = false]) {
    var fSet = _handleFunctions[PEER_EVENT_PIECE];
    fSet?.forEach((f) {
      Timer.run(() => f(this, index, begin, block, afterTimeout));
    });
  }

  void _fireHave(dynamic index) {
    var fSet = _handleFunctions[PEER_EVENT_HAVE];
    fSet?.forEach((f) {
      Timer.run(() => f(this, index));
    });
  }

  void _fireCancel(int index, int begin, int length) {
    var fSet = _handleFunctions[PEER_EVENT_CANCEL];
    fSet?.forEach((f) {
      Timer.run(() => f(this, index, begin, length));
    });
  }

  void _firePortChange(int port) {
    var fSet = _handleFunctions[PEER_EVENT_PORT];
    fSet?.forEach((f) {
      f(this, port);
    });
  }

  void _fireRemoteHaveAll() {
    var fSet = _handleFunctions[PEER_EVENT_HAVE_ALL];
    fSet?.forEach((f) {
      f(this);
    });
  }

  void _fireRemoteHaveNone() {
    var fSet = _handleFunctions[PEER_EVENT_HAVE_NONE];
    fSet?.forEach((f) {
      f(this);
    });
  }

  void _fireSuggestPiece(int index) {
    var fSet = _handleFunctions[PEER_EVENT_SUGGEST_PIECE];
    fSet?.forEach((f) {
      f(this, index);
    });
  }

  void _fireAllowFast(int index) {
    var fSet = _handleFunctions[PEER_EVENT_ALLOW_FAST];
    fSet?.forEach((f) {
      f(this, index);
    });
  }

  void _fireRejectRequest(int index, int begin, int length) {
    var fSet = _handleFunctions[PEER_EVENT_REJECT_REQUEST];
    fSet?.forEach((f) {
      f(this, index, begin, length);
    });
  }

  bool onRejectRequest(PieceConfigHandle handle) {
    return _onPieceConfigCallback(handle, PEER_EVENT_REJECT_REQUEST);
  }

  bool onAllowFast(SingleIntHandle handle) {
    return _onSingleIntCallback(handle, PEER_EVENT_ALLOW_FAST);
  }

  bool onSuggestPiece(SingleIntHandle handle) {
    return _onSingleIntCallback(handle, PEER_EVENT_SUGGEST_PIECE);
  }

  bool onHaveAll(NoneParamHandle handle) {
    return _onNoneParamCallback(handle, PEER_EVENT_HAVE_ALL);
  }

  bool onHaveNone(NoneParamHandle handle) {
    return _onNoneParamCallback(handle, PEER_EVENT_HAVE_NONE);
  }

  bool onCancel(PieceConfigHandle handle) {
    return _onPieceConfigCallback(handle, PEER_EVENT_CANCEL);
  }

  bool onPortChange(SingleIntHandle handle) {
    return _onSingleIntCallback(handle, PEER_EVENT_PORT);
  }

  bool onHave(SingleIntHandle handle) {
    return _onSingleIntCallback(handle, PEER_EVENT_HAVE);
  }

  bool onPiece(
      Function(Peer peer, int index, int begin, List<int> block,
              bool afterTimeout)
          handle) {
    var list = _getFunctionSet(PEER_EVENT_PIECE);
    return list.add(handle);
  }

  bool onBitfield(Function(Peer peer, Bitfield bitfield) handle) {
    var list = _getFunctionSet(PEER_EVENT_BITFIELD);
    return list.add(handle);
  }

  bool onKeepalive(NoneParamHandle handle) {
    return _onNoneParamCallback(handle, PEER_EVENT_KEEPALIVE);
  }

  bool onChokeChange(BoolHandle handle) {
    return _onBoolCallback(handle, PEER_EVENT_CHOKE_CHANGE);
  }

  bool onInterestedChange(BoolHandle handle) {
    return _onBoolCallback(handle, PEER_EVENT_INTERESTED_CHANGE);
  }

  bool onRequest(PieceConfigHandle handle) {
    return _onPieceConfigCallback(handle, PEER_EVENT_REQUEST);
  }

  bool onRequestTimeout(PieceConfigHandle handle) {
    return _onPieceConfigCallback(handle, PEER_EVENT_REQUEST_TIMEOUT);
  }

  bool onHandShake(
      Function(Peer peer, String remotePeerId, dynamic data) handle) {
    var list = _getFunctionSet(PEER_EVENT_HANDSHAKE);
    return list.add(handle);
  }

  bool onConnect(NoneParamHandle handle) {
    return _onNoneParamCallback(handle, PEER_EVENT_CONNECTED);
  }

  bool onDispose(Function(Peer peer, [dynamic reason]) handle) {
    var list = _getFunctionSet(PEER_EVENT_CLOSE);
    return list.add(handle);
  }

  bool _onNoneParamCallback(NoneParamHandle handle, String type) {
    var list = _getFunctionSet(type);
    return list.add(handle);
  }

  bool _onPieceConfigCallback(PieceConfigHandle handle, String type) {
    var list = _getFunctionSet(type);
    return list.add(handle);
  }

  bool _onBoolCallback(BoolHandle handle, String type) {
    var list = _getFunctionSet(type);
    return list.add(handle);
  }

  bool _onSingleIntCallback(SingleIntHandle handle, String type) {
    var list = _getFunctionSet(type);
    return list.add(handle);
  }

  void _log(String message, [dynamic error]) {
    if (error != null) {
      log(message, error: error, name: runtimeType.toString());
    } else {
      log(message, name: runtimeType.toString());
    }
  }

  @override
  int get hashCode => _id.hashCode;

  @override
  bool operator ==(b) {
    if (b is Peer) {
      return b.id == _id;
    }
    return false;
  }
}

class TimeoutException implements Exception {}

class RemoteCloseException implements Exception {}