abstract class MetadataDownloaderEvent {}

class MetaDataDownloadComplete implements MetadataDownloaderEvent {
  List<int> data;
  MetaDataDownloadComplete(
    this.data,
  );
}
