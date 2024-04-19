import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:dtorrent_task/src/peer/peer_base.dart';
import 'package:dtorrent_task/src/peer/peer_events.dart';
import 'package:events_emitter2/events_emitter2.dart';

mixin ExtendedProcessor on EventsEmittable<PeerEvent> {
  final Map<int, String> _extendedEventMap = {};
  int _id = 1;
  Map? _rawMap;
  final Map<int, String> _localExtended = <int, String>{};

  Map<String, int> get localExtended {
    var map = <String, int>{};
    _localExtended.forEach((key, value) {
      map[value] = key;
    });
    return map;
  }

  void registerExtend(String name) {
    _localExtended[_id] = name;
    _id++;
  }

  int? getExtendedEventId(String name) {
    if (_rawMap != null) {
      return _rawMap![name];
    }
    return null;
  }

  void processExtendMessage(int id, Uint8List message) {
    if (id == 0) {
      var data = decode(message);
      processExtendHandshake(data);
    } else {
      var name = _localExtended[id];
      if (name != null) {
        //TODO: remove the need for casting
        events.emit(ExtendedEvent(this as Peer, name, message));
      }
    }
  }

  void processExtendHandshake(dynamic data) {
    if (data == null || !(data as Map<String, dynamic>).containsKey('m')) {
      return;
    }
    var m = data['m'] as Map<String, dynamic>;
    _rawMap = m;
    m.forEach((key, value) {
      if (value == 0) return;
      _extendedEventMap[value] = key;
    });
    //TODO: remove the need for casting
    events.emit(ExtendedEvent(this as Peer, 'handshake', data));
  }

  void clearExtendedProcessors() {
    _extendedEventMap.clear();
    _rawMap?.clear();
    _localExtended.clear();
    _id = 1;
  }
}
