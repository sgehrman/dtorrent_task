abstract class PeersManagerEvent {}

class AllComplete implements PeersManagerEvent {}

class RecievedBlock implements PeersManagerEvent {
  final int index;
  final int begin;
  final List<int> block;

  RecievedBlock(this.index, this.begin, this.block);
}
