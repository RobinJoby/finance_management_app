class OpenPosition {
  final String assetId;
  final String assetSymbol;
  final String assetName;
  final double entryPrice; // Price in INR (already converted at buy time)
  final double quantity;
  final bool isLong; // true = BUY, false = SHORT
  final DateTime openedAt;

  const OpenPosition({
    required this.assetId,
    required this.assetSymbol,
    required this.assetName,
    required this.entryPrice,
    required this.quantity,
    required this.isLong,
    required this.openedAt,
  });

  /// Total capital locked (INR)
  double get totalCost => entryPrice * quantity;

  /// Live unrealized P&L against the current market price (INR)
  double unrealizedPnl(double currentPriceInr) {
    return (currentPriceInr - entryPrice) * (isLong ? 1 : -1) * quantity;
  }

  /// Realized P&L when closing at [closePriceInr]
  double realizedPnl(double closePriceInr) {
    return (closePriceInr - entryPrice) * (isLong ? 1 : -1) * quantity;
  }
}
