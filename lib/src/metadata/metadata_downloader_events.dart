abstract class MetadataDownloaderEvent {}

class MetaDataDownloadComplete implements MetadataDownloaderEvent {
  List<int> data;
  MetaDataDownloadComplete(
    this.data,
  );
}

class MetaDataDownloadProgress implements MetadataDownloaderEvent {
  num progress;
  MetaDataDownloadProgress(
    this.progress,
  );
}
