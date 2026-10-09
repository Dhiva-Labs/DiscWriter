import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../burn/models.dart';
import '../burn/plans.dart';
import '../project/disc_project.dart';
import '../state/providers.dart';
import 'job_dialog.dart';
import 'theme.dart';
import 'widgets.dart';

class DataDiscPage extends ConsumerStatefulWidget {
  const DataDiscPage({super.key});

  @override
  ConsumerState<DataDiscPage> createState() => _DataDiscPageState();
}

class _DataDiscPageState extends ConsumerState<DataDiscPage> {
  late final TextEditingController _label;
  var _dragging = false;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(text: ref.read(projectProvider).label);
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _addFiles() async {
    final files = await openFiles();
    ref.read(projectProvider.notifier).addPaths(files.map((f) => f.path));
  }

  Future<void> _addFolders() async {
    final dirs = await getDirectoryPaths(confirmButtonText: 'Add');
    ref.read(projectProvider.notifier).addPaths(dirs.whereType<String>());
  }

  Future<void> _rename(DiscEntry entry) async {
    final controller = TextEditingController(text: entry.name);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Name on disc'),
        content: SizedBox(
          width: 380,
          child: TextField(controller: controller, autofocus: true, onSubmitted: (v) => Navigator.pop(c, v)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, controller.text), child: const Text('Rename')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim() == entry.name || !mounted) return;
    final problem = validateEntryName(name.trim());
    final ok = problem == null && ref.read(projectProvider.notifier).rename(entry.sourcePath, name);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(problem ?? 'Another item on the disc is already called "${name.trim()}"')),
      );
    }
  }

  Future<void> _saveIso() async {
    final project = ref.read(projectProvider);
    final location = await getSaveLocation(
      suggestedName: '${project.label.replaceAll(RegExp(r'[/\\]'), '_')}.iso',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Disc image', extensions: ['iso']),
      ],
      confirmButtonText: 'Save',
    );
    if (location == null || !mounted) return;
    var path = location.path;
    if (!path.toLowerCase().endsWith('.iso')) path = '$path.iso';
    await runJobWithDialog(
      context,
      ref,
      'Saving "${project.label}" as an image',
      buildIsoPlan(project, path),
      destructiveCancel: false,
    );
  }

  Future<void> _burn() async {
    final x = ref.read(xorrisoProvider)!;
    final project = ref.read(projectProvider);
    final drive = ref.read(selectedDriveProvider)!;
    final media = ref.read(mediaProvider).value!;
    final opts = ref.read(burnOptionsProvider);
    if (opts.eraseFirst && media.erasable && !media.blank && !opts.simulate) {
      final ok = await _confirmErase(media);
      if (ok != true || !mounted) return;
    }
    final verb = opts.simulate ? 'Simulating' : 'Burning';
    await runJobWithDialog(
      context,
      ref,
      '$verb "${project.label}"',
      burnProjectPlan(x, project, drive, media, opts),
    );
  }

  Future<bool?> _confirmErase(MediaInfo media) => showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Erase the disc first?'),
      content: Text(
        'Everything on this ${media.displayName}'
        '${media.volumeId == null ? '' : ' ("${media.volumeId}")'} will be erased '
        'before writing.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Erase and burn')),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectProvider);
    final capacity = ref.watch(capacityBlocksProvider);
    final busy = ref.watch(jobProvider.select((j) => j != null && !j.finished));
    final opts = ref.watch(burnOptionsProvider);
    final theme = Theme.of(context);
    final labelError = validateLabel(project.label);
    final tooBig = project.estimatedBlocks > capacity;

    final contentBlocker = project.isEmpty
        ? 'Add files or folders to begin'
        : labelError != null
        ? 'Fix the disc label'
        : project.sizing
        ? 'Still measuring…'
        : null;
    final burnBlocker =
        contentBlocker ?? driveBlocker(ref) ?? (tooBig ? 'Too much data for this disc' : null);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Data disc',
                subtitle: 'Collect files and folders, then burn them to CD, DVD or Blu-ray.',
                actions: [
                  OutlinedButton.icon(
                    onPressed: busy ? null : _addFiles,
                    icon: const Icon(Icons.note_add_outlined, size: 18),
                    label: const Text('Add files'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : _addFolders,
                    icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                    label: const Text('Add folder'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 340,
                      child: TextField(
                        controller: _label,
                        maxLength: DiscProject.maxLabelLength,
                        enabled: !busy,
                        decoration: InputDecoration(
                          labelText: 'Disc label',
                          errorText: labelError,
                          counterText: '',
                          prefixIcon: const Icon(Icons.label_outline, size: 18),
                        ),
                        onChanged: ref.read(projectProvider.notifier).setLabel,
                      ),
                    ),
                    const Spacer(),
                    if (!project.isEmpty)
                      TextButton.icon(
                        onPressed: busy ? null : ref.read(projectProvider.notifier).clear,
                        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                        label: const Text('Clear'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 0),
                  child: DropTarget(
                    enable: !busy,
                    onDragEntered: (_) => setState(() => _dragging = true),
                    onDragExited: (_) => setState(() => _dragging = false),
                    onDragDone: (d) {
                      setState(() => _dragging = false);
                      ref.read(projectProvider.notifier).addPaths(d.files.map((f) => f.path));
                    },
                    child: DropSurface(
                      active: _dragging,
                      child: project.isEmpty
                          ? _EmptyDrop(
                              onAddFiles: busy ? null : _addFiles,
                              onAddFolder: busy ? null : _addFolders,
                            )
                          : _EntryTable(
                              entries: project.entries,
                              busy: busy,
                              onRename: _rename,
                              onRemove: ref.read(projectProvider.notifier).remove,
                            ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 12, 28, 20),
                child: Text(
                  project.isEmpty
                      ? 'Tip: drop files straight onto this window.'
                      : '${_plural(project.entries.length, 'item')} · ${_plural(project.totalFiles, 'file')}'
                            ' · ${formatBytes(project.totalBytes)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        SidePanel(
          children: [
            DiscSummary(
              neededBlocks: project.isEmpty ? 0 : project.estimatedBlocks,
              estimating: project.sizing,
            ),
            const SizedBox(height: 20),
            const SectionLabel('Options'),
            const BurnOptionsPanel(),
            const SizedBox(height: 20),
            BurnButton(
              label: opts.simulate ? 'Simulate burn' : 'Burn',
              onPressed: busy || burnBlocker != null ? null : _burn,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: busy || contentBlocker != null || ref.watch(xorrisoProvider) == null
                  ? null
                  : _saveIso,
              icon: const Icon(Icons.save_alt, size: 18),
              label: const Text('Save as ISO image…'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            ),
            BlockedReason(burnBlocker),
          ],
        ),
      ],
    );
  }
}

String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

class _EmptyDrop extends StatelessWidget {
  final VoidCallback? onAddFiles;
  final VoidCallback? onAddFolder;

  const _EmptyDrop({this.onAddFiles, this.onAddFolder});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = DiscColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(shape: BoxShape.circle, color: colors.laserSoft),
            child: Icon(Icons.file_download_outlined, size: 36, color: colors.laser),
          ),
          const SizedBox(height: 18),
          Text('Drop files and folders here', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'They keep their names and folder structure on the disc.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(onPressed: onAddFiles, child: const Text('Browse files')),
              const SizedBox(width: 4),
              TextButton(onPressed: onAddFolder, child: const Text('Browse folders')),
            ],
          ),
        ],
      ),
    );
  }
}

class _EntryTable extends StatelessWidget {
  final List<DiscEntry> entries;
  final bool busy;
  final void Function(DiscEntry) onRename;
  final void Function(String) onRemove;

  const _EntryTable({
    required this.entries,
    required this.busy,
    required this.onRename,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Row(
            children: [
              Expanded(child: Text('NAME ON DISC', style: muted)),
              SizedBox(
                width: 110,
                child: Text('CONTENTS', style: muted, textAlign: TextAlign.right),
              ),
              SizedBox(
                width: 100,
                child: Text('SIZE', style: muted, textAlign: TextAlign.right),
              ),
              const SizedBox(width: 44),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const Divider(indent: 20, endIndent: 20),
            itemBuilder: (_, i) => _EntryRow(
              entry: entries[i],
              busy: busy,
              onRename: () => onRename(entries[i]),
              onRemove: () => onRemove(entries[i].sourcePath),
            ),
          ),
        ),
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  final DiscEntry entry;
  final bool busy;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  const _EntryRow({required this.entry, required this.busy, required this.onRename, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = DiscColors.of(context);
    final e = entry;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    final numeric = theme.textTheme.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

    return InkWell(
      onTap: busy ? null : onRename,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: e.isDirectory ? colors.laserSoft : scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                e.isDirectory ? Icons.folder_rounded : Icons.insert_drive_file_outlined,
                size: 19,
                color: e.isDirectory ? colors.laser : scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.name,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(e.sourcePath, overflow: TextOverflow.ellipsis, style: muted),
                ],
              ),
            ),
            SizedBox(
              width: 110,
              child: Text(
                e.isDirectory ? (e.bytes == null ? '…' : _plural(e.fileCount, 'item')) : 'File',
                textAlign: TextAlign.right,
                style: muted,
              ),
            ),
            SizedBox(
              width: 100,
              child: e.bytes == null
                  ? const Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox.square(
                        dimension: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                    )
                  : Text(formatBytes(e.bytes!), textAlign: TextAlign.right, style: numeric),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Remove from disc',
              onPressed: busy ? null : onRemove,
              iconSize: 18,
              icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
