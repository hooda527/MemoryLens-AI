import 'dart:convert';
import 'package:memorylens_ai/models/document_model.dart';
import 'package:memorylens_ai/services/ai_provider.dart';
import 'package:uuid/uuid.dart';

class ExtractionResult {
  final DocumentModel? document;
  final String? error;
  final bool success;

  ExtractionResult({this.document, this.error, required this.success});
}

class ExtractionService {
  final AIProvider provider;

  ExtractionService(this.provider);

  static const String _extractionPrompt = """
You are an expert OCR and Document Analyzer. Your job is to analyze the provided document/image and return a clean, valid JSON object containing only the extracted values. Do not write any explanations or Markdown code fences (e.g. do not wrap in ```json).

You must categorize the document as one of these: 'bill', 'prescription', 'ticket', 'receipt', 'exam', 'notice', 'other'.

Based on the category, extract the specific fields. If a field cannot be found or is unclear, return null for its value. Never invent, guess, or substitute default/mock values.

Expected Output Format:
{
  "category": "bill | prescription | ticket | receipt | exam | notice | other",
  "summary": "Short AI description of the document contents.",
  "rawText": "A complete dump of visible text extracted from the document.",
  "billData": {
    "vendor": "String or null",
    "amount": 0.0 or null,
    "currency": "String or null",
    "dueDate": "ISO 8601 Date String YYYY-MM-DD or null",
    "accountNumber": "String or null"
  },
  "prescriptionData": {
    "medicineName": "String or null",
    "dosage": "String or null",
    "expiryDate": "ISO 8601 Date String YYYY-MM-DD or null",
    "doctorName": "String or null",
    "patientName": "String or null"
  },
  "ticketData": {
    "eventName": "String or null",
    "eventDate": "ISO 8601 Date String YYYY-MM-DD or null",
    "venue": "String or null",
    "seatNumber": "String or null",
    "price": 0.0 or null
  },
  "receiptData": {
    "storeName": "String or null",
    "totalAmount": 0.0 or null,
    "currency": "String or null",
    "purchaseDate": "ISO 8601 Date String YYYY-MM-DD or null",
    "items": ["String"] or null
  },
  "examData": {
    "subject": "String or null",
    "examDate": "ISO 8601 Date String YYYY-MM-DD or null",
    "venue": "String or null",
    "studentName": "String or null"
  },
  "noticeData": {
    "title": "String or null",
    "issuedBy": "String or null",
    "issuedDate": "ISO 8601 Date String YYYY-MM-DD or null",
    "deadlineDate": "ISO 8601 Date String YYYY-MM-DD or null"
  }
}
""";

  Future<ExtractionResult> extractFromBytes(List<int> bytes, String mimeType, String userId) async {
    try {
      String response = await provider.analyzeDocument(bytes, mimeType, _extractionPrompt);
      
      // Clean markdown formatting if present
      response = response.trim();
      if (response.startsWith("```json")) {
        response = response.substring(7);
      }
      if (response.endsWith("```")) {
        response = response.substring(0, response.length - 3);
      }
      response = response.trim();

      final json = jsonDecode(response) as Map<String, dynamic>;
      final model = _parseDocumentModel(json, userId);
      return ExtractionResult(document: model, success: true);
    } catch (e) {
      return ExtractionResult(error: e.toString(), success: false);
    }
  }

  DocumentModel _parseDocumentModel(Map<String, dynamic> json, String userId) {
    final categoryStr = json['category'] as String? ?? 'other';
    final category = DocumentCategory.values.firstWhere(
      (e) => e.name == categoryStr.toLowerCase(),
      orElse: () => DocumentCategory.other,
    );

    final rawText = json['rawText'] as String?;
    final summary = json['summary'] as String?;
    final List<String> unextracted = [];

    BillData? bill;
    PrescriptionData? prescription;
    TicketData? ticket;
    ReceiptData? receipt;
    ExamData? exam;
    NoticeData? notice;

    if (category == DocumentCategory.bill) {
      final data = json['billData'] as Map<String, dynamic>? ?? {};
      bill = BillData(
        vendor: _parseString(data['vendor'], 'vendor', unextracted),
        amount: _parseDouble(data['amount'], 'amount', unextracted),
        currency: _parseString(data['currency'], 'currency', unextracted),
        dueDate: _parseDate(data['dueDate'], 'dueDate', unextracted),
        accountNumber: _parseString(data['accountNumber'], 'accountNumber', unextracted),
      );
    } else if (category == DocumentCategory.prescription) {
      final data = json['prescriptionData'] as Map<String, dynamic>? ?? {};
      prescription = PrescriptionData(
        medicineName: _parseString(data['medicineName'], 'medicineName', unextracted),
        dosage: _parseString(data['dosage'], 'dosage', unextracted),
        expiryDate: _parseDate(data['expiryDate'], 'expiryDate', unextracted),
        doctorName: _parseString(data['doctorName'], 'doctorName', unextracted),
        patientName: _parseString(data['patientName'], 'patientName', unextracted),
      );
    } else if (category == DocumentCategory.ticket) {
      final data = json['ticketData'] as Map<String, dynamic>? ?? {};
      ticket = TicketData(
        eventName: _parseString(data['eventName'], 'eventName', unextracted),
        eventDate: _parseDate(data['eventDate'], 'eventDate', unextracted),
        venue: _parseString(data['venue'], 'venue', unextracted),
        seatNumber: _parseString(data['seatNumber'], 'seatNumber', unextracted),
        price: _parseDouble(data['price'], 'price', unextracted),
      );
    } else if (category == DocumentCategory.receipt) {
      final data = json['receiptData'] as Map<String, dynamic>? ?? {};
      receipt = ReceiptData(
        storeName: _parseString(data['storeName'], 'storeName', unextracted),
        totalAmount: _parseDouble(data['totalAmount'], 'totalAmount', unextracted),
        currency: _parseString(data['currency'], 'currency', unextracted),
        purchaseDate: _parseDate(data['purchaseDate'], 'purchaseDate', unextracted),
        items: data['items'] != null ? List<String>.from(data['items'] as Iterable) : null,
      );
      if (receipt.storeName == null) unextracted.add('storeName');
      if (receipt.totalAmount == null) unextracted.add('totalAmount');
    } else if (category == DocumentCategory.exam) {
      final data = json['examData'] as Map<String, dynamic>? ?? {};
      exam = ExamData(
        subject: _parseString(data['subject'], 'subject', unextracted),
        examDate: _parseDate(data['examDate'], 'examDate', unextracted),
        venue: _parseString(data['venue'], 'venue', unextracted),
        studentName: _parseString(data['studentName'], 'studentName', unextracted),
      );
    } else if (category == DocumentCategory.notice) {
      final data = json['noticeData'] as Map<String, dynamic>? ?? {};
      notice = NoticeData(
        title: _parseString(data['title'], 'title', unextracted),
        issuedBy: _parseString(data['issuedBy'], 'issuedBy', unextracted),
        issuedDate: _parseDate(data['issuedDate'], 'issuedDate', unextracted),
        deadlineDate: _parseDate(data['deadlineDate'], 'deadlineDate', unextracted),
      );
    }

    return DocumentModel(
      id: const Uuid().v4(),
      userId: userId,
      category: category,
      rawText: rawText,
      aiSummary: summary,
      billData: bill,
      prescriptionData: prescription,
      ticketData: ticket,
      receiptData: receipt,
      examData: exam,
      noticeData: notice,
      createdAt: DateTime.now(),
      unextractedFields: unextracted,
    );
  }

  String? _parseString(dynamic val, String name, List<String> unextracted) {
    if (val == null || val.toString().trim().isEmpty) {
      unextracted.add(name);
      return null;
    }
    return val.toString();
  }

  double? _parseDouble(dynamic val, String name, List<String> unextracted) {
    if (val == null) {
      unextracted.add(name);
      return null;
    }
    if (val is num) return val.toDouble();
    final parsed = double.tryParse(val.toString());
    if (parsed == null) unextracted.add(name);
    return parsed;
  }

  DateTime? _parseDate(dynamic val, String name, List<String> unextracted) {
    if (val == null || val.toString().isEmpty) {
      unextracted.add(name);
      return null;
    }
    final parsed = DateTime.tryParse(val.toString());
    if (parsed == null) unextracted.add(name);
    return parsed;
  }
}
