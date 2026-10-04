import 'dart:async';

import 'package:flutter/material.dart';

import '../cleaning/cleaning_controller.dart';
import '../cleaning/droplet_physics.dart';
import '../cleaning/program_generator.dart';
import 'about_sheet.dart';
import 'program_timeline.dart';
import 'stage_style.dart';
import 'waveform_scope.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final CleaningController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  StreamSubscription<String>? _notices;

  @override
  void initState() {
    super.initState();
    _notices = widget.controller.notices.listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    });
  }

  @override
  void dispose() {
    _notices?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Ultrasonic'),
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: 'How it works',
              onPressed: () => showAboutSheet(context),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _ReadinessCard(controller: c),
            const SizedBox(height: 16),
            _ModePicker(controller: c),
            const SizedBox(height: 16),
            _ProgramCard(controller: c),
            const SizedBox(height: 16),
            _SettingsCard(controller: c),
          ],
        ),
        bottomNavigationBar: _StartBar(controller: c),
      ),
    );
  }
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({required this.controller});

  final CleaningController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = controller.status;

    final rows = <Widget>[];
    if (!controller.engineAvailable) {
      rows.add(
        _InfoRow(
          icon: Icons.phone_iphone,
          color: scheme.error,
          text:
              'Playback needs an iPhone. You can still browse programs here, '
              'or export one with tool/render_wav.dart.',
        ),
      );
    } else if (status != null) {
      final volume = status.outputVolume;
      final loud = volume >= 0.95;
      rows.add(
        Row(
          children: [
            Icon(
              loud ? Icons.volume_up : Icons.volume_down,
              color: loud ? scheme.primary : scheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Volume ${(volume * 100).round()}%'),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: volume,
                    color: loud ? scheme.primary : scheme.error,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
      if (!loud) {
        rows.add(
          Padding(
            padding: const EdgeInsets.only(left: 36, top: 4),
            child: Text(
              'Turn the volume all the way up with the side buttons. '
              'Apps are not allowed to change it.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
        );
      }
      rows.add(const SizedBox(height: 12));
      rows.add(
        status.route.isBuiltIn
            ? _InfoRow(
                icon: Icons.speaker_phone,
                color: scheme.primary,
                text: 'Playing through the iPhone speakers',
              )
            : _InfoRow(
                icon: Icons.headphones,
                color: scheme.error,
                text:
                    'Headphones or Bluetooth connected. Disconnect them so '
                    'the tones go to the phone\'s own speakers.',
              ),
      );
    }

    rows.add(const SizedBox(height: 12));
    rows.add(
      _InfoRow(
        icon: Icons.south,
        color: scheme.onSurfaceVariant,
        text:
            'Take the case off. Point the bottom edge (the speaker grille) '
            'down so gravity helps the water out.',
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: rows),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: color),
      const SizedBox(width: 12),
      Expanded(child: Text(text)),
    ],
  );
}

class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.controller});

  final CleaningController controller;

  @override
  Widget build(BuildContext context) {
    final mode = controller.options.mode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<CleaningMode>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            for (final m in CleaningMode.values)
              ButtonSegment(
                value: m,
                // Scale down rather than wrap on 320 pt wide phones.
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(m.label, maxLines: 1),
                ),
              ),
          ],
          selected: {mode},
          onSelectionChanged: controller.isRunning
              ? null
              : (s) => controller.setMode(s.single),
        ),
        const SizedBox(height: 8),
        Text(
          mode.description,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _ProgramCard extends StatelessWidget {
  const _ProgramCard({required this.controller});

  final CleaningController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final program = controller.program;
    final running = controller.isRunning;
    final position = controller.position;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Program', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  running
                      ? '${formatClock(position)} / '
                            '${formatClock(program.duration)}'
                      : formatClock(program.duration),
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ProgramTimeline(
              program: program,
              position: position,
              showPlayhead: running,
            ),
            const SizedBox(height: 12),
            if (running)
              _NowPlaying(program: program, position: position)
            else
              for (final stage in program.stages) _StageTile(stage: stage),
          ],
        ),
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.program, required this.position});

  final CleaningProgram program;
  final double position;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stage = program.stages[program.stageIndexAt(position)];
    final hz = program.tones.frequencyAt(position);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _Dot(color: stageColor(stage.kind)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(stage.title, style: theme.textTheme.titleSmall),
            ),
            Text(
              hz == null ? 'pause' : formatHz(hz),
              style: theme.textTheme.titleMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        WaveformScope(program: program, position: position, active: true),
        const SizedBox(height: 8),
        Text(stage.detail, style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        LinearProgressIndicator(
          value: program.duration > 0 ? position / program.duration : 0,
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _StageTile extends StatelessWidget {
  const _StageTile({required this.stage});

  final ProgramStage stage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      dense: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 20, bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      shape: const Border(),
      leading: _Dot(color: stageColor(stage.kind)),
      title: Text(stage.title),
      trailing: Text(
        '${formatClock(stage.start)} · ${stage.duration.toStringAsFixed(1)} s',
        style: theme.textTheme.labelSmall,
      ),
      children: [Text(stage.detail, style: theme.textTheme.bodySmall)],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.controller});

  final CleaningController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final o = controller.options;
    final locked = controller.isRunning;
    final dropMm = rayleighRadius(o.ejectionHz) * 1000;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text('High-frequency stages'),
              subtitle: Text(
                '${formatHz(microLowHz)}–${formatHz(microHighHz)} '
                'micro-droplet sweep and '
                '${formatHz(nearUltrasonicLowHz)}–'
                '${formatHz(o.nearUltrasonicHighHz)} near-ultrasonic warble',
              ),
              value: o.highFrequencyStages,
              onChanged: locked ? null : controller.setHighFrequencyStages,
            ),
            _SliderTile(
              label: 'Ejection frequency',
              value:
                  '${o.ejectionHz.round()} Hz · ~${dropMm.toStringAsFixed(2)} '
                  'mm drops',
              slider: Slider(
                min: 140,
                max: 200,
                divisions: 60,
                value: o.ejectionHz,
                label: '${o.ejectionHz.round()} Hz',
                onChanged: locked ? null : controller.setEjectionHz,
              ),
            ),
            _SliderTile(
              label: 'Intensity',
              value: '${(o.intensity * 100).round()}%',
              slider: Slider(
                min: 0.5,
                max: 1,
                divisions: 10,
                value: o.intensity,
                label: '${(o.intensity * 100).round()}%',
                onChanged: locked ? null : controller.setIntensity,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Variation #${controller.seed}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: locked ? null : controller.shuffle,
                    icon: const Icon(Icons.shuffle),
                    label: const Text('New variation'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.label,
    required this.value,
    required this.slider,
  });

  final String label;
  final String value;
  final Widget slider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          slider,
        ],
      ),
    );
  }
}

class _StartBar extends StatelessWidget {
  const _StartBar({required this.controller});

  final CleaningController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final routeOk = c.status?.route.isBuiltIn ?? true;
    final canStart = c.engineAvailable && routeOk && !c.isBusy;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 56,
          child: c.isRunning
              ? FilledButton.tonalIcon(
                  onPressed: c.stop,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop'),
                )
              : FilledButton.icon(
                  onPressed: canStart ? c.start : null,
                  icon: const Icon(Icons.graphic_eq),
                  label: Text(
                    'Start cleaning · ${formatClock(c.program.duration)}',
                  ),
                ),
        ),
      ),
    );
  }
}
