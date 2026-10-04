import 'package:flutter/material.dart';

Future<void> showAboutSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.75,
    maxChildSize: 0.95,
    builder: (context, controller) => ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: const [_About()],
    ),
  ),
);

class _About extends StatelessWidget {
  const _About();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget h(String s) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 6),
      child: Text(s, style: text.titleMedium),
    );
    Widget p(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(s, style: text.bodyMedium),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How it works', style: text.headlineSmall),
        h('Low frequencies do the pushing'),
        p(
          'At the same loudness, a speaker cone moves 1/f² as far: a 165 Hz '
          'tone moves the diaphragm roughly 15,000 times further than 20 kHz '
          'does. That motion pumps air through the grille and shoves water '
          'out. 165 Hz is the tone the Sonic app, the "Water Eject" shortcut '
          'and Apple Watch-style ejectors settled on.',
        ),
        h('Droplets have their own resonances'),
        p(
          'Rayleigh\'s formula for a vibrating drop gives about 165 Hz for a '
          '0.8 mm drop, 480 Hz for 0.4 mm, and 1–11 kHz for the 50–200 µm '
          'beads stuck in the mesh. The resonance sweep and micro-droplet '
          'sweep cover those bands, so whichever drop is in there gets shaken '
          'at its own frequency.',
        ),
        h('Pauses help'),
        p(
          'Apple Watch Water Lock runs, pauses and runs again because each '
          'push also draws some water back in. The pauses between bursts let '
          'water pool at the grille before the next push.',
        ),
        h('Why not true ultrasonic?'),
        p(
          'iPhone audio runs at 48 kHz, so nothing above 24 kHz can come out '
          'at all, and the speaker\'s output falls off sharply above about '
          '20 kHz. Ultrasonic cleaners work by cavitation at 20–40 kHz in a '
          'liquid bath, driven by piezo transducers at tens to hundreds of '
          'watts. A phone speaker in air cannot do that. The near-ultrasonic '
          'stage (17–20 kHz) is the highest the hardware goes; it is a '
          'finishing pass, not the main event.',
        ),
        h('Every run is different'),
        p(
          'The seed changes the burst frequencies, lengths, drive, pauses and '
          'pulse rates. A drop that sits at a quiet spot for one frequency '
          'will not sit there for all of them.',
        ),
        h('Safety'),
        p(
          'The program will not play through headphones or Bluetooth, and '
          'stops if one connects. The iPhone\'s amplifier limits speaker '
          'excursion and coil temperature itself. If it is still muffled '
          'after two runs, stop and let it dry: speaker side down on a '
          'lint-free cloth. Do not put anything into the openings, and do not '
          'charge while the port is wet. Lint packed into the grille needs a '
          'dry, soft brush.',
        ),
      ],
    );
  }
}
