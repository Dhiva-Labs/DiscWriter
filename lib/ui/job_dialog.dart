import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../burn/jobs.dart';
import '../burn/models.dart';
import '../state/providers.dart';
import 'disc_gauge.dart';
import 'theme.dart';

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

  /// Fraction of the disc drawing that is "written", kept monotonic across
  /// steps so the gauge doesn't empty out when verification starts.
  double _shownProgress = 0;

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
    final colors = DiscColors.of(context);

    if (_showLog) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScroll.hasClients) _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
      });
    }

    final writing = job.phase == JobPhase.writing || job.phase == JobPhase.blanking;
    if (job.status == JobStatus.succeeded) {
      _shownProgress = 1;
    } else if (writing && job.fraction != null) {
      _shownProgress = job.fraction!;
    } else if (job.phase == JobPhase.verifying || job.phase == JobPhase.finishing) {
      _shownProgress = 1;
    }

    final (headline, headColor) = switch (job.status) {
      JobStatus.running => (job.stepLabel, scheme.onSurface),
      JobStatus.succeeded => ('Done', colors.verified),
      JobStatus.failed => ('Failed', scheme.error),
      JobStatus.cancelled => ('Stopped', scheme.onSurfaceVariant),
    };

    final centerIcon = switch (job.status) {
      JobStatus.succeeded => Icon(Icons.check_rounded, size: 34, color: colors.verified),
      JobStatus.failed => Icon(Icons.close_rounded, size: 34, color: scheme.error),
      JobStatus.cancelled => Icon(Icons.stop_rounded, size: 34, color: scheme.onSurfaceVariant),
      JobStatus.running => null,
    };

    return PopScope(
      canPop: job.finished,
      child: Dialog(
        insetPadding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 26, 28, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  job.title,
                  style: theme.textTheme.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 18),
                Center(
                  child: DiscGauge(
                    size: 190,
                    newFraction: 1,
                    progress: _shownProgress,
                    spinning: !job.finished,
                    verified: job.status == JobStatus.succeeded,
                    // Sits in the hub, which the painter keeps clear of data.
                    center:
                        centerIcon ??
                        Text(
                          job.fraction == null ? '…' : '${(job.fraction! * 100).toStringAsFixed(0)}%',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  headline,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(color: headColor),
                ),
                const SizedBox(height: 6),
                _StatusLine(job: job),
                const SizedBox(height: 18),
                _Steps(job: job),
                const SizedBox(height: 12),
                if (_showLog)
                  Container(
                    height: 200,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: ListView.builder(
                      controller: _logScroll,
                      itemCount: job.log.length,
                      itemBuilder: (_, i) => Text(
                        job.log[i],
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => setState(() => _showLog = !_showLog),
                      icon: Icon(_showLog ? Icons.expand_less : Icons.terminal, size: 18),
                      label: Text(_showLog ? 'Hide details' : 'Show details'),
                    ),
                    if (_showLog)
                      TextButton(
                        onPressed: () => Clipboard.setData(ClipboardData(text: job.log.join('\n'))),
                        child: const Text('Copy details'),
                      ),
                    const Spacer(),
                    if (job.finished)
                      FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))
                    else
                      OutlinedButton(onPressed: () => _cancel(job), child: const Text('Stop')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  final JobState job;

  const _StatusLine({required this.job});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final text = switch (job.status) {
      JobStatus.failed => job.error ?? 'Something went wrong.',
      JobStatus.succeeded => job.note ?? 'Finished.',
      JobStatus.cancelled => 'The job was stopped before it finished.',
      JobStatus.running => [
        if (job.detail != null) job.detail!,
        if (job.speed != null) '${job.speed!.toStringAsFixed(1)}x',
      ].join('  ·  '),
    };
    return SelectableText(
      text.isEmpty ? ' ' : text,
      textAlign: TextAlign.center,
      style: job.status == JobStatus.failed ? muted?.copyWith(color: scheme.error) : muted,
    );
  }
}

class _Steps extends StatelessWidget {
  final JobState job;

  const _Steps({required this.job});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = DiscColors.of(context);
    final n = job.stepLabels.length;
    return Row(
      children: [
        for (var i = 0; i < n; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.only(bottom: 22),
                color: (i <= job.step || job.status == JobStatus.succeeded)
                    ? colors.laser
                    : scheme.outlineVariant,
              ),
            ),
          _Step(
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

class _Step extends StatelessWidget {
  final String label;
  final bool done, active, failed;

  const _Step({required this.label, required this.done, required this.active, required this.failed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = DiscColors.of(context);
    final color = failed
        ? scheme.error
        : done
        ? colors.verified
        : active
        ? colors.laser
        : scheme.outline;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done || failed ? color : Colors.transparent,
            border: Border.all(color: color, width: 2),
          ),
          child: done
              ? const Icon(Icons.check, size: 13, color: Colors.white)
              : failed
              ? const Icon(Icons.close, size: 13, color: Colors.white)
              : active
              ? Center(
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: active || done || failed ? scheme.onSurface : scheme.onSurfaceVariant,
            fontWeight: active ? FontWeight.w600 : null,
          ),
        ),
      ],
    );
  }
}
