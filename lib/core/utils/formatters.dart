/// Formatting helpers for SOL, tokens and addresses
class Formatters {
  static const int lamportsPerSol = 1000000000; // 1e9

  static String formatSol(double sol, {int decimals = 4}) {
    final fixed = sol.toStringAsFixed(decimals);
    return 'SOL $fixed';
  }

  static String formatLamports(int lamports, {int decimals = 4}) => formatSol(lamports / lamportsPerSol, decimals: decimals);

  static String shortAddress(String address, {int head = 4, int tail = 4}) {
    if (address.length <= head + tail) return address;
    return '${address.substring(0, head)}…${address.substring(address.length - tail)}';
  }

  static String formatToken(double amount, {required int tokenDecimals, String symbol = ''}) {
    final fixed = amount.toStringAsFixed(tokenDecimals.clamp(0, 9));
    return symbol.isEmpty ? fixed : '$symbol $fixed';
  }
}
