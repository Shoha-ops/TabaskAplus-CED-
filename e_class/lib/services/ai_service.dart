import 'package:e_class/services/database_service.dart';
import 'package:e_class/services/api_constants.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:developer';

class AIService {
  final DatabaseService _db;

  // We will try these models in order
  final List<String> _modelsToTry = ['gemini-1.5-flash', 'gemini-pro'];

  AIService(this._db);

  Future<void> processMessage(String text) async {
    final apiKey = ApiConstants.geminiApiKey;

    if (apiKey == 'YOUR_API_KEY_HERE' || apiKey.isEmpty) {
      await _db.sendMessage(
        "I'm sorry, but the AI service is currently unavailable due to maintenance. Please try again later.",
        isBot: true,
      );
      return;
    }

    // Masked key for debugging
    final keyDebug = apiKey.length > 5
        ? "${apiKey.substring(0, 5)}..."
        : "Invalid";

    for (final modelName in _modelsToTry) {
      try {
        log('AI: Trying $modelName with key $keyDebug');

        final model = GenerativeModel(model: modelName, apiKey: apiKey);

        final content = [Content.text(text)];
        final result = await model.generateContent(content);

        final responseText = result.text ?? "I couldn't generate a response.";
        await _db.sendMessage(responseText, isBot: true);
        return; // Success, exit
      } catch (e) {
        log('AI Failed ($modelName): $e');
        // Continue to next model
      }
    }

    // If both failed
    String errorMessage = "Failed to connect to AI (Key: $keyDebug).";
    errorMessage += "\n\nReason: Model not found (404) or Access Denied.";
    errorMessage += "\n\nFIX:";
    errorMessage +=
        "\n1. Go to https://console.cloud.google.com/apis/library/generativelanguage.googleapis.com";
    errorMessage += "\n2. Select the project associated with your API Key.";
    errorMessage += "\n3. Click 'ENABLE' for Generative Language API.";

    await _db.sendMessage(errorMessage, isBot: true);
  }
}
