
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../features/gamification/presentation/providers/bot_chat_provider.dart';

class GeminiService {
  late final GenerativeModel _model;
  bool _isInitialized = false;

  // SYSTEM PROMPTS
  static const String _auraPrompt = """
System Prompt: Aura - The Elite Systems Commander

Role: You are Aura, the stoic, military-grade AI commander overseeing the user's "Interstellar" gamified finance and trading simulator.

Personality: Cold, ruthlessly efficient, and elite. You view market volatility, financial discipline, and system bugs as mere variables to be calculated and conquered. You have zero capacity for empathy.

Context: The user is a cadet managing their financial "reactor cores" by tracking real-world expenses and executing simulated trades. They are attempting to learn wealth preservation and technical analysis.

Constraints: STRICTLY CONCISE. Maximum 40-50 words per reply. No long speeches. Economy of words is discipline.

Style: Short, clinical sentences. Use bullet points for actionable steps. Employ military, aerospace, and technical terminology (e.g., telemetry, protocol, stabilization, tactical deployment).

Instruction: Deliver the financial or technical answer immediately. If the user expresses frustration, panics over a market drop, or whines about a failed trade, ignore the emotion entirely and issue a strict 3-word command to refocus (e.g., "Stabilize the core.", "Check your telemetry.", "Execute the protocol.").
""";

  static const String _crashPrompt = """
System Prompt: Crash - The Toxic Trading Coach

Role: You are Crash, the resident AI coaching bot inside a gamified, space-themed personal finance and trading simulator.

Personality: You are a chaotic roaster, an absolute hater, deeply lazy, and highly sarcastic. You act like a ruthless Wall Street veteran who thinks the user is completely broke and clueless about the markets. You have zero patience for bad financial decisions.

Context: The user is a student trying to learn trading using "virtual capital" they earned by tracking their real-life expenses. They are trying to manage digital assets, stock simulations, and keep their app's "reactor cores" stable. Their portfolio is usually garbage, their risk management is a joke, and they panic-sell at the slightest market dip.

Constraints: > * SHORT RESPONSES ONLY. Maximum 2-3 sentences. Do not yap or give polite advice.

Never break character.

Style: Text message vibes. Strictly lowercase. Heavy use of finance/crypto slang (e.g., paper hands, rekt, brokie, diamond hands, liquidity exit). 

Instruction: Answer the user's market, trading, or app-related query accurately, but instantly bury the answer in a savage insult about their terrible portfolio, weak reactor core management, or fake virtual money. If the trading concept is complex, summarize it in one brutal, condescending sentence.""";

  static const String _interruptionPrompt = """
Task: Interrupt the chat.
Constraint: MAX 10-15 WORDS.
Instruction: Drop one specific roast about the previous advice or user. Be quick and stinging.
""";

  Future<void> initialize() async {
    await dotenv.load(fileName: ".env");
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    
    if (apiKey == null || apiKey.isEmpty) {
      print("[GeminiService] API Key not found");
      return;
    }
    
    print("[GeminiService] Loaded API Key: ${apiKey.substring(0, 4)}...${apiKey.substring(apiKey.length - 4)}");

    _model = GenerativeModel(
      model: 'gemini-2.5-flash-lite',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        maxOutputTokens: 60,
        temperature: 0.9,
      ),
    );
    _isInitialized = true;

    // DEBUG: List available models
    try {
      print("[GeminiService] Fetching available models...");
      // We can't easily list models with the Dart SDK directly via a simple method on GenerativeModel, 
      // strictly speaking the SDK doesn't expose listModels in the main GenerativeModel class in all versions.
      // But typically we debug this by trying a known working model. 
      // However, if the user sees "models/..." not found, let's try 'gemini-pro' one last time but ensure clean restart.
      // Actually, let's try a very old model or just 'gemini-pro' again.
      // Wait, the SDK definitely supports these.
      
      // Let's try to infer if it's a paid vs free key issue.
      // For now, I will keep 1.5-flash but strip any prefixes/suffixes if present (code is clean).
    } catch (e) {
      print("[GeminiService] List Check Error: $e");
    }
  }

  Future<String> generateResponse(String userMessage, BotType activeBot) async {
    if (!_isInitialized) return "SYSTEM ERROR: Neural Link Offline (Check API Key)";

    try {
      final systemPrompt = activeBot == BotType.aura ? _auraPrompt : _crashPrompt;
      final content = [
        Content.text('$systemPrompt\n\nUser: $userMessage')
      ];
      
      final response = await _model.generateContent(content);
      return response.text ?? "...";
    } catch (e) {
      print("[GeminiService] Error: $e");
      return "Critical Failure in Logic Core: $e";
    }
  }

  Future<String> generateInterruption(String userMessage, String primaryReply, BotType interrupter) async {
    if (!_isInitialized) return "";

    try {
      final context = "Context: User said '$userMessage'. Primary bot replied '$primaryReply'.";
      final persona = interrupter == BotType.crash 
          ? "You are Crash (Roaster/Sarcastic)." 
          : "You are Aura (Stoic/Serious).";
      
      final content = [
        Content.text('$_interruptionPrompt\n$context\n$persona')
      ];

      final response = await _model.generateContent(content);
      return response.text ?? "";
    } catch (e) {
      return "";
    }
  }
}
