import 'package:flutter/material.dart';

class WalletCreationScreen extends StatelessWidget {
  const WalletCreationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Kreiraj novi wallet')),
      body: Center(
        child: Text('Setup flow dolazi uskoro', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.8))),
      ),
    );
  }
}
