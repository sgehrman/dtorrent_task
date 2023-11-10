import 'dart:typed_data';

import 'package:dtorrent_task/dtorrent_task.dart';

abstract class PeerEvent {}

class PeerChokeChanged implements PeerEvent {
  final Peer peer;
  final bool choked;
  PeerChokeChanged(this.peer, this.choked);
}

class PeerInterestedChanged implements PeerEvent {
  final Peer peer;
  final bool interested;

  PeerInterestedChanged(this.peer, this.interested);
}

class PeerConnected implements PeerEvent {
  final Peer peer;

  PeerConnected(this.peer);
}

class PeerKeepAlive implements PeerEvent {}

class PeerCancelEvent implements PeerEvent {
  final int index;
  final int begin;
  final int length;

  PeerCancelEvent(this.index, this.begin, this.length);
}

class PeerPortChanged implements PeerEvent {
  final int port;
  PeerPortChanged(this.port);
}

class PeerHaveAll implements PeerEvent {
  final Peer peer;

  PeerHaveAll(this.peer);
}

class PeerHaveNone implements PeerEvent {
  final Peer peer;

  PeerHaveNone(this.peer);
}

class PeerSuggestPiece implements PeerEvent {
  final Peer peer;
  final int index;

  PeerSuggestPiece(this.peer, this.index);
}

class PeerRejectEvent implements PeerEvent {
  final int index;
  final int begin;
  final int length;

  PeerRejectEvent(this.index, this.begin, this.length);
}

class PeerAllowFast implements PeerEvent {
  final Peer peer;
  final int index;
  PeerAllowFast(this.peer, this.index);
}

class PeerRequestEvent implements PeerEvent {
  final Peer peer;
  final int index;
  final int begin;
  final int length;

  PeerRequestEvent(this.peer, this.index, this.begin, this.length);
}

class PeerPieceEvent implements PeerEvent {
  final Peer peer;
  final int index;
  final int begin;
  final Uint8List block;

  PeerPieceEvent(this.peer, this.index, this.begin, this.block);
}

class PeerHaveEvent implements PeerEvent {
  final Peer peer;
  final List<int> indices;

  PeerHaveEvent(this.peer, this.indices);
}

class PeerHandshakeEvent implements PeerEvent {
  final Peer peer;
  final String remotePeerId;
  final List<int> data;

  PeerHandshakeEvent(this.peer, this.remotePeerId, this.data);
}

class PeerBitfieldEvent implements PeerEvent {
  final Peer peer;
  final Bitfield? bitfield;

  PeerBitfieldEvent(this.peer, this.bitfield);
}

class PeerDisposeEvent implements PeerEvent {
  final Peer peer;
  final dynamic reason;

  PeerDisposeEvent(this.peer, this.reason);
}

// extended processor events

class ExtendedEvent implements PeerEvent {
  String eventName;
  dynamic data;
  ExtendedEvent(
    this.eventName,
    this.data,
  );
}

class RequestTimeoutEvent implements PeerEvent {
  List<List<int>> requests;
  RequestTimeoutEvent(
    this.requests,
  );
}
