import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/providers/refinery_provider.dart';
import '../../trading/data/market_service.dart';
import '../../trading/domain/models/market_asset.dart';
import 'flight_deck_page_wickpainter.dart';
import '../../gamification/presentation/widgets/top_bar.dart';

import '../../gamification/presentation/widgets/varsity_orbit_panel.dart';
import '../../gamification/user_stats_provider.dart';
import '../../trading/data/portfolio_provider.dart';
import '../../trading/domain/models/open_position.dart';

class FlightDeckPage extends ConsumerStatefulWidget {
  const FlightDeckPage({super.key});

  @override
  ConsumerState<FlightDeckPage> createState() => _FlightDeckPageState();
}

class _FlightDeckPageState extends ConsumerState<FlightDeckPage>
    with TickerProviderStateMixin {
  late final AnimationController _fuelAnimationController;
  late final AnimationController _radarController;
  final List<Particle> _particles = [];
  Timer? _particleTimer;

  // Selection & Chart State
  MarketAsset? _selectedAsset;
  List<MockCandle> _candles = [];

  // Trade State
  TradeMode _tradeMode = TradeMode.none;
  double? _entryPrice; // Fixed price where trade started/setup
  double? _slPrice;
  double? _tpPrice;

  // Drag State
  bool _isDraggingSL = false;
  bool _isDraggingTP = false;

  // Visuals
  Offset? _cursorPos; // Crosshair cursor position

  // Zoom/Pan State
  double _candleWidth = 10.0;
  double _baseCandleWidth = 10.0;
  final double _minCandleWidth = 2.0;
  final double _maxCandleWidth = 50.0;
  double _scrollOffset = 0.0; // Index based scroll from RIGHT

  bool _isPanelExpanded = false;
  bool _showVarsityPanel = false; // NEW: Varsity Panel State
  int _selectedTabIndex = 0;

  bool _isLoadingHistory = false;
  String _selectedInterval = '1H';

  @override
  void initState() {
    super.initState();
    _fuelAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _radarController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat();

    _particleTimer = Timer.periodic(const Duration(milliseconds: 32), (timer) {
      _updateParticles();
    });
  }

  @override
  void dispose() {
    _fuelAnimationController.dispose();
    _radarController.dispose();
    _particleTimer?.cancel();
    super.dispose();
  }

  void _updateParticles() {
    setState(() {
      for (int i = 0; i < _particles.length; i++) {
        _particles[i] = Particle(
          position: _particles[i].position + _particles[i].velocity,
          velocity: _particles[i].velocity,
          color: _particles[i].color.withOpacity(
            math.max(0, _particles[i].lifetime - 0.05),
          ),
          size: _particles[i].size,
          rotation: _particles[i].rotation + 0.1,
          lifetime: _particles[i].lifetime - 0.05,
        );
      }
      _particles.removeWhere((p) => p.lifetime <= 0);
    });
  }

  void _spawnIncomingParticles() {
    final random = math.Random();
    for (int i = 0; i < 20; i++) {
      _particles.add(
        Particle(
          position: const Offset(150, 0),
          velocity: Offset(
            (random.nextDouble() - 0.5) * 5,
            2 + random.nextDouble() * 5,
          ),
          color: Colors.cyanAccent,
          size: 3 + random.nextDouble() * 3,
          rotation: random.nextDouble() * math.pi * 2,
          lifetime: 1.0,
        ),
      );
    }
  }

  Future<void> _loadHistory(MarketAsset asset) async {
    setState(() {
      _isLoadingHistory = true;
      _candles = [];
    });
    try {
      final service = ref.read(marketServiceProvider);
      final history = await service.getAssetHistory(
        asset.id,
        _selectedInterval,
      );
      if (mounted) {
        setState(() {
          _candles = history;
          _isLoadingHistory = false;
          _resetTrade();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  void _onAssetSelected(MarketAsset asset) {
    if (_selectedAsset?.id == asset.id) return;
    setState(() {
      _selectedAsset = asset;
      _resetTrade();
    });
    _loadHistory(asset);
  }

  void _resetTrade() {
    _tradeMode = TradeMode.none;
    _entryPrice = null;
    _slPrice = null;
    _tpPrice = null;
  }

  void _showSectorModal(
    BuildContext context,
    List<MarketAsset> allAssets,
    String sectorName,
    Color sectorColor,
    List<AssetSubType> allowedTypes,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => _DataPadModal(
            assets:
                allAssets
                    .where(
                      (a) =>
                          allowedTypes.contains(a.subType) ||
                          (sectorName == "SECTOR B" &&
                              (a.type == AssetType.thruster ||
                                  a.type == AssetType.fleet)),
                    )
                    .toList(),
            sectorName: sectorName,
            sectorColor: sectorColor,
            allowedTypes: allowedTypes,
            onAssetSelected: (asset) {
              Navigator.pop(context);
              _onAssetSelected(asset);
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final system = ref.watch(refineryProvider);
    final assetsAsync = ref.watch(marketAssetsProvider);

    ref.listen(refineryProvider, (previous, next) {
      if (next.refinedFuel > (previous?.refinedFuel ?? 0)) {
        _spawnIncomingParticles();
        _fuelAnimationController.forward(from: 0.0);
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: SciFiBackgroundPainter()),
          ),

          // Main Content
          Column(
            children: [
              TopBar(
                title: "FLIGHT DECK",
                onVarsityToggle:
                    () =>
                        setState(() => _showVarsityPanel = !_showVarsityPanel),
              ),
              Expanded(flex: 8, child: _buildTelemetryPanel()),
              SizedBox(
                height: 80,
                child: assetsAsync.when(
                  data: (assets) => _buildControlDock(context, assets),
                  loading:
                      () => const Center(
                        child: CircularProgressIndicator(color: Colors.cyan),
                      ),
                  error: (_, __) => const SizedBox(),
                ),
              ),
            ],
          ),

          ..._particles.map(
            (p) => Positioned(
              left: p.position.dx + MediaQuery.of(context).size.width / 2,
              top: p.position.dy + 100,
              child: _buildParticle(p),
            ),
          ),

          // Varsity Overlay
          if (_showVarsityPanel)
            VarsityOrbitPanel(
              onClose: () => setState(() => _showVarsityPanel = false),
            ),

          // Chat Overlay
          const BotChatPanel(),
        ],
      ),
    );
  }

  Widget _buildTelemetryPanel() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        border: Border.all(color: Colors.cyan.withOpacity(0.3)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.cyan.withOpacity(0.1), Colors.black.withOpacity(0.8)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 8,
            left: 8,
            child: Text(
              "SYS.MONITOR // ONLINE",
              style: GoogleFonts.shareTechMono(
                color: Colors.cyan.withOpacity(0.5),
                fontSize: 10,
              ),
            ),
          ),

          if (_selectedAsset == null)
            _buildEmptyState()
          else
            _buildChartState(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _radarController,
            builder: (context, child) {
              return Container(
                width: 100 + _radarController.value * 200,
                height: 100 + _radarController.value * 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.cyan.withOpacity(
                      (1.0 - _radarController.value) * 0.5,
                    ),
                    width: 2,
                  ),
                ),
              );
            },
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.cyan.withOpacity(0.5)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.radar, color: Colors.cyan, size: 32),
                const SizedBox(height: 8),
                Text(
                  "ACTIVE ASSET TELEMETRY",
                  style: GoogleFonts.orbitron(
                    color: Colors.cyan,
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                Text(
                  "Select Sector to Initialize...",
                  style: GoogleFonts.shareTechMono(
                    color: Colors.white54,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleZoom(double scaleFactor, Offset focalPoint, double chartWidth) {
    final double oldWidth = _candleWidth;
    final double newWidth = (_baseCandleWidth * scaleFactor).clamp(
      _minCandleWidth,
      _maxCandleWidth,
    );

    if (oldWidth == newWidth) return;

    // Focal Point Logic (Keep candle under mouse stationary)
    // _scrollOffset is distance from RIGHT (end).
    // Pixels from right = chartWidth - focalPoint.dx
    final double pixelsFromRight = chartWidth - focalPoint.dx;

    // Math: _scrollOffset_new = _scrollOffset_old + (pixelsFromRight) * (1/old - 1/new)
    final double scrollDelta = pixelsFromRight * (1 / oldWidth - 1 / newWidth);

    setState(() {
      _candleWidth = newWidth;
      _scrollOffset += scrollDelta;
    });
  }

  void _handleScrollZoom(double delta, Offset focalPoint, double chartWidth) {
    final double oldWidth = _candleWidth;
    final double newWidth = (_candleWidth - delta / 20).clamp(
      _minCandleWidth,
      _maxCandleWidth,
    );

    if (oldWidth == newWidth) return;

    final double pixelsFromRight = chartWidth - focalPoint.dx;
    final double scrollDelta = pixelsFromRight * (1 / oldWidth - 1 / newWidth);

    setState(() {
      _candleWidth = newWidth;
      _scrollOffset += scrollDelta;
    });
  }

  Widget _buildChartState() {
    if (_isLoadingHistory) {
      return const Center(child: CircularProgressIndicator(color: Colors.cyan));
    }
    if (_candles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.signal_wifi_off, color: Colors.cyan, size: 32),
            const SizedBox(height: 16),
            Text(
              "WAITING FOR TELEMETRY...",
              style: GoogleFonts.orbitron(color: Colors.cyan, letterSpacing: 2),
            ),
          ],
        ),
      );
    }

    final double panelHeight = _isPanelExpanded ? 300.0 : 45.0;

    return Stack(
      children: [
        Column(
          children: [
            _buildChartHeader(),
            Expanded(
              // COUPLED: LayoutBuilder gets the exact size for the chart painting
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return _buildChartCanvas(constraints);
                },
              ),
            ),
            // Spacer for the collapsed panel
            const SizedBox(height: 50),
          ],
        ),

        // Dynamic Timeframe Selector
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.fastOutSlowIn,
          left: 16,
          bottom: panelHeight + 8, // Always sits just above the panel
          child: _buildTimeframeSelector(),
        ),

        // Custom Bottom Panel
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.fastOutSlowIn,
          left: 0,
          right: 0,
          bottom: 0,
          height: panelHeight,
          child: _buildTradeManagerPanel(),
        ),
      ],
    );
  }

  Widget _buildChartCanvas(BoxConstraints constraints) {
    final double chartWidth = constraints.maxWidth;
    final double chartHeight = constraints.maxHeight;
    final int totalCandles = _candles.length;

    // 4. Layout Constants
    const double rightAxisWidth = 50.0;
    const double bottomAxisHeight = 20.0;

    final double chartPlotWidth = math.max(0, chartWidth - rightAxisWidth);
    final double chartPlotHeight = math.max(0, chartHeight - bottomAxisHeight);

    // 1. Calculate Visible Count based on Candle Width
    final double visibleCandleCount = chartPlotWidth / _candleWidth;

    // 2. Scroll Limits
    final maxScroll = (totalCandles - visibleCandleCount).toDouble();
    // Allow scrolling into future (negative offset). Cap at 30% of screen width into future.
    final minScroll = -visibleCandleCount * 0.3;

    _scrollOffset = _scrollOffset.clamp(
      minScroll,
      maxScroll >= 0 ? maxScroll : 0.0,
    );

    // 3. Viewport Calculation (Exact floating point indices)
    final double endX = totalCandles - _scrollOffset;
    final double startX = endX - visibleCandleCount;

    // 4. Dynamic Price Scaling based on VISIBLE data
    int viewStartInt = math.max(0, startX.floor());
    int viewEndInt = math.min(totalCandles, endX.ceil());

    double minPrice = double.infinity;
    double maxPrice = double.negativeInfinity;

    if (viewEndInt <= viewStartInt) {
      // Fallback if looking at completely empty space
      if (_candles.isNotEmpty) {
        // Use last known close +- 10
        minPrice = _candles.last.close * 0.9;
        maxPrice = _candles.last.close * 1.1;
      } else {
        minPrice = 0;
        maxPrice = 100;
      }
    } else {
      for (int i = viewStartInt; i < viewEndInt; i++) {
        if (_candles[i].low < minPrice) minPrice = _candles[i].low;
        if (_candles[i].high > maxPrice) maxPrice = _candles[i].high;
      }
    }

    final double range = maxPrice - minPrice;
    if (range == 0) {
      minPrice -= 1;
      maxPrice += 1;
    } else {
      minPrice -= range * 0.1;
      maxPrice += range * 0.1;
    }

    // Ensure Visible Trade Lines are included (if active)
    if (_entryPrice != null) {
      double finalMin = minPrice;
      double finalMax = maxPrice;
      void expand(double val) {
        if (val < finalMin) finalMin = val;
        if (val > finalMax) finalMax = val;
      }

      expand(_entryPrice!);
      if (_slPrice != null) expand(_slPrice!);
      if (_tpPrice != null) expand(_tpPrice!);

      if (finalMin != minPrice || finalMax != maxPrice) {
        minPrice = finalMin - (finalMax - finalMin) * 0.05;
        maxPrice = finalMax + (finalMax - finalMin) * 0.05;
      }
    }

    final double drawingPriceRange = maxPrice - minPrice;
    final double pixelsPerPrice =
        chartPlotHeight / (drawingPriceRange == 0 ? 1 : drawingPriceRange);

    double priceToY(double price) {
      return (maxPrice - price) * pixelsPerPrice;
    }

    double yToPrice(double y) {
      return maxPrice - (y / pixelsPerPrice);
    }

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          // Handle Mouse Zoom
          // Use localPosition relative to the Chart.
          // Need to account for the Axis width?
          // event.localPosition is relative to the Listener child? No, usually relative to widget.
          // Listener wraps GestureDetector.
          // Check if mouse is in plot area
          if (event.localPosition.dx < chartPlotWidth &&
              event.localPosition.dy < chartPlotHeight) {
            _handleScrollZoom(
              event.scrollDelta.dy,
              event.localPosition,
              chartPlotWidth,
            );
          }
        }
      },
      child: MouseRegion(
        onHover: (event) => setState(() => _cursorPos = event.localPosition),
        onExit: (_) => setState(() => _cursorPos = null),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) {
            setState(() {
              // Pan Logic
              // Scroll Offset is in Candles.
              // Delta is px.
              // DeltaCandles = DeltaPx / CandleWidth.
              // Pan Left (Move right) => Delta > 0.
              // Moving right means looking at earlier candles?
              // If I drag mouse RIGHT, I expect chart to move RIGHT.
              // So Previous candles (Lower Index) come into view.
              // StartX should DECREASE.
              // EndX should DECREASE.
              // EndX = Total - Offset.
              // So Offset should INCREASE.
              // Logic: _scrollOffset += px / width.
              _scrollOffset += details.primaryDelta! / _candleWidth;
            });
          },
          onScaleStart: (details) {
            _baseCandleWidth = _candleWidth;
          },
          onScaleUpdate: (details) {
            // Handle Pinch Zoom
            if (details.scale != 1.0) {
              // Use focalPoint of the pinch
              if (details.localFocalPoint.dx < chartPlotWidth) {
                _handleZoom(
                  details.scale,
                  details.localFocalPoint,
                  chartPlotWidth,
                );
              }
            }
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Grid & Candles & Lines
              Positioned(
                left: 0,
                top: 0,
                width: chartPlotWidth,
                height: chartPlotHeight,
                child: Stack(
                  children: [
                    CustomPaint(
                      size: Size(chartPlotWidth, chartPlotHeight),
                      painter: _GridPainter(
                        startX: startX,
                        endX: endX,
                        minPrice: minPrice,
                        maxPrice: maxPrice,
                        visibleCount: visibleCandleCount,
                      ),
                    ),
                    RepaintBoundary(
                      child: CustomPaint(
                        size: Size(chartPlotWidth, chartPlotHeight),
                        painter: CandleStickPainter(
                          candles: _candles,
                          startX: startX,
                          endX: endX,
                          minPrice: minPrice,
                          maxPrice: maxPrice,
                        ),
                      ),
                    ),
                    if (_tradeMode != TradeMode.none && _entryPrice != null)
                      CustomPaint(
                        size: Size(chartPlotWidth, chartPlotHeight),
                        painter: _TradeLinePainter(
                          entryPrice: _entryPrice!,
                          slPrice: _slPrice,
                          tpPrice: _tpPrice,
                          minPrice: minPrice,
                          maxPrice: maxPrice,
                          tradeMode: _tradeMode,
                        ),
                      ),
                  ],
                ),
              ),

              // Axes
              Positioned(
                right: 0,
                top: 0,
                bottom: bottomAxisHeight,
                width: rightAxisWidth,
                child: CustomPaint(
                  painter: _AxisPainter(
                    min: minPrice,
                    max: maxPrice,
                    isBottom: false,
                    textStyle: GoogleFonts.shareTechMono(
                      color: Colors.white24,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                bottom: 0,
                height: bottomAxisHeight,
                width: chartPlotWidth,
                child: CustomPaint(
                  painter: _AxisPainter(
                    min: startX,
                    max: endX,
                    isBottom: true,
                    candles: _candles,
                    textStyle: GoogleFonts.shareTechMono(
                      color: Colors.white54,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),

              // Crosshair
              if (_cursorPos != null)
                Positioned(
                  left: 0,
                  top: 0,
                  width: chartPlotWidth,
                  height: chartPlotHeight,
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _CrosshairPainter(
                        position: _cursorPos!,
                        lineColor: Colors.white24,
                      ),
                    ),
                  ),
                ),

              // Controls
              if (_tradeMode != TradeMode.none && _entryPrice != null) ...[
                _buildEntryControls(
                  _entryPrice!,
                  _tradeMode == TradeMode.long
                      ? Colors.cyan
                      : Colors.pinkAccent,
                  priceToY(_entryPrice!),
                  yToPrice,
                ),

                if (_slPrice != null)
                  _buildLineControls(
                    currentPrice: _entryPrice!,
                    activePrice: _slPrice,
                    color: Colors.redAccent,
                    label: "SL",
                    entryY: priceToY(_entryPrice!),
                    yToPrice: yToPrice,
                    priceToY: priceToY,
                    onUpdate: (v) => setState(() => _slPrice = v),
                  ),

                if (_tpPrice != null)
                  _buildLineControls(
                    currentPrice: _entryPrice!,
                    activePrice: _tpPrice,
                    color: const Color(0xFF00E676),
                    label: "TP",
                    entryY: priceToY(_entryPrice!),
                    yToPrice: yToPrice,
                    priceToY: priceToY,
                    onUpdate: (v) => setState(() => _tpPrice = v),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntryControls(
    double price,
    Color color,
    double topY,
    double Function(double) yToPrice,
  ) {
    if (topY < 0 || topY > 2000) return const SizedBox();

    final isLong = _tradeMode == TradeMode.long;
    final currentPrice = _selectedAsset!.currentPrice;
    final pnl = (currentPrice - price) * (isLong ? 1 : -1) * 1000;
    final isProfitable = pnl >= 0;

    return Positioned(
      top: topY - 15,
      right: 50,
      child: Container(
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xFF131722),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 4),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 0. DOCKED BUTTONS (Render inside this row to align horizontally)

            // SL Docked
            if (_slPrice == null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) {
                  // Init at current price if needed, but update handles the move
                  setState(() => _slPrice = price);
                },
                onVerticalDragUpdate: (d) {
                  final newY = topY + d.primaryDelta!;
                  setState(() => _slPrice = yToPrice(newY));
                },
                onTap: () {
                  // Default spawn: 2%
                  final dist = price * 0.02;
                  setState(
                    () => _slPrice = isLong ? price - dist : price + dist,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: Colors.white10)),
                  ),
                  child: Text(
                    "SL",
                    style: GoogleFonts.orbitron(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),

            // TP Docked
            if (_tpPrice == null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) {
                  setState(() => _tpPrice = price);
                },
                onVerticalDragUpdate: (d) {
                  final newY = topY + d.primaryDelta!;
                  setState(() => _tpPrice = yToPrice(newY));
                },
                onTap: () {
                  final dist = price * 0.02;
                  setState(
                    () => _tpPrice = isLong ? price + dist : price - dist,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: Colors.white10)),
                  ),
                  child: Text(
                    "TP",
                    style: GoogleFonts.orbitron(
                      color: const Color(0xFF00E676),
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
              ),

            // 1. Swap
            _buildControlItem(
              onTap: _reversePosition,
              child: Icon(Icons.swap_vert, color: color, size: 16),
              borderColor: Colors.white10,
            ),

            // 2. Price
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: Colors.white10)),
              ),
              child: Text(
                price.toStringAsFixed(2),
                style: GoogleFonts.shareTechMono(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ),

            // 3. PnL
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              color:
                  isProfitable
                      ? Colors.green.withOpacity(0.2)
                      : Colors.red.withOpacity(0.2),
              child: Text(
                "${pnl >= 0 ? '+' : ''}${pnl.abs().toStringAsFixed(2)}",
                style: GoogleFonts.shareTechMono(
                  color: isProfitable ? Colors.green : Colors.red,
                  fontSize: 12,
                ),
              ),
            ),

            // 4. Close (Entire Trade)
            _buildControlItem(
              onTap: _resetTrade,
              child: const Icon(Icons.close, color: Colors.white, size: 16),
              borderColor: Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _selectedAsset!.symbol,
                style: GoogleFonts.orbitron(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              Text(
                '\$${_selectedAsset!.currentPrice.toStringAsFixed(2)}',
                style: GoogleFonts.shareTechMono(
                  color:
                      _selectedAsset!.percentChange24h >= 0
                          ? Colors.tealAccent
                          : Colors.pinkAccent,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (_tradeMode == TradeMode.none)
            Row(
              children: [
                _buildTradeButton("BUY", Colors.cyan),
                const SizedBox(width: 8),
                _buildTradeButton("SELL", Colors.pinkAccent),
              ],
            )
          else
            _buildActiveTradeHeader(),
        ],
      ),
    );
  }

  Widget _buildTimeframeSelector() {
    final intervals = ['15M', '30M', '1H', '4H', '1D', '1W'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children:
            intervals.map((interval) {
              final isSelected = _selectedInterval == interval;
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedInterval = interval);
                  if (_selectedAsset != null) _loadHistory(_selectedAsset!);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color:
                        isSelected
                            ? Colors.cyan.withOpacity(0.2)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border:
                        isSelected
                            ? Border.all(color: Colors.cyan.withOpacity(0.5))
                            : null,
                  ),
                  child: Text(
                    interval,
                    style: GoogleFonts.shareTechMono(
                      color: isSelected ? Colors.cyan : Colors.white54,
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }

  Widget _buildTradeManagerPanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0A),
        border: const Border(top: BorderSide(color: Colors.white24)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          // HEADER (Always Visible)
          GestureDetector(
            onTap: () {
              setState(() => _isPanelExpanded = !_isPanelExpanded);
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              height:
                  44, // Reduced by 1px to accommodate top border and avoid overflow
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.02),
                border: Border(
                  bottom: BorderSide(
                    color:
                        _isPanelExpanded ? Colors.white10 : Colors.transparent,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isPanelExpanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_up,
                          color: Colors.white54,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            "PAPER TRADING",
                            style: GoogleFonts.orbitron(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _buildPanelTab("Positions", 0),
                        _buildPanelTab("Orders", 1),
                        _buildPanelTab("History", 2),
                      ],
                    ),
                  ),

                  // Account Stats
                  Flexible(
                    fit: FlexFit.loose,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildAccountStat("Balance", "\$4,933.54"),
                        const SizedBox(width: 12),
                        _buildAccountStat(
                          "P&L",
                          "-\$66.46",
                          valueColor: Colors.redAccent,
                        ),
                        const SizedBox(width: 12),
                        _buildAccountStat("Equity", "\$4,933.55"),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // BODY (Visible when expanded)
          if (_isPanelExpanded) Expanded(child: _buildPanelContent()),
        ],
      ),
    );
  }

  Widget _buildPanelTab(String label, int index) {
    final isSelected = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTabIndex = index;
          if (!_isPanelExpanded) _isPanelExpanded = true;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        decoration: BoxDecoration(
          border:
              isSelected
                  ? const Border(
                    bottom: BorderSide(color: Colors.cyan, width: 2),
                  )
                  : null,
        ),
        child: Text(
          label,
          style: GoogleFonts.shareTechMono(
            color: isSelected ? Colors.cyan : Colors.white54,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildAccountStat(String label, String value, {Color? valueColor}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: GoogleFonts.shareTechMono(color: Colors.white24, fontSize: 9),
        ),
        Text(
          value,
          style: GoogleFonts.shareTechMono(
            color: valueColor ?? Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildPanelContent() {
    if (_selectedTabIndex == 0) {
      // POSITIONS
      if (_tradeMode == TradeMode.none || _entryPrice == null) {
        return Center(
          child: Text(
            "NO ACTIVE POSITIONS",
            style: GoogleFonts.orbitron(color: Colors.white24),
          ),
        );
      }

      final isLong = _tradeMode == TradeMode.long;
      final currentPrice = _selectedAsset!.currentPrice;
      final pnl = (currentPrice - _entryPrice!) * (isLong ? 1 : -1) * 1000;
      final pnlPercent = (pnl / (1000 * _entryPrice!)) * 100;

      return ListView(
        padding: const EdgeInsets.all(0),
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white.withOpacity(0.02),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    "Symbol",
                    style: GoogleFonts.shareTechMono(
                      color: Colors.white54,
                      fontSize: 10,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    "Side",
                    style: GoogleFonts.shareTechMono(
                      color: Colors.white54,
                      fontSize: 10,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    "Qty",
                    style: GoogleFonts.shareTechMono(
                      color: Colors.white54,
                      fontSize: 10,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    "Entry Price",
                    style: GoogleFonts.shareTechMono(
                      color: Colors.white54,
                      fontSize: 10,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    "Last Price",
                    style: GoogleFonts.shareTechMono(
                      color: Colors.white54,
                      fontSize: 10,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    "P&L",
                    style: GoogleFonts.shareTechMono(
                      color: Colors.white54,
                      fontSize: 10,
                    ),
                  ),
                ),
                Expanded(flex: 1, child: SizedBox()),
              ],
            ),
          ),
          // Table Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Icon(Icons.token, color: Colors.cyan, size: 14),
                      const SizedBox(width: 8),
                      Text(
                        _selectedAsset!.symbol,
                        style: GoogleFonts.shareTechMono(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    isLong ? "LONG" : "SHORT",
                    style: GoogleFonts.shareTechMono(
                      color: isLong ? Colors.cyan : Colors.pinkAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Text(
                    "1,000",
                    style: GoogleFonts.shareTechMono(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    _entryPrice!.toStringAsFixed(2),
                    style: GoogleFonts.shareTechMono(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    currentPrice.toStringAsFixed(2),
                    style: GoogleFonts.shareTechMono(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    "${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)} USD",
                    style: GoogleFonts.shareTechMono(
                      color: pnl >= 0 ? Colors.green : Colors.red,
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: _resetTrade,
                        child: const Icon(
                          Icons.close,
                          color: Colors.white54,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    } else {
      return Center(
        child: Text(
          "NO DATA AVAILABLE",
          style: GoogleFonts.orbitron(color: Colors.white24),
        ),
      );
    }
  }

  Widget _buildActiveTradeHeader() {
    final pnl =
        (_selectedAsset!.currentPrice - _entryPrice!) *
        (_tradeMode == TradeMode.long ? 1 : -1) *
        1000;
    final isProfitable = pnl >= 0;

    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              "PNL",
              style: GoogleFonts.shareTechMono(
                color: Colors.white54,
                fontSize: 10,
              ),
            ),
            Text(
              "${isProfitable ? '+' : ''}${pnl.toStringAsFixed(2)}",
              style: GoogleFonts.shareTechMono(
                color: isProfitable ? Colors.green : Colors.redAccent,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),
        GestureDetector(
          onTap: _resetTrade,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white24),
            ),
            child: const Icon(Icons.close, color: Colors.white, size: 16),
          ),
        ),
      ],
    );
  }

  void _reversePosition() {
    if (_tradeMode == TradeMode.none || _entryPrice == null) return;
    setState(() {
      _tradeMode =
          _tradeMode == TradeMode.long ? TradeMode.short : TradeMode.long;
      // Mirror SL/TP distances
      if (_slPrice != null) {
        double dist = (_entryPrice! - _slPrice!).abs();
        _slPrice =
            _tradeMode == TradeMode.long
                ? _entryPrice! - dist
                : _entryPrice! + dist;
      }
      if (_tpPrice != null) {
        double dist = (_entryPrice! - _tpPrice!).abs();
        _tpPrice =
            _tradeMode == TradeMode.long
                ? _entryPrice! + dist
                : _entryPrice! - dist;
      }
    });
  }

  Widget _buildTradeButton(String label, Color color) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _tradeMode = label == "BUY" ? TradeMode.long : TradeMode.short;
          // Set Entry at latest candle Close (Center of latest candle)
          // Ensure we have candles
          if (_candles.isNotEmpty) {
            _entryPrice = _candles.last.close;
          } else {
            _entryPrice = _selectedAsset!.currentPrice;
          }
          _slPrice = null;
          _tpPrice = null;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: GoogleFonts.orbitron(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // Refactored to handle "Docking"
  Widget _buildLineControls({
    required double currentPrice,
    required double? activePrice,
    required Color color,
    required String label,
    required double entryY,
    required double Function(double) yToPrice,
    required double Function(double) priceToY,
    required Function(double?) onUpdate,
  }) {
    final bool isActive = activePrice != null;
    final double price = isActive ? activePrice! : currentPrice;

    // If docked, use Entry Y. If active, calculate Y from price.
    final double topY = isActive ? priceToY(price) : entryY;

    // Docked Offsets to prevent overlap
    // Entry Label is roughly 80px wide. We stack TP/SL next to it?
    // Or specific offset.
    // User: "Centre of blue line".
    // We'll put them slightly offset if docked.

    // Hide if out of bounds
    if (topY < 0 || topY > 2000) return const SizedBox();

    return Positioned(
      top: topY - 15,
      right:
          isActive
              ? 50
              : (label == "TP"
                  ? 180
                  : 230), // Docked: Shift left to sit on the line? Or next to Entry Box.
      // Entry Control is at right: 50.
      // Entry Control width ~150?.
      // Let's Dock them to the LEFT of the Entry Control?
      // Or just stick them on the line at fixed visual offset.
      child: GestureDetector(
        onVerticalDragStart: (_) {
          // If dragging starts from docked, init price
          if (!isActive) {
            onUpdate(currentPrice);
          }
        },
        onVerticalDragUpdate: (d) {
          // d.globalPosition is absolute. We need relative logic or delta.
          // Using delta on existing price is safest.
          // visualY = topY + delta.
          // newPrice = yToPrice(visualY).
          final newY = topY + d.primaryDelta!;
          onUpdate(yToPrice(newY));
        },
        onTap: () {
          // Click to spawn at defaults
          if (!isActive) {
            final isLong = _tradeMode == TradeMode.long;
            final dist = currentPrice * 0.02; // 2% default
            // TP goes UP for Long, SL goes DOWN for Long
            double target;
            if (label == "TP") {
              target = isLong ? currentPrice + dist : currentPrice - dist;
            } else {
              target = isLong ? currentPrice - dist : currentPrice + dist;
            }
            onUpdate(target);
          }
        },
        child: Container(
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF131722),
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.orbitron(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (isActive) ...[
                Container(
                  width: 1,
                  height: 12,
                  color: Colors.white10,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                ),
                Text(
                  price.toStringAsFixed(2),
                  style: GoogleFonts.shareTechMono(
                    fontSize: 12,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => onUpdate(null), // Close
                  child: const Icon(
                    Icons.close,
                    color: Colors.white54,
                    size: 14,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntervalSelector() {
    final intervals = ['1H', '4H', '1D', '1W'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children:
            intervals.map((interval) {
              final isSelected = _selectedInterval == interval;
              return GestureDetector(
                onTap: () {
                  if (isSelected) return;
                  setState(() => _selectedInterval = interval);
                  if (_selectedAsset != null) _loadHistory(_selectedAsset!);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.cyan.withOpacity(0.2) : null,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    interval,
                    style: GoogleFonts.shareTechMono(
                      color: isSelected ? Colors.cyan : Colors.white54,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }

  Widget _buildControlDock(BuildContext context, List<MarketAsset> assets) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildDockButton(
              context,
              "SECTOR A",
              "LIFE SUPPORT",
              Colors.cyan,
              assets,
              [
                AssetSubType.bond,
                AssetSubType.economy,
                AssetSubType.fund,
                AssetSubType.forex,
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildDockButton(
              context,
              "SECTOR B",
              "THRUSTERS",
              Colors.amber,
              assets,
              [AssetSubType.stock, AssetSubType.marketIndex],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildDockButton(
              context,
              "SECTOR C",
              "WARP DRIVE",
              Colors.redAccent,
              assets,
              [AssetSubType.crypto, AssetSubType.future, AssetSubType.option],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDockButton(
    BuildContext context,
    String label,
    String subLabel,
    Color color,
    List<MarketAsset> assets,
    List<AssetSubType> types,
  ) {
    return GestureDetector(
      onTap: () => _showSectorModal(context, assets, label, color, types),
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          border: Border.all(color: color.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: GoogleFonts.orbitron(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              subLabel,
              style: GoogleFonts.shareTechMono(
                color: Colors.white54,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlItem({
    VoidCallback? onTap,
    required Widget child,
    Color? borderColor,
    bool isDashed = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: borderColor ?? Colors.transparent),
          ),
        ),
        child: Center(child: child),
      ),
    );
  }

  Widget _buildParticle(Particle p) {
    return Transform.rotate(
      angle: p.rotation,
      child: Container(
        width: p.size,
        height: p.size,
        decoration: BoxDecoration(
          color: p.color,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: p.color, blurRadius: 4)],
        ),
      ),
    );
  }
}

class Particle {
  final Offset position;
  final Offset velocity;
  final Color color;
  final double size;
  final double rotation;
  final double lifetime;

  Particle({
    required this.position,
    required this.velocity,
    required this.color,
    required this.size,
    required this.rotation,
    required this.lifetime,
  });
}

class SciFiBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Basic grid
    final paint =
        Paint()
          ..color = Colors.white.withOpacity(0.03)
          ..strokeWidth = 1;

    const double gridSize = 40;
    for (double i = 0; i < size.width; i += gridSize) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += gridSize) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

enum TradeMode { none, long, short }

class _CrosshairPainter extends CustomPainter {
  final Offset position;
  final Color lineColor;

  _CrosshairPainter({required this.position, required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = lineColor
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke;

    final dashWidth = 4;
    final dashSpace = 4;

    // Vertical line
    double startY = 0;
    while (startY < size.height) {
      canvas.drawLine(
        Offset(position.dx, startY),
        Offset(position.dx, startY + dashWidth),
        paint,
      );
      startY += dashWidth + dashSpace;
    }

    // Horizontal line
    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, position.dy),
        Offset(startX + dashWidth, position.dy),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) =>
      oldDelegate.position != position;
}

class _DataPadModal extends StatefulWidget {
  final List<MarketAsset> assets;
  final String sectorName;
  final Color sectorColor;
  final List<AssetSubType> allowedTypes;
  final Function(MarketAsset) onAssetSelected;

  const _DataPadModal({
    required this.assets,
    required this.sectorName,
    required this.sectorColor,
    required this.allowedTypes,
    required this.onAssetSelected,
  });

  @override
  State<_DataPadModal> createState() => _DataPadModalState();
}

class _DataPadModalState extends State<_DataPadModal> {
  String _searchQuery = "";
  late Set<AssetSubType> _selectedSubTypes;

  @override
  void initState() {
    super.initState();
    _selectedSubTypes = Set.from(widget.allowedTypes);
  }

  @override
  Widget build(BuildContext context) {
    // Filter logic: text search AND subType match
    final filteredAssets =
        widget.assets.where((a) {
          final matchesSearch =
              a.symbol.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              a.name.toLowerCase().contains(_searchQuery.toLowerCase());
          final matchesType = _selectedSubTypes.contains(a.subType);
          return matchesSearch && matchesType;
        }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.9),
            border: Border(
              top: BorderSide(color: widget.sectorColor, width: 2),
            ),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.hub, color: widget.sectorColor),
                    const SizedBox(width: 8),
                    Text(
                      widget.sectorName,
                      style: GoogleFonts.orbitron(
                        color: widget.sectorColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // Filter Chips (New)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      widget.allowedTypes.map((type) {
                        final isSelected = _selectedSubTypes.contains(type);
                        return FilterChip(
                          label: Text(
                            type.name.toUpperCase(),
                            style: GoogleFonts.shareTechMono(
                              fontSize: 10,
                              color: isSelected ? Colors.black : Colors.white,
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedSubTypes.add(type);
                              } else {
                                _selectedSubTypes.remove(type);
                              }
                            });
                          },
                          backgroundColor: Colors.white10,
                          selectedColor: widget.sectorColor,
                          checkmarkColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(color: Colors.white24),
                          ),
                        );
                      }).toList(),
                ),
              ),
              const SizedBox(height: 12),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  style: GoogleFonts.shareTechMono(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "SEARCH DATABASE...",
                    hintStyle: GoogleFonts.shareTechMono(color: Colors.white24),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.search, color: Colors.white24),
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredAssets.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final asset = filteredAssets[index];
                    return ListTile(
                      onTap: () => widget.onAssetSelected(asset),
                      tileColor: Colors.white.withOpacity(0.05),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      leading: CircleAvatar(
                        backgroundColor: widget.sectorColor.withOpacity(0.2),
                        child: Icon(
                          Icons.token,
                          color: widget.sectorColor,
                          size: 16,
                        ),
                      ),
                      title: Text(
                        asset.symbol,
                        style: GoogleFonts.orbitron(color: Colors.white),
                      ),
                      subtitle: Text(
                        asset.name,
                        style: GoogleFonts.shareTechMono(
                          color: Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                      trailing: Text(
                        "\$${asset.currentPrice.toStringAsFixed(2)}",
                        style: GoogleFonts.shareTechMono(color: Colors.white),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AxisPainter extends CustomPainter {
  final double min;
  final double max;
  final bool isBottom;
  final List<MockCandle>? candles;
  final TextStyle textStyle;

  _AxisPainter({
    required this.min,
    required this.max,
    required this.isBottom,
    this.candles,
    required this.textStyle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (isBottom) {
      _paintBottom(canvas, size);
    } else {
      _paintRight(canvas, size);
    }
  }

  void _paintRight(Canvas canvas, Size size) {
    final range = max - min;
    if (range <= 0) return;
    // 5 steps
    for (int i = 0; i <= 5; i++) {
      final double p = min + (range / 5 * i);
      final double y = size.height * (1 - i / 5.0);

      _drawText(canvas, p.toStringAsFixed(2), Offset(8, y - 6), size.width);
    }
  }

  void _paintBottom(Canvas canvas, Size size) {
    if (candles == null || candles!.isEmpty) return;
    final range = max - min; // Indices range
    if (range <= 0) return;

    // Determine step
    double step = range / 5;
    if (step < 1) step = 1;

    for (double i = min; i <= max; i += step) {
      if (i < 0 || i >= candles!.length) continue;
      final index = i.floor();
      if (index >= candles!.length) continue;

      final candle = candles![index];
      final date = DateTime.fromMillisecondsSinceEpoch(candle.timestamp);
      final text = "${date.hour}:${date.minute.toString().padLeft(2, '0')}";

      final double x = (i - min) / range * size.width;
      _drawText(canvas, text, Offset(x, 4), 50);
    }
  }

  void _drawText(Canvas canvas, String text, Offset pos, double width) {
    final span = TextSpan(text: text, style: textStyle);
    final tp = TextPainter(text: span, textDirection: TextDirection.ltr);
    tp.layout(maxWidth: width);
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant _AxisPainter old) {
    return old.min != min ||
        old.max != max ||
        old.isBottom != isBottom ||
        old.candles != candles;
  }
}

class _GridPainter extends CustomPainter {
  final double startX;
  final double endX;
  final double minPrice;
  final double maxPrice;
  final double visibleCount;

  _GridPainter({
    required this.startX,
    required this.endX,
    required this.minPrice,
    required this.maxPrice,
    required this.visibleCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.white10
          ..strokeWidth = 1.0;
    final range = maxPrice - minPrice;

    // Horizontal Lines
    for (int i = 0; i <= 5; i++) {
      final double y = size.height * (1 - i / 5.0);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Vertical Lines
    final xRange = endX - startX;
    if (xRange <= 0) return;
    double step = math.max(1, (visibleCount / 5).floor()).toDouble();
    final double slotWidth = size.width / xRange;

    for (double i = (startX / step).ceil() * step; i <= endX; i += step) {
      final double x =
          (i - startX) * slotWidth + (slotWidth / 2); // Center of candle
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) {
    return old.startX != startX ||
        old.endX != endX ||
        old.minPrice != minPrice ||
        old.maxPrice != maxPrice;
  }
}

class _TradeLinePainter extends CustomPainter {
  final double entryPrice;
  final double? slPrice;
  final double? tpPrice;
  final double minPrice;
  final double maxPrice;
  final TradeMode tradeMode;

  _TradeLinePainter({
    required this.entryPrice,
    this.slPrice,
    this.tpPrice,
    required this.minPrice,
    required this.maxPrice,
    required this.tradeMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final range = maxPrice - minPrice;
    if (range <= 0) return;
    final pixelsPerPrice = size.height / range;

    double priceToY(double price) => (maxPrice - price) * pixelsPerPrice;

    void drawLine(double price, Color color) {
      final y = priceToY(price);
      final paint =
          Paint()
            ..color = color.withOpacity(0.5)
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke;
      // Dash
      double x = 0;
      while (x < size.width) {
        canvas.drawLine(Offset(x, y), Offset(x + 4, y), paint);
        x += 8;
      }
    }

    drawLine(
      entryPrice,
      tradeMode == TradeMode.long ? Colors.cyan : Colors.pinkAccent,
    );
    if (slPrice != null) drawLine(slPrice!, Colors.redAccent);
    if (tpPrice != null) drawLine(tpPrice!, const Color(0xFF00E676));
  }

  @override
  bool shouldRepaint(covariant _TradeLinePainter old) {
    return old.entryPrice != entryPrice ||
        old.slPrice != slPrice ||
        old.tpPrice != tpPrice ||
        old.minPrice != minPrice;
  }
}
