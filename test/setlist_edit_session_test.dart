import 'package:flutter_test/flutter_test.dart';
import 'package:music_tabbler/application/setlist_edit_session.dart';
import 'package:music_tabbler/application/library_contracts.dart';
import 'package:music_tabbler/domain/library_models.dart';

void main() {
  test(
    'setlist session preserves metadata and owns reorder persistence',
    () async {
      final createdAt = DateTime.utc(2026, 1, 1);
      final editedAt = DateTime.utc(2026, 2, 3, 4, 5);
      final repository = _SetlistRepository();
      final session = SetlistEditSession(
        initialSetlist: LibrarySetlist(
          id: 'set-1',
          name: 'Stage set',
          createdAt: createdAt,
          updatedAt: createdAt,
          scheduledAt: DateTime.utc(2026, 4, 1),
          notes: 'Keep this',
          entries: const [
            LibrarySetlistEntry(id: 'a', chartVariantId: 'chart-a'),
            LibrarySetlistEntry.placeholder(id: 'b', title: 'Break'),
          ],
        ),
        repository: repository,
        clock: () => editedAt,
      );

      final result = await session.reorder(0, 1);

      expect(result.entries.map((entry) => entry.id), ['b', 'a']);
      expect(result.name, 'Stage set');
      expect(result.createdAt, createdAt);
      expect(result.updatedAt, editedAt);
      expect(result.scheduledAt, DateTime.utc(2026, 4, 1));
      expect(result.notes, 'Keep this');
      expect(repository.saved, same(result));
      expect(session.current, same(result));
    },
  );
}

class _SetlistRepository implements SetlistLibrary {
  LibrarySetlist? saved;

  @override
  Future<void> saveSetlist(LibrarySetlist setlist) async => saved = setlist;

  @override
  Future<void> deleteSetlist(String id) => throw UnimplementedError();

  @override
  Future<LibrarySetlist?> loadSetlist(String id) => throw UnimplementedError();

  @override
  Future<List<LibrarySetlist>> listSetlists() => throw UnimplementedError();

  @override
  Future<void> reorderSetlistEntries(
    String setlistId,
    List<String> orderedEntryIds, {
    required DateTime updatedAt,
  }) => throw UnimplementedError();
}
