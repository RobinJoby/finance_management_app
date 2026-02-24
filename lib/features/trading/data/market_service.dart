import 'dart:convert';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../domain/models/market_asset.dart';

// Provider definition
final marketServiceProvider = Provider<MarketRepository>((ref) {
  return MixedMarketService();
});

// FutureProvider for fetching assets
final marketAssetsProvider = FutureProvider<List<MarketAsset>>((ref) async {
  final service = ref.watch(marketServiceProvider);
  return service.fetchAssets();
});

abstract class MarketRepository {
  Future<List<MarketAsset>> fetchAssets();
  Future<List<MockCandle>> getAssetHistory(String assetId, String interval);

  /// Live USD → INR rate captured during the last Yahoo fetch.
  /// Falls back to 84.0 if Yahoo has not been called yet.
  double get usdToInr;
}

/// Provider that exposes the latest USD/INR exchange rate.
/// Updated each time [marketAssetsProvider] fetches data.
final usdInrRateProvider = Provider<double>((ref) {
  final service = ref.watch(marketServiceProvider);
  return service.usdToInr;
});

class MixedMarketService implements MarketRepository {
  final http.Client _client = http.Client();

  /// Fallback rate until Yahoo returns the live rate.
  double _usdToInr = 84.0;

  @override
  double get usdToInr => _usdToInr;

  // CoinGecko API for Crypto
  final String _cryptoApiUrl =
      'https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&ids=bitcoin,ethereum,dogecoin&order=market_cap_desc&per_page=10&page=1&sparkline=false';

  // Yahoo Finance API - single batch call for Stocks, Indices, Commodities, Forex
  // %5E = ^ (index prefix), %3D = = (futures suffix)
  final String _yahooApiUrl =
      'https://query1.finance.yahoo.com/v7/finance/quote?symbols=AAPL,RELIANCE.NS,%5EGSPC,%5EIXIC,GC%3DF,CL%3DF,INR%3DX';

  @override
  Future<List<MarketAsset>> fetchAssets() async {
    List<MarketAsset> assets = [];

    // 1. Fetch Crypto (API)
    try {
      final response = await _client.get(Uri.parse(_cryptoApiUrl));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        assets.addAll(data.map((json) {
          final asset = MarketAsset.fromJson(json);
          // Customize levels for Crypto
          int level = 1;
          if (asset.symbol.toUpperCase() == 'BTC') level = 5; // Bitcoin is high level
          if (asset.symbol.toUpperCase() == 'ETH') level = 3;
          if (asset.symbol.toUpperCase() == 'DOGE') level = 1;

          return MarketAsset(
            id: asset.id,
            symbol: asset.symbol.toUpperCase(),
            name: asset.name,
            currentPrice: asset.currentPrice,
            percentChange24h: asset.percentChange24h,
            type: AssetType.warpDrive, // Crypto is Warp Drive (High Risk)
            subType: AssetSubType.crypto,
            minLevelRequired: level,
          );
        }));
      } else {
        // Fallback mock if API fails
        assets.addAll(_getMockSectorC());
      }
    } catch (e) {
      // Fallback mock if network error
      assets.addAll(_getMockSectorC());
    }

    // 2. Fetch Stocks, Indices, Commodities (Yahoo Finance - single batch call)
    bool yahooSuccess = false;
    try {
      final yResponse = await _client.get(
        Uri.parse(_yahooApiUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 8));

      if (yResponse.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(yResponse.body);
        final results = data['quoteResponse']?['result'] as List<dynamic>?;

        if (results != null && results.isNotEmpty) {
          yahooSuccess = true;

          // --- Pass 1: capture live USD/INR rate ---
          for (final item in results) {
            if ((item['symbol'] ?? '') == 'INR=X') {
              final rate = (item['regularMarketPrice'] as num?)?.toDouble();
              if (rate != null && rate > 0) _usdToInr = rate;
              break;
            }
          }
          print('[MarketService] USD/INR rate: $_usdToInr');

          // --- Pass 2: build assets ---
          for (final item in results) {
            final String symbol = (item['symbol'] ?? '').toString();
            final double priceRaw = (item['regularMarketPrice'] as num?)?.toDouble() ?? 0.0;
            final double change = (item['regularMarketChangePercent'] as num?)?.toDouble() ?? 0.0;

            // Convert USD-denominated assets to INR
            final double price = _toInr(symbol, priceRaw);

            if (symbol == 'AAPL') {
              // AAPL is on NYSE (USD) - converted to INR
              assets.add(_buildAsset('aapl', 'AAPL', 'Apple Inc. (INR)', price, change, AssetType.thruster, AssetSubType.stock, 3));
            } else if (symbol == 'RELIANCE.NS') {
              // Reliance is on NSE (already INR)
              assets.add(_buildAsset('reliance', 'RELIANCE', 'Reliance Ind.', price, change, AssetType.thruster, AssetSubType.stock, 3));
            } else if (symbol == '^GSPC') {
              // S&P 500 is USD - converted to INR
              assets.add(_buildAsset('sp500', 'SPX', 'S&P 500 (INR)', price, change, AssetType.fleet, AssetSubType.marketIndex, 4));
            } else if (symbol == '^IXIC') {
              // NASDAQ is USD - converted to INR
              assets.add(_buildAsset('nasdaq', 'NDX', 'NASDAQ (INR)', price, change, AssetType.fleet, AssetSubType.marketIndex, 4));
            } else if (symbol == 'GC=F') {
              // Gold is USD/oz - converted to INR
              assets.add(_buildAsset('gold', 'GOLD', 'Gold (INR/oz)', price, change, AssetType.lifeSupport, AssetSubType.forex, 2));
            } else if (symbol == 'CL=F') {
              // Crude Oil is USD/bbl - converted to INR
              assets.add(_buildAsset('oil', 'OIL', 'Crude Oil (INR)', price, change, AssetType.lifeSupport, AssetSubType.forex, 2));
            } else if (symbol == 'INR=X') {
              // USD/INR rate itself - show raw (not doubled)
              assets.add(_buildAsset('usdinr', 'USD/INR', 'USD/INR Rate', priceRaw, change, AssetType.lifeSupport, AssetSubType.forex, 1));
            }
          }
        }
      }
    } catch (e) {
      print('[MarketService] Yahoo Finance fetch failed: $e');
    }

    // Fallback: use mock data if Yahoo call failed or returned empty
    if (!yahooSuccess) {
      print('[MarketService] Using mock fallback for stocks/indices/commodities.');
      assets.addAll(_getMockSectorB_Thrusters());
      assets.addAll(_getMockSectorB_Fleets());
      assets.add(_getMockSectorA('gold', 'Gold', 2030.50, 2));
      assets.add(_getMockSectorA('oil', 'Crude Oil', 78.40, 2));
      assets.add(_getMockSectorA('usdinr', 'USD/INR', 83.12, 1));
    }

    return assets;
  }

  @override
  Future<List<MockCandle>> getAssetHistory(String assetId, String interval) async {
    // ... (keep existing implementation) ...
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Generate realistic-looking random walk data
    final List<MockCandle> candles = [];
    final now = DateTime.now();
    
    // Base price depends on asset (rough hack for demo)
    double price = 100.0;
    if (assetId == 'bitcoin') price = 42000.0;
    if (assetId == 'ethereum') price = 2200.0;
    if (assetId == 'dogecoin') price = 0.15;
    if (assetId == 'aapl') price = 185.0;
    
    // Determine number of points and interval duration
    int points = 100;
    Duration step = const Duration(hours: 1);
    if (interval == '1D') step = const Duration(days: 1);
    if (interval == '1W') step = const Duration(days: 7);
    if (interval == '4H') step = const Duration(hours: 4);
    if (interval == '1H') step = const Duration(hours: 1);
    if (interval == '30M') step = const Duration(minutes: 30);
    if (interval == '15M') step = const Duration(minutes: 15);
    
    DateTime currentStr = now.subtract(step * points);
    
    final random = Random();
    
    for (int i = 0; i < points; i++) {
        // Random usage to generate O H L C
        double volatility = price * 0.02; // 2% volatility
        double change = (random.nextDouble() - 0.5) * volatility;
        
        double open = price;
        double close = price + change;
        double high = max(open, close) + random.nextDouble() * volatility * 0.5;
        double low = min(open, close) - random.nextDouble() * volatility * 0.5;
        
        candles.add(MockCandle(
          open: open, 
          high: high, 
          low: low, 
          close: close, 
          volume: 1000 + random.nextDouble() * 5000, 
          timestamp: currentStr.millisecondsSinceEpoch,
        ));
        
        price = close; // Next candle starts at this close
        currentStr = currentStr.add(step);
    }
    
    return candles;
  }

  // --- Helpers ---

  /// Symbols that are USD-denominated and need INR conversion.
  static const _usdSymbols = {'AAPL', '^GSPC', '^IXIC', 'GC=F', 'CL=F'};

  /// Convert [priceUsd] to INR if [symbol] is USD-denominated; pass-through otherwise.
  double _toInr(String symbol, double priceUsd) {
    if (_usdSymbols.contains(symbol)) return priceUsd * _usdToInr;
    return priceUsd; // RELIANCE.NS and INR=X are already in INR
  }

  MarketAsset _buildAsset(
    String id, String symbol, String name,
    double price, double change,
    AssetType type, AssetSubType subType, int level,
  ) {
    return MarketAsset(
      id: id,
      symbol: symbol,
      name: name,
      currentPrice: price,
      percentChange24h: change,
      type: type,
      subType: subType,
      minLevelRequired: level,
    );
  }

  // --- Mock Generators (fallback when network is unavailable) ---

  List<MarketAsset> _getMockSectorC() {
    return [
      MarketAsset(id: 'bitcoin', symbol: 'BTC', name: 'Bitcoin', currentPrice: 42000.0, percentChange24h: 2.5, type: AssetType.warpDrive, subType: AssetSubType.crypto, minLevelRequired: 5),
      MarketAsset(id: 'ethereum', symbol: 'ETH', name: 'Ethereum', currentPrice: 2200.0, percentChange24h: -1.2, type: AssetType.warpDrive, subType: AssetSubType.crypto, minLevelRequired: 3),
      MarketAsset(id: 'dogecoin', symbol: 'DOGE', name: 'Dogecoin', currentPrice: 0.15, percentChange24h: 5.0, type: AssetType.warpDrive, subType: AssetSubType.crypto, minLevelRequired: 1),
    ];
  }

  List<MarketAsset> _getMockSectorB_Fleets() {
    return [
      MarketAsset(
        id: 'sp500', 
        symbol: 'SPX', 
        name: 'S&P 500 Fleet', 
        currentPrice: 4800.0, 
        percentChange24h: 0.5, 
        type: AssetType.fleet,
        subType: AssetSubType.marketIndex, 
        minLevelRequired: 4
      ),
      MarketAsset(
        id: 'nasdaq', 
        symbol: 'NDX', 
        name: 'NASDAQ Fleet', 
        currentPrice: 16800.0, 
        percentChange24h: 0.8, 
        type: AssetType.fleet,
        subType: AssetSubType.marketIndex, 
        minLevelRequired: 4
      ),
    ];
  }

  List<MarketAsset> _getMockSectorB_Thrusters() {
    final random = Random();
    // Simulate volatility: -2% to +2% change roughly
    double AAPL_Price = 185.0 + (random.nextDouble() - 0.5) * 5; 
    double RELIANCE_Price = 2500.0 + (random.nextDouble() - 0.5) * 50;

    return [
      MarketAsset(
        id: 'aapl', 
        symbol: 'AAPL', 
        name: 'Apple Inc.', 
        currentPrice: AAPL_Price, 
        percentChange24h: (random.nextDouble() - 0.5) * 3.0, 
        type: AssetType.thruster,
        subType: AssetSubType.stock, 
        minLevelRequired: 3
      ),
      MarketAsset(
        id: 'reliance', 
        symbol: 'RELIANCE', 
        name: 'Reliance Ind.', 
        currentPrice: RELIANCE_Price, 
        percentChange24h: (random.nextDouble() - 0.5) * 4.0, 
        type: AssetType.thruster,
        subType: AssetSubType.stock, 
        minLevelRequired: 3
      ),
    ];
  }

  MarketAsset _getMockSectorA(String id, String name, double basePrice, int level) {
    final random = Random();
    double price = basePrice + (random.nextDouble() - 0.5) * (basePrice * 0.01); // 1% volatility
    return MarketAsset(
      id: id,
      symbol: name.toUpperCase(),
      name: name,
      currentPrice: price,
      percentChange24h: (random.nextDouble() - 0.5) * 1.5,
      type: AssetType.lifeSupport,
      subType: AssetSubType.forex, // Defaulting to forex for simplicity
      minLevelRequired: level,
    );
  }
}

class MockCandle {
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
  final int timestamp;

  MockCandle({
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    required this.timestamp,
  });
}
