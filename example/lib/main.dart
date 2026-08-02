import 'package:engage_flutter/engage_flutter.dart';
import 'package:flutter/material.dart';

const engageAppKey = String.fromEnvironment('ENGAGE_APP_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (engageAppKey.isNotEmpty) {
    await Engage.start(config: const EngageConfig(appKey: engageAppKey));
  }
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Engage Flutter',
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: const ExampleHome(),
  );
}

class ExampleHome extends StatelessWidget {
  const ExampleHome({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Engage Flutter')),
    body: StreamBuilder<String?>(
      stream: Engage.installation.id,
      initialData: Engage.installation.id.value,
      builder: (context, snapshot) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Installation: ${snapshot.data ?? 'pending'}'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: engageAppKey.isEmpty
                  ? null
                  : () => Engage.messageCenter.display(),
              child: const Text('Open Message Center'),
            ),
          ],
        ),
      ),
    ),
  );
}
