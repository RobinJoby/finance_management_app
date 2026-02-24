import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models/open_position.dart';

class PortfolioNotifier extends Notifier<List<OpenPosition>> {
  @override
  List<OpenPosition> build() => [];

  /// Open a new long/short position
  void openPosition(OpenPosition position) {
    state = [...state, position];
  }

  /// Close the position for [assetId]. Returns realized P&L in INR,
  /// or null if no position found.
  double? closePosition(String assetId, double currentPriceInr) {
    final index = state.indexWhere((p) => p.assetId == assetId);
    if (index == -1) return null;
    final position = state[index];
    final pnl = position.realizedPnl(currentPriceInr);
    state = [...state]..removeAt(index);
    return pnl;
  }

  /// Get the open position for [assetId], or null if none.
  OpenPosition? getPosition(String assetId) {
    try {
      return state.firstWhere((p) => p.assetId == assetId);
    } catch (_) {
      return null;
    }
  }

  /// Total unrealized P&L across all open positions, given a price lookup function.
  double totalUnrealizedPnl(double Function(String assetId) currentPriceFn) {
    return state.fold(0.0, (sum, p) => sum + p.unrealizedPnl(currentPriceFn(p.assetId)));
  }
}

final portfolioProvider =
    NotifierProvider<PortfolioNotifier, List<OpenPosition>>(() {
  return PortfolioNotifier();
});
