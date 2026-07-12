import 'package:cloud_firestore/cloud_firestore.dart';

enum DocumentCategory {
  bill,
  prescription,
  ticket,
  receipt,
  exam,
  notice,
  other
}

class BillData {
  final String? vendor;
  final double? amount;
  final String? currency;
  final DateTime? dueDate;
  final String? accountNumber;

  BillData({
    this.vendor,
    this.amount,
    this.currency,
    this.dueDate,
    this.accountNumber,
  });

  Map<String, dynamic> toMap() {
    return {
      'vendor': vendor,
      'amount': amount,
      'currency': currency,
      'dueDate': dueDate?.toIso8601String(),
      'accountNumber': accountNumber,
    };
  }

  factory BillData.fromMap(Map<String, dynamic> map) {
    return BillData(
      vendor: map['vendor'] as String?,
      amount: (map['amount'] as num?)?.toDouble(),
      currency: map['currency'] as String?,
      dueDate: map['dueDate'] != null ? DateTime.tryParse(map['dueDate'] as String) : null,
      accountNumber: map['accountNumber'] as String?,
    );
  }
}

class PrescriptionData {
  final String? medicineName;
  final String? dosage;
  final DateTime? expiryDate;
  final String? doctorName;
  final String? patientName;

  PrescriptionData({
    this.medicineName,
    this.dosage,
    this.expiryDate,
    this.doctorName,
    this.patientName,
  });

  Map<String, dynamic> toMap() {
    return {
      'medicineName': medicineName,
      'dosage': dosage,
      'expiryDate': expiryDate?.toIso8601String(),
      'doctorName': doctorName,
      'patientName': patientName,
    };
  }

  factory PrescriptionData.fromMap(Map<String, dynamic> map) {
    return PrescriptionData(
      medicineName: map['medicineName'] as String?,
      dosage: map['dosage'] as String?,
      expiryDate: map['expiryDate'] != null ? DateTime.tryParse(map['expiryDate'] as String) : null,
      doctorName: map['doctorName'] as String?,
      patientName: map['patientName'] as String?,
    );
  }
}

class TicketData {
  final String? eventName;
  final DateTime? eventDate;
  final String? venue;
  final String? seatNumber;
  final double? price;

  TicketData({
    this.eventName,
    this.eventDate,
    this.venue,
    this.seatNumber,
    this.price,
  });

  Map<String, dynamic> toMap() {
    return {
      'eventName': eventName,
      'eventDate': eventDate?.toIso8601String(),
      'venue': venue,
      'seatNumber': seatNumber,
      'price': price,
    };
  }

  factory TicketData.fromMap(Map<String, dynamic> map) {
    return TicketData(
      eventName: map['eventName'] as String?,
      eventDate: map['eventDate'] != null ? DateTime.tryParse(map['eventDate'] as String) : null,
      venue: map['venue'] as String?,
      seatNumber: map['seatNumber'] as String?,
      price: (map['price'] as num?)?.toDouble(),
    );
  }
}

class ReceiptData {
  final String? storeName;
  final double? totalAmount;
  final String? currency;
  final DateTime? purchaseDate;
  final List<String>? items;

  ReceiptData({
    this.storeName,
    this.totalAmount,
    this.currency,
    this.purchaseDate,
    this.items,
  });

  Map<String, dynamic> toMap() {
    return {
      'storeName': storeName,
      'totalAmount': totalAmount,
      'currency': currency,
      'purchaseDate': purchaseDate?.toIso8601String(),
      'items': items,
    };
  }

  factory ReceiptData.fromMap(Map<String, dynamic> map) {
    return ReceiptData(
      storeName: map['storeName'] as String?,
      totalAmount: (map['totalAmount'] as num?)?.toDouble(),
      currency: map['currency'] as String?,
      purchaseDate: map['purchaseDate'] != null ? DateTime.tryParse(map['purchaseDate'] as String) : null,
      items: map['items'] != null ? List<String>.from(map['items'] as Iterable) : null,
    );
  }
}

class ExamData {
  final String? subject;
  final DateTime? examDate;
  final String? venue;
  final String? studentName;

  ExamData({
    this.subject,
    this.examDate,
    this.venue,
    this.studentName,
  });

  Map<String, dynamic> toMap() {
    return {
      'subject': subject,
      'examDate': examDate?.toIso8601String(),
      'venue': venue,
      'studentName': studentName,
    };
  }

  factory ExamData.fromMap(Map<String, dynamic> map) {
    return ExamData(
      subject: map['subject'] as String?,
      examDate: map['examDate'] != null ? DateTime.tryParse(map['examDate'] as String) : null,
      venue: map['venue'] as String?,
      studentName: map['studentName'] as String?,
    );
  }
}

class NoticeData {
  final String? title;
  final String? issuedBy;
  final DateTime? issuedDate;
  final DateTime? deadlineDate;

  NoticeData({
    this.title,
    this.issuedBy,
    this.issuedDate,
    this.deadlineDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'issuedBy': issuedBy,
      'issuedDate': issuedDate?.toIso8601String(),
      'deadlineDate': deadlineDate?.toIso8601String(),
    };
  }

  factory NoticeData.fromMap(Map<String, dynamic> map) {
    return NoticeData(
      title: map['title'] as String?,
      issuedBy: map['issuedBy'] as String?,
      issuedDate: map['issuedDate'] != null ? DateTime.tryParse(map['issuedDate'] as String) : null,
      deadlineDate: map['deadlineDate'] != null ? DateTime.tryParse(map['deadlineDate'] as String) : null,
    );
  }
}

class DocumentModel {
  final String id;
  final String userId;
  final DocumentCategory category;
  final String? rawText;
  final String? aiSummary;
  final BillData? billData;
  final PrescriptionData? prescriptionData;
  final TicketData? ticketData;
  final ReceiptData? receiptData;
  final ExamData? examData;
  final NoticeData? noticeData;
  final DateTime createdAt;
  final String? imageUrl;
  final List<String> unextractedFields;

  DocumentModel({
    required this.id,
    required this.userId,
    required this.category,
    this.rawText,
    this.aiSummary,
    this.billData,
    this.prescriptionData,
    this.ticketData,
    this.receiptData,
    this.examData,
    this.noticeData,
    required this.createdAt,
    this.imageUrl,
    this.unextractedFields = const [],
  });

  DateTime? get primaryDate {
    switch (category) {
      case DocumentCategory.bill:
        return billData?.dueDate;
      case DocumentCategory.prescription:
        return prescriptionData?.expiryDate;
      case DocumentCategory.ticket:
        return ticketData?.eventDate;
      case DocumentCategory.receipt:
        return receiptData?.purchaseDate;
      case DocumentCategory.exam:
        return examData?.examDate;
      case DocumentCategory.notice:
        return noticeData?.deadlineDate ?? noticeData?.issuedDate;
      case DocumentCategory.other:
        return null;
    }
  }

  String get displayTitle {
    switch (category) {
      case DocumentCategory.bill:
        return billData?.vendor ?? 'Unnamed Bill';
      case DocumentCategory.prescription:
        return prescriptionData?.medicineName ?? 'Unnamed Prescription';
      case DocumentCategory.ticket:
        return ticketData?.eventName ?? 'Unnamed Ticket';
      case DocumentCategory.receipt:
        return receiptData?.storeName ?? 'Unnamed Receipt';
      case DocumentCategory.exam:
        return examData?.subject ?? 'Unnamed Exam';
      case DocumentCategory.notice:
        return noticeData?.title ?? 'Unnamed Notice';
      case DocumentCategory.other:
        return 'Other Document';
    }
  }

  DocumentModel copyWith({
    String? id,
    String? userId,
    DocumentCategory? category,
    String? rawText,
    String? aiSummary,
    BillData? billData,
    PrescriptionData? prescriptionData,
    TicketData? ticketData,
    ReceiptData? receiptData,
    ExamData? examData,
    NoticeData? noticeData,
    DateTime? createdAt,
    String? imageUrl,
    List<String>? unextractedFields,
  }) {
    return DocumentModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      category: category ?? this.category,
      rawText: rawText ?? this.rawText,
      aiSummary: aiSummary ?? this.aiSummary,
      billData: billData ?? this.billData,
      prescriptionData: prescriptionData ?? this.prescriptionData,
      ticketData: ticketData ?? this.ticketData,
      receiptData: receiptData ?? this.receiptData,
      examData: examData ?? this.examData,
      noticeData: noticeData ?? this.noticeData,
      createdAt: createdAt ?? this.createdAt,
      imageUrl: imageUrl ?? this.imageUrl,
      unextractedFields: unextractedFields ?? this.unextractedFields,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'category': category.name,
      'rawText': rawText,
      'aiSummary': aiSummary,
      'billData': billData?.toMap(),
      'prescriptionData': prescriptionData?.toMap(),
      'ticketData': ticketData?.toMap(),
      'receiptData': receiptData?.toMap(),
      'examData': examData?.toMap(),
      'noticeData': noticeData?.toMap(),
      'createdAt': createdAt.toIso8601String(),
      'imageUrl': imageUrl,
      'unextractedFields': unextractedFields,
    };
  }

  factory DocumentModel.fromMap(Map<String, dynamic> map) {
    return DocumentModel(
      id: map['id'] as String,
      userId: map['userId'] as String,
      category: DocumentCategory.values.firstWhere((e) => e.name == map['category']),
      rawText: map['rawText'] as String?,
      aiSummary: map['aiSummary'] as String?,
      billData: map['billData'] != null ? BillData.fromMap(map['billData'] as Map<String, dynamic>) : null,
      prescriptionData: map['prescriptionData'] != null ? PrescriptionData.fromMap(map['prescriptionData'] as Map<String, dynamic>) : null,
      ticketData: map['ticketData'] != null ? TicketData.fromMap(map['ticketData'] as Map<String, dynamic>) : null,
      receiptData: map['receiptData'] != null ? ReceiptData.fromMap(map['receiptData'] as Map<String, dynamic>) : null,
      examData: map['examData'] != null ? ExamData.fromMap(map['examData'] as Map<String, dynamic>) : null,
      noticeData: map['noticeData'] != null ? NoticeData.fromMap(map['noticeData'] as Map<String, dynamic>) : null,
      createdAt: DateTime.parse(map['createdAt'] as String),
      imageUrl: map['imageUrl'] as String?,
      unextractedFields: map['unextractedFields'] != null ? List<String>.from(map['unextractedFields'] as Iterable) : const [],
    );
  }
}
