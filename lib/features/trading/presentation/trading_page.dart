import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:interactive_chart/interactive_chart.dart';
import '../../trading/data/market_service.dart';
import '../../trading/data/portfolio_provider.dart';
import '../../trading/domain/models/market_asset.dart';
import '../../trading/domain/models/open_position.dart';
import '../../gamification/user_stats_provider.dart';

class TradingPage extends ConsumerStatefulWidget {
  final MarketAsset asset;

  const TradingPage({super.key, required this.asset});

  @override
  ConsumerState<TradingPage> createState() => _TradingPageState();
}

class _TradingPageState extends ConsumerState<TradingPage> {
  String _selectedInterval = '1H';
  List<CandleData> _candles = [];
  bool _isLoading = true;

  final _quantityController = TextEditingController(text: '1');
  double _quantity = 1.0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(marketServiceProvider);
      final history =
          await service.getAssetHistory(widget.asset.id, _selectedInterval);
      setState(() {
        _candles = history
            .map((h) => CandleData(
                  timestamp: h.timestamp,
                  open: h.open,
                  close: h.close,
                  high: h.high,
                  low: h.low,
                  volume: h.volume,
                ))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // ─── Order Execution ────────────────────────────────────────────────────────

  void _onBuy() {
    final qty = double.tryParse(_quantityController.text.trim()) ?? 0;
    if (qty <= 0) {
      _showSnack('Enter a valid quantity', Colors.orange);
      return;
    }
    final price = widget.asset.currentPrice; // Already in INR
    final cost = price * qty;

    final notifier = ref.read(userStatsProvider.notifier);
    final success = notifier.deductFuel(cost);

    if (!success) {
      final balance = ref.read(userStatsProvider).tradingCredits;
      _showSnack(
        'Insufficient FUEL — need ₹${cost.toStringAsFixed(2)}, have ₹${balance.toStringAsFixed(2)}',
        Colors.redAccent,
      );
      return;
    }

    ref.read(portfolioProvider.notifier).openPosition(
          OpenPosition(
            assetId: widget.asset.id,
            assetSymbol: widget.asset.symbol,
            assetName: widget.asset.name,
            entryPrice: price,
            quantity: qty,
            isLong: true,
            openedAt: DateTime.now(),
          ),
        );

    _showSnack(
      'LONG ${qty.toStringAsFixed(2)} ${widget.asset.symbol} @ ₹${price.toStringAsFixed(2)}',
      Colors.tealAccent,
    );
  }

  void _onSell() {
    final portfolio = ref.read(portfolioProvider.notifier);
    final existing = portfolio.getPosition(widget.asset.id);

    if (existing == null) {
      _showSnack('No open position for ${widget.asset.symbol}', Colors.orange);
      return;
    }

    final currentPrice = widget.asset.currentPrice;
    final pnl = portfolio.closePosition(widget.asset.id, currentPrice);
    if (pnl == null) return;

    // Return capital + P&L to FUEL wallet
    ref.read(userStatsProvider.notifier).addFuel(existing.totalCost + pnl);

    final pnlSign = pnl >= 0 ? '+' : '';
    final pnlColor = pnl >= 0 ? Colors.greenAccent : Colors.redAccent;
    _showSnack(
      'Position closed — P&L: $pnlSign₹${pnl.toStringAsFixed(2)}',
      pnlColor,
    );
  }

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.shareTechMono(color: Colors.black, fontSize: 13),
        ),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(userStatsProvider);
    final openPosition = ref.watch(portfolioProvider.notifier).getPosition(widget.asset.id);
    final hasPosition = openPosition != null;
    final unrlPnl = hasPosition
        ? openPosition.unrealizedPnl(widget.asset.currentPrice)
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0E14),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.asset.symbol,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
            Text(
              '₹${widget.asset.currentPrice.toStringAsFixed(2)}',
              style: TextStyle(
                color: widget.asset.percentChange24h >= 0
                    ? Colors.greenAccent
                    : Colors.redAccent,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [_buildIntervalSelector()],
      ),
      body: Column(
        children: [
          // Chart
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF00D9FF)))
                : InteractiveChart(
                    candles: _candles,
                    style: ChartStyle(
                      priceGainColor: Colors.greenAccent,
                      priceLossColor: Colors.redAccent,
                      volumeColor: Colors.white.withOpacity(0.2),
                      priceGridLineColor: Colors.white10,
                      timeLabelStyle: const TextStyle(
                          color: Colors.white54, fontSize: 10),
                      priceLabelStyle: const TextStyle(
                          color: Colors.white54, fontSize: 10),
                      overlayBackgroundColor:
                          Colors.black.withOpacity(0.8),
                    ),
                  ),
          ),

          // Trade Panel
          _buildTradePanel(stats.tradingCredits, hasPosition, unrlPnl),
        ],
      ),
    );
  }

  Widget _buildIntervalSelector() {
    final intervals = ['1H', '4H', '1D', '1W'];
    return Row(
      children: intervals.map((interval) {
        final isSelected = _selectedInterval == interval;
        return GestureDetector(
          onTap: () {
            setState(() => _selectedInterval = interval);
            _loadHistory();
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF00D9FF).withOpacity(0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF00D9FF)
                    : Colors.transparent,
              ),
            ),
            child: Text(
              interval,
              style: TextStyle(
                color: isSelected
                    ? const Color(0xFF00D9FF)
                    : Colors.white54,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTradePanel(
      double fuelBalance, bool hasPosition, double? unrlPnl) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF151A21),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Quantity row ──
          Row(
            children: [
              Text('QTY',
                  style: GoogleFonts.orbitron(
                      color: Colors.white54, fontSize: 11)),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _quantityController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d*'))
                  ],
                  style: GoogleFonts.shareTechMono(
                      color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(
                          color: Color(0xFF00D9FF)),
                    ),
                    hintText: '0.00',
                    hintStyle: const TextStyle(color: Colors.white24),
                  ),
                  onChanged: (v) =>
                      setState(() => _quantity = double.tryParse(v) ?? 0),
                ),
              ),
              const SizedBox(width: 10),
              // Cost preview
              Text(
                '≈ ₹${(widget.asset.currentPrice * _quantity).toStringAsFixed(2)}',
                style: GoogleFonts.shareTechMono(
                    color: Colors.white38, fontSize: 11),
              ),
            ],
          ),

          // ── Open position badge ──
          if (hasPosition && unrlPnl != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (unrlPnl >= 0 ? Colors.green : Colors.red)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: (unrlPnl >= 0 ? Colors.green : Colors.red)
                        .withOpacity(0.4),
                  ),
                ),
                child: Text(
                  'OPEN POSITION · Unrealized P&L: '
                  '${unrlPnl >= 0 ? "+" : ""}₹${unrlPnl.toStringAsFixed(2)}',
                  style: GoogleFonts.shareTechMono(
                    color: unrlPnl >= 0 ? Colors.green : Colors.red,
                    fontSize: 11,
                  ),
                ),
              ),
            ),

          const SizedBox(height: 10),

          // ── BUY / SELL buttons ──
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  label: 'BUY',
                  color: Colors.green,
                  onPressed: _onBuy,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildActionButton(
                  label: hasPosition ? 'CLOSE POSITION' : 'SELL',
                  color: Colors.red,
                  onPressed: _onSell,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ── Balance ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'FUEL BALANCE',
                style: GoogleFonts.orbitron(
                    color: Colors.white24, fontSize: 9),
              ),
              Text(
                '₹${fuelBalance.toStringAsFixed(2)}',
                style: GoogleFonts.shareTechMono(
                    color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.2),
        foregroundColor: color,
        side: BorderSide(color: color),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
    );
  }
}
