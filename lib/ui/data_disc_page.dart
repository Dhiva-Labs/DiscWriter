import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../burn/models.dart';
import '../burn/plans.dart';
import '../project/disc_project.dart';
import '../state/providers.dart';
import 'job_dialog.dart';
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
          child: TextField(
            controller: controller,
            autofocus: true,
            onSubmitted: (v) => Navigator.pop(c, v),
          ),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(problem ?? 'Another item on the disc is already called "${name.trim()}"'),
      ));
    }
  }

  Future<void> _saveIso() async {
    final project = ref.read(projectProvider);
    final location = await getSaveLocation(
      suggestedName: '${project.label.replaceAll(RegExp(r'[/\\]'), '_')}.iso',
      acceptedTypeGroups: const [XTypeGroup(label: 'Disc image', extensions: ['iso'])],
      confirmButtonText: 'Save',
    );
    if (location == null || !mounted) return;
    var path = location.path;
    if (!path.toLowerCase().endsWith('.iso')) path = '$path.iso';
    await runJobWithDialog(context, ref, 'Saving "${project.label}" as an image',
        buildIsoPlan(project, path), destructiveCancel: false);
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
    await runJobWithDialog(context, ref, '$verb "${project.label}"',
        burnProjectPlan(x, project, drive, media, opts));
  }

  Future<bool?> _confirmErase(MediaInfo media) => showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Erase the disc first?'),
          content: Text('Everything on this ${media.profile ?? 'disc'}'
              '${media.volumeId == null ? '' : ' ("${media.volumeId}")'} will be erased '
              'before writing.'),
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
    final media = ref.watch(mediaProvider).valueOrNull;
    final busy = ref.watch(jobProvider.select((j) => j != null && !j.finished));
    final theme = Theme.of(context);
    final labelError = validateLabel(project.label);
    final tooBig = project.estimatedBlocks > capacity;
    final usingPreset = media == null || !media.present || media.family == DiscFamily.file;

    final contentBlocker = project.isEmpty
        ? 'Add files or folders'
        : labelError != null
            ? 'Fix the disc label'
            : project.sizing
                ? 'Still measuring…'
                : null;
    final burnBlocker = contentBlocker ??
        driveBlocker(ref) ??
        (tooBig ? 'Too much data for this disc' : null);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 300,
                      child: TextField(
                        controller: _label,
                        maxLength: DiscProject.maxLabelLength,
                        enabled: !busy,
                        decoration: InputDecoration(
                          labelText: 'Disc label',
                          errorText: labelError,
                          counterText: '',
                        ),
                        onChanged: ref.read(projectProvider.notifier).setLabel,
                      ),
                    ),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: busy ? null : _addFiles,
                      icon: const Icon(Icons.note_add_outlined),
                      label: const Text('Add files'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: busy ? null : _addFolders,
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: const Text('Add folder'),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Remove everything',
                      onPressed: busy || project.isEmpty ? null : ref.read(projectProvider.notifier).clear,
                      icon: const Icon(Icons.clear_all),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: DropTarget(
                    enable: !busy,
                    onDragEntered: (_) => setState(() => _dragging = true),
                    onDragExited: (_) => setState(() => _dragging = false),
                    onDragDone: (d) {
                      setState(() => _dragging = false);
                      ref.read(projectProvider.notifier).addPaths(d.files.map((f) => f.path));
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _dragging ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                          width: _dragging ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        color: _dragging ? theme.colorScheme.primary.withValues(alpha: 0.06) : null,
                      ),
                      child: project.isEmpty
                          ? const _EmptyDrop()
                          : _EntryList(
                              entries: project.entries,
                              busy: busy,
                              onRename: _rename,
                              onRemove: ref.read(projectProvider.notifier).remove,
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text('${project.entries.length} item${project.entries.length == 1 ? '' : 's'}'
                        ' · ${project.totalFiles} file${project.totalFiles == 1 ? '' : 's'}'
                        ' · ${formatBytes(project.totalBytes)}',
                        style: theme.textTheme.bodySmall),
                    const Spacer(),
                    if (usingPreset)
                      DropdownButton<CapacityPreset>(
                        value: ref.watch(capacityPresetProvider),
                        isDense: true,
                        underline: const SizedBox.shrink(),
                        style: theme.textTheme.bodySmall,
                        onChanged: (p) => ref.read(capacityPresetProvider.notifier).state = p!,
                        items: [
                          for (final p in CapacityPreset.values)
                            DropdownMenuItem(value: p, child: Text('Size for ${p.label}')),
                        ],
                      )
                    else
                      Text('Free on disc: ${formatBlocks(capacity)}', style: theme.textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 6),
                CapacityBar(
                  usedBlocks: project.isEmpty ? 0 : project.estimatedBlocks,
                  capacityBlocks: capacity,
                  estimating: project.sizing,
                ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        SizedBox(
          width: 320,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BurnOptionsPanel(),
                if (media != null && media.appendable && !media.blank && !ref.watch(burnOptionsProvider).eraseFirst) ...[
                  const SizedBox(height: 8),
                  Text(
                    'This disc already holds ${media.sessions} session${media.sessions == 1 ? '' : 's'}. '
                    'The new files are added alongside the existing ones.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: busy || burnBlocker != null ? null : _burn,
                  icon: const Icon(Icons.local_fire_department_outlined),
                  label: Text(ref.watch(burnOptionsProvider).simulate ? 'Simulate burn' : 'Burn'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: busy || contentBlocker != null || ref.watch(xorrisoProvider) == null
                      ? null
                      : _saveIso,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Save as ISO image…'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                ),
                const SizedBox(height: 10),
                BlockedReason(burnBlocker),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyDrop extends StatelessWidget {
  const _EmptyDrop();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.move_to_inbox_outlined, size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text('Drop files and folders here', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('or use Add files / Add folder', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _EntryList extends StatelessWidget {
  final List<DiscEntry> entries;
  final bool busy;
  final void Function(DiscEntry) onRename;
  final void Function(String) onRemove;

  const _EntryList({
    required this.entries,
    required this.busy,
    required this.onRename,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 56),
      itemBuilder: (_, i) {
        final e = entries[i];
        final size = e.bytes == null
            ? 'measuring…'
            : e.isDirectory
                ? '${formatBytes(e.bytes!)} · ${e.fileCount} item${e.fileCount == 1 ? '' : 's'}'
                : formatBytes(e.bytes!);
        return ListTile(
          leading: Icon(e.isDirectory ? Icons.folder : Icons.insert_drive_file_outlined,
              color: e.isDirectory ? theme.colorScheme.primary : null),
          title: Text(e.name, overflow: TextOverflow.ellipsis),
          subtitle: Text(e.sourcePath, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
          onTap: busy ? null : () => onRename(e),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(size, style: theme.textTheme.bodySmall),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Remove from disc',
                onPressed: busy ? null : () => onRemove(e.sourcePath),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        );
      },
    );
  }
}
