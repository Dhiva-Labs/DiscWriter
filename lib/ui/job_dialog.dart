import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../burn/jobs.dart';
import '../burn/models.dart';
import '../state/providers.dart';

/// Starts a job and shows its progress dialog until the user closes it.
Future<JobState?> runJobWithDialog(
  BuildContext context,
  WidgetRef ref,
  String title,
  List<JobStep> steps, {
  bool destructiveCancel = true,
}) async {
  final jobs = ref.read(jobProvider.notifier);
  if (jobs.busy) return null;
  final future = jobs.start(title, steps);
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => JobDialog(destructiveCancel: destructiveCancel),
  );
  final result = await future;
  jobs.dismiss();
  return result;
}

class JobDialog extends ConsumerStatefulWidget {
  /// Cancelling mid-write can ruin write-once media, so ask first.
  final bool destructiveCancel;

  const JobDialog({super.key, this.destructiveCancel = true});

  @override
  ConsumerState<JobDialog> createState() => _JobDialogState();
}

class _JobDialogState extends ConsumerState<JobDialog> {
  var _showLog = false;
  final _logScroll = ScrollController();

  @override
  void dispose() {
    _logScroll.dispose();
    super.dispose();
  }

  Future<void> _cancel(JobState job) async {
    final writing = job.phase == JobPhase.writing || job.phase == JobPhase.blanking;
    if (widget.destructiveCancel && writing) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Stop now?'),
          content: const Text(
            'Stopping while the drive is writing usually leaves a write-once '
            'disc (CD-R, DVD±R, BD-R) unusable. Rewritable discs can be erased '
            'and used again.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep going')),
            FilledButton.tonal(onPressed: () => Navigator.pop(c, true), child: const Text('Stop')),
          ],
        ),
      );
      if (ok != true) return;
    }
    ref.read(jobProvider.notifier).cancel();
  }

  @override
  Widget build(BuildContext context) {
    final job = ref.watch(jobProvider);
    if (job == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (_showLog) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScroll.hasClients) _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      });
    }

    final (icon, color, headline) = switch (job.status) {
      JobStatus.running => (null, scheme.primary, job.stepLabel),
      JobStatus.succeeded => (Icons.check_circle, Colors.green.shade600, 'Done'),
      JobStatus.failed => (Icons.error, scheme.error, 'Failed'),
      JobStatus.cancelled => (Icons.cancel, scheme.onSurfaceVariant, 'Stopped'),
    };

    return PopScope(
      canPop: job.finished,
      child: AlertDialog(
        title: Row(
          children: [
            if (icon != null) ...[Icon(icon, color: color), const SizedBox(width: 10)],
            Expanded(child: Text(job.title)),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Steps(job: job),
              const SizedBox(height: 16),
              Text(headline, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              if (!job.finished) ...[
                LinearProgressIndicator(value: job.fraction, minHeight: 8,
                    borderRadius: BorderRadius.circular(4)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text(job.detail ?? '', style: theme.textTheme.bodySmall)),
                    if (job.speed != null)
                      Text('${job.speed!.toStringAsFixed(1)}x  ', style: theme.textTheme.bodySmall),
                    if (job.fraction != null)
                      Text('${(job.fraction! * 100).toStringAsFixed(0)}%',
                          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
              if (job.status == JobStatus.failed && job.error != null)
                SelectableText(job.error!, style: TextStyle(color: scheme.error)),
              if (job.status == JobStatus.succeeded && job.note != null) Text(job.note!),
              if (job.status == JobStatus.cancelled)
                const Text('The job was stopped before it finished.'),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showLog = !_showLog),
                  icon: Icon(_showLog ? Icons.expand_less : Icons.expand_more),
                  label: Text(_showLog ? 'Hide details' : 'Show details'),
                ),
              ),
              if (_showLog)
                Container(
                  height: 220,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: ListView.builder(
                    controller: _logScroll,
                    itemCount: job.log.length,
                    itemBuilder: (_, i) => Text(
                      job.log[i],
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (_showLog)
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: job.log.join('\n'))),
              child: const Text('Copy details'),
            ),
          if (job.finished)
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))
          else
            TextButton(onPressed: () => _cancel(job), child: const Text('Stop')),
        ],
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  final JobState job;

  const _Steps({required this.job});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < job.stepLabels.length; i++) ...[
          if (i > 0) Icon(Icons.chevron_right, size: 16, color: scheme.outline),
          _StepChip(
            label: job.stepLabels[i],
            done: i < job.step || job.status == JobStatus.succeeded,
            active: i == job.step && !job.finished,
            failed: i == job.step && job.status == JobStatus.failed,
          ),
        ],
      ],
    );
  }
}

class _StepChip extends StatelessWidget {
  final String label;
  final bool done, active, failed;

  const _StepChip({required this.label, required this.done, required this.active, required this.failed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = failed
        ? scheme.error
        : done
            ? Colors.green.shade600
            : active
                ? scheme.primary
                : scheme.outline;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          failed
              ? Icons.error_outline
              : done
                  ? Icons.check_circle
                  : active
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontWeight: active ? FontWeight.w600 : null)),
      ],
    );
  }
}
