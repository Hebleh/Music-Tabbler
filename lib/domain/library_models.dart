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

class LibrarySetlistEntry {
  const LibrarySetlistEntry({required this.id, required this.chartVariantId});

  final String id;
  final String chartVariantId;
}

class LibrarySetlist {
  LibrarySetlist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.scheduledAt,
    this.notes,
    List<LibrarySetlistEntry> entries = const [],
  }) : entries = List.unmodifiable(entries);

  final String id;
  final String name;
  final DateTime? scheduledAt;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<LibrarySetlistEntry> entries;
}

class MissingChartVariantReferencesException implements Exception {
  MissingChartVariantReferencesException(List<String> chartVariantIds)
    : chartVariantIds = List.unmodifiable(chartVariantIds);

  final List<String> chartVariantIds;

  @override
  String toString() => 'Unknown chart variants: ${chartVariantIds.join(', ')}.';
}

class ChartVariantReferencedBySetlistsException implements Exception {
  ChartVariantReferencedBySetlistsException({
    required this.chartVariantId,
    required List<String> setlistIds,
  }) : setlistIds = List.unmodifiable(setlistIds);

  final String chartVariantId;
  final List<String> setlistIds;

  @override
  String toString() =>
      'Chart variant $chartVariantId is referenced by setlists: '
      '${setlistIds.join(', ')}.';
}

class SetlistEntryIdentityConflictException implements Exception {
  SetlistEntryIdentityConflictException(List<String> entryIds)
    : entryIds = List.unmodifiable(entryIds);

  final List<String> entryIds;

  @override
  String toString() =>
      'Setlist entry IDs already belong to another setlist: '
      '${entryIds.join(', ')}.';
}
