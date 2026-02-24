import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/user_stats_model.dart';

class UserStatsNotifier extends Notifier<UserStatsModel> {
  @override
  UserStatsModel build() {
    // Starting FUEL balance: 5000 (equal to 5000 INR of trading capital)
    return UserStatsModel(userId: 'default_user', tradingCredits: 5000.0);
  }

  void updateUserStats(UserStatsModel newStats) {
    state = newStats;
  }

  /// Deduct [amount] of FUEL (INR) from trading credits.
  /// Returns true if successful, false if insufficient funds.
  bool deductFuel(double amount) {
    if (state.tradingCredits < amount) return false;
    state = state.copyWith(tradingCredits: state.tradingCredits - amount);
    return true;
  }

  /// Add [amount] of FUEL (INR) back to trading credits (on sell / close).
  void addFuel(double amount) {
    state = state.copyWith(tradingCredits: state.tradingCredits + amount);
  }

  /// Sync FUEL with the refinery's refinedFuel (called when refinery produces fuel).
  void addRefineryFuel(double fuelAdded) {
    // 1 Refined Fuel = 10 INR of trading credits
    const double fuelToInrRate = 10.0;
    state = state.copyWith(
      tradingCredits: state.tradingCredits + (fuelAdded * fuelToInrRate),
    );
  }
}

final userStatsProvider =
    NotifierProvider<UserStatsNotifier, UserStatsModel>(() {
  return UserStatsNotifier();
});
