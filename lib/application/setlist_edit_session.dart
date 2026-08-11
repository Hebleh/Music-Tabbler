import '../domain/library_models.dart';
import 'library_contracts.dart';

/// Owns the canonical mutation and persistence rule for one setlist.
///
/// Presentation layers remain responsible for dialogs, selection, and deck
/// navigation. This session only updates entry order/content and timestamps the
/// persisted aggregate.
class SetlistEditSession {
  SetlistEditSession({
    required LibrarySetlist initialSetlist,
    required this.repository,
    DateTime Function()? clock,
  }) : _current = initialSetlist,
       _clock = clock ?? DateTime.now;

  final SetlistLibrary repository;
  final DateTime Function() _clock;
  LibrarySetlist _current;

  LibrarySetlist get current => _current;

  Future<LibrarySetlist> replaceEntries(
    List<LibrarySetlistEntry> entries,
  ) async {
    final updated = LibrarySetlist(
      id: _current.id,
      name: _current.name,
      createdAt: _current.createdAt,
      updatedAt: _clock().toUtc(),
      scheduledAt: _current.scheduledAt,
      notes: _current.notes,
      entries: List<LibrarySetlistEntry>.unmodifiable(entries),
    );
    await repository.saveSetlist(updated);
    _current = updated;
    return updated;
  }

  Future<LibrarySetlist> reorder(int oldIndex, int newIndex) {
    final entries = List<LibrarySetlistEntry>.of(_current.entries);
    final moved = entries.removeAt(oldIndex);
    entries.insert(newIndex, moved);
    return replaceEntries(entries);
  }
}
