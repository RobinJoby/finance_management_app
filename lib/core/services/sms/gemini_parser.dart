import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

/// Represents a bank transaction parsed from an SMS.
class ParsedTransaction {
  final double amount;
  final String type; // 'income' | 'expense'
  final String category;
  final bool isWant;

  const ParsedTransaction({
    required this.amount,
    required this.type,
    required this.category,
    required this.isWant,
  });

  @override
  String toString() =>
      'ParsedTransaction(amount: $amount, type: $type, category: $category, isWant: $isWant)';
}

/// Uses the Gemini API to parse raw bank SMS text into a [ParsedTransaction].
///
/// Returns `null` if:
/// - The API key is missing from .env
/// - The Gemini request fails
/// - The response JSON is malformed
class GeminiParser {
  static const _systemPrompt = '''
You are a financial SMS parser. Parse the given bank SMS into a JSON object.
Respond ONLY with a single valid JSON object — no markdown, no explanation, no extra text.

JSON format:
{
  "amount": <number>,
  "type": "income" | "expense",
  "category": "food" | "upi" | "salary" | "shopping" | "transport" | "entertainment" | "health" | "utilities" | "rent" | "other",
  "isWant": <true | false>
}

Rules:
- "debited", "spent", "withdrawn" → type = "expense"
- "credited", "received", "deposited" → type = "income"
- isWant = true for entertainment, shopping; false for salary, health, utilities, rent
''';

  /// Sends [smsBody] to Gemini and returns a [ParsedTransaction] or `null`.
  Future<ParsedTransaction?> parse(String smsBody) async {
    try {
      final apiKey = dotenv.maybeGet('GEMINI_API_KEY');
      if (apiKey == null || apiKey.isEmpty) {
        debugPrint(
          '[GeminiParser] GEMINI_API_KEY not found in .env — skipping SMS parse.',
        );
        return null;
      }

      final model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: apiKey,
        systemInstruction: Content.system(_systemPrompt),
      );

      final response = await model
          .generateContent([Content.text(smsBody)])
          .timeout(const Duration(seconds: 15));

      final raw = response.text?.trim();
      if (raw == null || raw.isEmpty) {
        debugPrint(
          '[GeminiParser] Empty response from Gemini for SMS: "$smsBody"',
        );
        return null;
      }

      // Strip markdown code fences if Gemini adds them despite instructions
      final cleaned =
          raw
              .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
              .replaceAll(RegExp(r'^```\s*', multiLine: true), '')
              .trim();

      final Map<String, dynamic> json = jsonDecode(cleaned);

      return ParsedTransaction(
        amount: (json['amount'] as num).toDouble(),
        type: (json['type'] as String?) ?? 'expense',
        category: (json['category'] as String?) ?? 'other',
        isWant: (json['isWant'] as bool?) ?? false,
      );
    } catch (e, st) {
      debugPrint('[GeminiParser] Error parsing SMS: $e\n$st');
      return null;
    }
  }
}
