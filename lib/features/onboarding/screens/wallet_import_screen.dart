import 'package:flutter/material.dart';

class WalletImportScreen extends StatelessWidget {
  const WalletImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Uvezi postojeći wallet')),
      body: Center(
        child: Text('Ekran za uvoz seed fraze dolazi uskoro', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: cs.onSurface.withValues(alpha: 0.8))),
      ),
    );
  }
}
