import 'package:flutter_test/flutter_test.dart';
import 'package:memorylens_ai/models/document_model.dart';
import 'package:memorylens_ai/services/ai_provider.dart';
import 'package:memorylens_ai/services/extraction_service.dart';

class MockAIProvider implements AIProvider {
  final String mockResponse;

  MockAIProvider(this.mockResponse);

  @override
  String get name => "Mock Provider";

  @override
  Future<String> analyzeDocument(List<int> fileBytes, String mimeType, String prompt) async {
    return mockResponse;
  }

  @override
  Future<bool> testConnection(String apiKey) async {
    return true;
  }
}

void main() {
  group('ExtractionService JSON Parsing & Validation Tests', () {
    test('Successful Parsing of Complete Bill JSON', () async {
      const mockJson = """
      {
        "category": "bill",
        "summary": "Electricity bill for June.",
        "rawText": "Power Corp. Due: 2026-07-20. Total: 150.00",
        "billData": {
          "vendor": "Power Corp",
          "amount": 150.00,
          "currency": "USD",
          "dueDate": "2026-07-20",
          "accountNumber": "AC-99281"
        }
      }
      """;

      final service = ExtractionService(MockAIProvider(mockJson));
      final result = await service.extractFromBytes([], 'image/jpeg', 'user123');

      expect(result.success, isTrue);
      expect(result.document, isNotNull);
      
      final doc = result.document!;
      expect(doc.category, DocumentCategory.bill);
      expect(doc.displayTitle, "Power Corp");
      expect(doc.billData?.amount, 150.00);
      expect(doc.billData?.dueDate, DateTime(2026, 7, 20));
      expect(doc.unextractedFields, isEmpty);
    });

    test('Incomplete Extraction Correctly Sets Missing Fields to Null (No Fabricated Data)', () async {
      const mockJson = """
      {
        "category": "bill",
        "summary": "Water bill with missing date and account number.",
        "rawText": "Water Inc. Total: 45.00",
        "billData": {
          "vendor": "Water Inc",
          "amount": 45.00,
          "currency": null,
          "dueDate": null,
          "accountNumber": null
        }
      }
      """;

      final service = ExtractionService(MockAIProvider(mockJson));
      final result = await service.extractFromBytes([], 'image/jpeg', 'user123');

      expect(result.success, isTrue);
      final doc = result.document!;
      expect(doc.billData?.vendor, "Water Inc");
      expect(doc.billData?.amount, 45.00);
      
      // Verification that missing fields are null (not filled with fabricated placeholder values)
      expect(doc.billData?.currency, isNull);
      expect(doc.billData?.dueDate, isNull);
      expect(doc.billData?.accountNumber, isNull);
      
      // Verification that missing fields are captured in unextractedFields list for UI notification
      expect(doc.unextractedFields, contains('currency'));
      expect(doc.unextractedFields, contains('dueDate'));
      expect(doc.unextractedFields, contains('accountNumber'));
    });

    test('Malformed Date Format Correctly Sets Field to Null and flags it', () async {
      const mockJson = """
      {
        "category": "prescription",
        "summary": "Medicine prescription with malformed expiry date.",
        "rawText": "Ibuprofen. Expiry: Unknown/ASAP.",
        "prescriptionData": {
          "medicineName": "Ibuprofen",
          "dosage": "400mg",
          "expiryDate": "Unknown/ASAP",
          "doctorName": "Dr. Smith"
        }
      }
      """;

      final service = ExtractionService(MockAIProvider(mockJson));
      final result = await service.extractFromBytes([], 'image/jpeg', 'user123');

      expect(result.success, isTrue);
      final doc = result.document!;
      expect(doc.prescriptionData?.medicineName, "Ibuprofen");
      
      // Malformed date should be parsed as null and flagged in unextractedFields
      expect(doc.prescriptionData?.expiryDate, isNull);
      expect(doc.unextractedFields, contains('expiryDate'));
    });
  });
}
