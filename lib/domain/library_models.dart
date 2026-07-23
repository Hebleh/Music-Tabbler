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

enum SetlistEntryKind { chart, placeholder }

sealed class LibrarySetlistEntry {
  const LibrarySetlistEntry._({required this.id});

  const factory LibrarySetlistEntry({
    required String id,
    required String chartVariantId,
  }) = ChartSetlistEntry;

  const factory LibrarySetlistEntry.placeholder({
    required String id,
    required String title,
  }) = PlaceholderSetlistEntry;

  final String id;
  SetlistEntryKind get kind;
  String? get chartVariantId;
  String? get placeholderTitle;
}

final class ChartSetlistEntry extends LibrarySetlistEntry {
  const ChartSetlistEntry({required super.id, required this.chartVariantId})
    : super._();

  @override
  SetlistEntryKind get kind => SetlistEntryKind.chart;

  @override
  final String chartVariantId;

  @override
  String? get placeholderTitle => null;
}

final class PlaceholderSetlistEntry extends LibrarySetlistEntry {
  const PlaceholderSetlistEntry({required super.id, required this.title})
    : super._();

  @override
  SetlistEntryKind get kind => SetlistEntryKind.placeholder;

  final String title;

  @override
  String? get chartVariantId => null;

  @override
  String get placeholderTitle => title;
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
