import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../burn/commands.dart';
import '../burn/models.dart';
import '../burn/plans.dart';
import '../state/providers.dart';
import 'job_dialog.dart';
import 'widgets.dart';

class ErasePage extends ConsumerStatefulWidget {
  const ErasePage({super.key});

  @override
  ConsumerState<ErasePage> createState() => _ErasePageState();
}

class _ErasePageState extends ConsumerState<ErasePage> {
  var _mode = BlankMode.fast;

  Future<void> _erase(MediaInfo media) async {
    final drive = ref.read(selectedDriveProvider)!;
    final simulate = ref.read(burnOptionsProvider).simulate;
    if (!simulate) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Erase this disc?'),
          content: Text('Everything on the ${media.profile ?? 'disc'}'
              '${media.volumeId == null ? '' : ' "${media.volumeId}"'} will be lost.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Erase'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    await runJobWithDialog(
      context,
      ref,
      simulate ? 'Simulating erase' : 'Erasing disc',
      blankPlan(drive, _mode, simulate: simulate),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaAsync = ref.watch(mediaProvider);
    final media = mediaAsync.valueOrNull ?? MediaInfo.none;
    final busy = ref.watch(jobProvider.select((j) => j != null && !j.finished));
    final simulate = ref.watch(burnOptionsProvider).simulate;
    final theme = Theme.of(context);

    String? blocker;
    if (ref.watch(xorrisoProvider) == null) {
      blocker = 'Install xorriso to erase discs';
    } else if (ref.watch(selectedDriveProvider) == null) {
      blocker = 'No drive selected';
    } else if (mediaAsync.isLoading) {
      blocker = 'Reading the disc…';
    } else if (!media.present) {
      blocker = 'Insert a rewritable disc';
    } else if (!media.erasable) {
      blocker = '${media.profile} is write-once and cannot be erased';
    } else if (media.blank) {
      blocker = 'The disc is already blank';
    }

    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Erase a rewritable disc', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text('Works with CD-RW, DVD-RW, DVD+RW, DVD-RAM and BD-RE. '
                  'Write-once discs (CD-R, DVD±R, BD-R) cannot be erased.',
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 20),
              Card(
                child: Column(
                  children: [
                    RadioGroup<BlankMode>(
                      groupValue: _mode,
                      onChanged: (m) => setState(() => _mode = m!),
                      child: const Column(
                        children: [
                          RadioListTile(
                            value: BlankMode.fast,
                            title: Text('Quick erase'),
                            subtitle: Text('Makes the disc appear blank. Takes seconds to a minute.'),
                          ),
                          RadioListTile(
                            value: BlankMode.full,
                            title: Text('Full erase'),
                            subtitle: Text('Overwrites every sector. As slow as a full burn; '
                                'use it for a disc that misbehaves or holds private data.'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Simulate only'),
                subtitle: const Text('Run the erase with the laser off'),
                value: simulate,
                onChanged: busy
                    ? null
                    : (v) => ref.read(burnOptionsProvider.notifier).state =
                        ref.read(burnOptionsProvider).copyWith(simulate: v),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                      minimumSize: const Size(160, 44),
                    ),
                    onPressed: busy || blocker != null ? null : () => _erase(media),
                    icon: const Icon(Icons.cleaning_services),
                    label: Text(simulate ? 'Simulate erase' : 'Erase disc'),
                  ),
                  const SizedBox(width: 16),
                  if (media.present && media.dataBlocks > 0)
                    Text('${formatBlocks(media.dataBlocks)} on the disc now',
                        style: theme.textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 10),
              BlockedReason(blocker),
            ],
          ),
        ),
      ),
    );
  }
}
