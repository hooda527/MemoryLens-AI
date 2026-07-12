import 'dart:convert';
import 'package:http/http.dart' as http;

enum ProviderType {
  gemini,
  openai,
  claude,
  groq,
  custom,
  firebaseProxy
}

abstract class AIProvider {
  Future<String> analyzeDocument(List<int> fileBytes, String mimeType, String prompt);
  Future<bool> testConnection(String apiKey);
  String get name;
}

class GeminiProvider implements AIProvider {
  final String? apiKey;
  GeminiProvider(this.apiKey);

  @override
  String get name => "Google Gemini";

  @override
  Future<String> analyzeDocument(List<int> fileBytes, String mimeType, String prompt) async {
    if (apiKey == null || apiKey!.isEmpty) throw Exception("API Key is missing");
    final url = Uri.parse("https://generativelanguage.googleapis.com/v1beta/models/gemini-2
    .5-flash:generateContent?key=$apiKey");
    final base64Image = base64Encode(fileBytes);
    final body = {
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inlineData': {
                'mimeType': mimeType,
                'data': base64Image,
              }
            }
          ]
        }
      ]
    };
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception("Gemini analysis failed: ${response.body}");
    }
    final responseJson = jsonDecode(response.body);
    final text = responseJson['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
    if (text == null) throw Exception("Empty response from Gemini");
    return text;
  }

  @override
  Future<bool> testConnection(String apiKey) async {
    final url = Uri.parse("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey");
    final body = {
      'contents': [
        {
          'parts': [
            {'text': 'Hello, reply with "OK" if you read this.'}
          ]
        }
      ]
    };
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return response.statusCode == 200;
  }
}

class OpenAIProvider implements AIProvider {
  final String? apiKey;
  OpenAIProvider(this.apiKey);

  @override
  String get name => "OpenAI GPT-4o";

  @override
  Future<String> analyzeDocument(List<int> fileBytes, String mimeType, String prompt) async {
    if (apiKey == null || apiKey!.isEmpty) throw Exception("API Key is missing");
    final url = Uri.parse("https://api.openai.com/v1/chat/completions");
    final base64Image = base64Encode(fileBytes);
    final body = {
      'model': 'gpt-4o',
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:$mimeType;base64,$base64Image',
              }
            }
          ]
        }
      ]
    };
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception("OpenAI analysis failed: ${response.body}");
    }
    final responseJson = jsonDecode(response.body);
    final text = responseJson['choices']?[0]?['message']?['content'] as String?;
    if (text == null) throw Exception("Empty response from OpenAI");
    return text;
  }

  @override
  Future<bool> testConnection(String apiKey) async {
    final url = Uri.parse("https://api.openai.com/v1/chat/completions");
    final body = {
      'model': 'gpt-4o',
      'messages': [
        {'role': 'user', 'content': 'Hello'}
      ],
      'max_tokens': 5
    };
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(body),
    );
    return response.statusCode == 200;
  }
}

class ClaudeProvider implements AIProvider {
  final String? apiKey;
  ClaudeProvider(this.apiKey);

  @override
  String get name => "Anthropic Claude";

  @override
  Future<String> analyzeDocument(List<int> fileBytes, String mimeType, String prompt) async {
    if (apiKey == null || apiKey!.isEmpty) throw Exception("API Key is missing");
    final url = Uri.parse("https://api.anthropic.com/v1/messages");
    final base64Image = base64Encode(fileBytes);
    final body = {
      'model': 'claude-3-5-sonnet-20241022',
      'max_tokens': 1024,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image',
              'source': {
                'type': 'base64',
                'media_type': mimeType,
                'data': base64Image,
              }
            },
            {'type': 'text', 'text': prompt}
          ]
        }
      ]
    };
    final response = await http.post(
      url,
      headers: {
        'content-type': 'application/json',
        'x-api-key': apiKey!,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception("Claude analysis failed: ${response.body}");
    }
    final responseJson = jsonDecode(response.body);
    final text = responseJson['content']?[0]?['text'] as String?;
    if (text == null) throw Exception("Empty response from Claude");
    return text;
  }

  @override
  Future<bool> testConnection(String apiKey) async {
    final url = Uri.parse("https://api.anthropic.com/v1/messages");
    final body = {
      'model': 'claude-3-5-sonnet-20241022',
      'max_tokens': 5,
      'messages': [
        {'role': 'user', 'content': 'Hello'}
      ]
    };
    final response = await http.post(
      url,
      headers: {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode(body),
    );
    return response.statusCode == 200;
  }
}

class GroqProvider implements AIProvider {
  final String? apiKey;
  GroqProvider(this.apiKey);

  @override
  String get name => "Groq Llama 3";

  @override
  Future<String> analyzeDocument(List<int> fileBytes, String mimeType, String prompt) async {
    if (apiKey == null || apiKey!.isEmpty) throw Exception("API Key is missing");
    final url = Uri.parse("https://api.groq.com/openai/v1/chat/completions");
    final base64Image = base64Encode(fileBytes);
    final body = {
      'model': 'llama-3.2-11b-vision-preview',
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:$mimeType;base64,$base64Image',
              }
            }
          ]
        }
      ]
    };
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception("Groq analysis failed: ${response.body}");
    }
    final responseJson = jsonDecode(response.body);
    final text = responseJson['choices']?[0]?['message']?['content'] as String?;
    if (text == null) throw Exception("Empty response from Groq");
    return text;
  }

  @override
  Future<bool> testConnection(String apiKey) async {
    final url = Uri.parse("https://api.groq.com/openai/v1/chat/completions");
    final body = {
      'model': 'llama-3.2-11b-vision-preview',
      'messages': [
        {'role': 'user', 'content': 'Hello'}
      ],
      'max_tokens': 5
    };
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(body),
    );
    return response.statusCode == 200;
  }
}

class CustomProvider implements AIProvider {
  final String? apiKey;
  final String? baseUrl;
  final String? model;
  CustomProvider({this.apiKey, this.baseUrl, this.model});

  @override
  String get name => "Custom OpenAI compatible API";

  @override
  Future<String> analyzeDocument(List<int> fileBytes, String mimeType, String prompt) async {
    if (apiKey == null || apiKey!.isEmpty) throw Exception("API Key is missing");
    if (baseUrl == null || baseUrl!.isEmpty) throw Exception("Base URL is missing");
    final url = Uri.parse("$baseUrl/chat/completions");
    final base64Image = base64Encode(fileBytes);
    final body = {
      'model': model ?? 'default',
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {
                'url': 'data:$mimeType;base64,$base64Image',
              }
            }
          ]
        }
      ]
    };
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception("Custom Provider analysis failed: ${response.body}");
    }
    final responseJson = jsonDecode(response.body);
    final text = responseJson['choices']?[0]?['message']?['content'] as String?;
    if (text == null) throw Exception("Empty response from Custom Provider");
    return text;
  }

  @override
  Future<bool> testConnection(String apiKey) async {
    if (baseUrl == null || baseUrl!.isEmpty) return false;
    final url = Uri.parse("$baseUrl/chat/completions");
    final body = {
      'model': model ?? 'default',
      'messages': [
        {'role': 'user', 'content': 'Hello'}
      ],
      'max_tokens': 5
    };
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(body),
    );
    return response.statusCode == 200;
  }
}

class FirebaseProxyProvider implements AIProvider {
  final String functionUrl = "https://us-central1-memorylens-ai.cloudfunctions.net/analyzeDocumentProxy";

  @override
  String get name => "MemoryLens AI Free Tier";

  @override
  Future<String> analyzeDocument(List<int> fileBytes, String mimeType, String prompt) async {
    final url = Uri.parse(functionUrl);
    final base64Image = base64Encode(fileBytes);
    final body = {
      'mimeType': mimeType,
      'image': base64Image,
      'prompt': prompt,
    };
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception("Free Tier Proxy failed: ${response.body}");
    }
    final responseJson = jsonDecode(response.body);
    final text = responseJson['text'] as String?;
    if (text == null) throw Exception("Empty response from Proxy");
    return text;
  }

  @override
  Future<bool> testConnection(String apiKey) async {
    return true; // Proxy bypass
  }
}
