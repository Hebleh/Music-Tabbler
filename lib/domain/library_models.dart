enum ChartVariantKind { visual }

class LibrarySong {
  const LibrarySong({
    required this.id,
    required this.title,
    required this.artist,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String artist;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class ChartVariantIdentity {
  const ChartVariantIdentity({
    required this.id,
    required this.songId,
    required this.kind,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String songId;
  final ChartVariantKind kind;
  final DateTime createdAt;
  final DateTime updatedAt;
}
