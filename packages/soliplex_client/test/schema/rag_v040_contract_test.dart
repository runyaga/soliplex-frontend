// ignore_for_file: prefer_const_constructors

import 'dart:convert';

import 'package:soliplex_client/src/schema/agui_features/rag.dart';
import 'package:soliplex_client/src/schema/agui_features/rag_v040.dart';
import 'package:test/test.dart';

/// Contract tests for the haiku.rag 0.40 RAG state schema.
///
/// The 0.40 schema emits the `rag` namespace with `citations` as a list of
/// inline `Citation` objects, plus `qa_history`, `documents`, and `reports` —
/// fields removed in 0.42. These types are kept hand-written (not generated)
/// because 0.40 is end-of-life.
void main() {
  group('RagV040 contract', () {
    test('fromJson with empty Map yields empty defaults for list fields', () {
      final rag = RagV040.fromJson(<String, dynamic>{});
      expect(rag.citations, isEmpty);
      expect(rag.qaHistory, isEmpty);
      expect(rag.documents, isEmpty);
      expect(rag.reports, isEmpty);
      expect(rag.documentFilter, isNull);
      expect(rag.searches, isNull);
    });

    test('parses full 0.40 RAGState payload', () {
      final json = {
        'citations': [
          {
            'chunk_id': 'c1',
            'content': 'text',
            'document_id': 'd1',
            'document_uri': 'uri',
          },
        ],
        'qa_history': [
          {
            'question': 'q?',
            'answer': 'a',
          },
        ],
        'document_filter': "id = 'abc'",
        'searches': {
          'q1': [
            {'content': 'result', 'score': 0.9},
          ],
        },
        'documents': [
          {'title': 'Doc 1', 'uri': 'uri1', 'created': '2025-01-01'},
        ],
        'reports': [
          {
            'question': 'q?',
            'title': 'T',
            'executive_summary': 'summary',
          },
        ],
      };

      final rag = RagV040.fromJson(json);
      expect(rag.citations, hasLength(1));
      expect(rag.citations!.first.chunkId, equals('c1'));
      expect(rag.qaHistory, hasLength(1));
      expect(rag.qaHistory!.first.question, equals('q?'));
      expect(rag.documentFilter, equals("id = 'abc'"));
      expect(rag.searches, hasLength(1));
      expect(rag.documents, hasLength(1));
      expect(rag.documents!.first.title, equals('Doc 1'));
      expect(rag.reports, hasLength(1));
      expect(rag.reports!.first.executiveSummary, equals('summary'));
    });

    test('STATE_DELTA-style partial payload parses without crashing', () {
      // Backend may omit most fields in a delta.
      final json = {
        'document_filter': "id = 'x'",
      };
      final rag = RagV040.fromJson(json);
      expect(rag.documentFilter, equals("id = 'x'"));
      expect(rag.citations, isEmpty);
      expect(rag.qaHistory, isEmpty);
    });

    test('ignores extra keys without crashing', () {
      final json = <String, dynamic>{
        'citations': <dynamic>[],
        'unknown_future_field': 42,
      };
      final rag = RagV040.fromJson(json);
      expect(rag.citations, isEmpty);
    });

    test('roundtrips a fully-populated RagV040', () {
      final original = RagV040(
        citations: [
          Citation(
            chunkId: 'c1',
            content: 'text',
            documentId: 'd1',
            documentUri: 'uri',
          ),
        ],
        qaHistory: [
          QaHistoryEntry(question: 'q?', answer: 'a'),
        ],
        documentFilter: 'filter',
        searches: {
          'q': [SearchResult(content: 'r', score: 0.9)],
        },
        documents: [
          DocumentInfo(title: 'T', uri: 'u', created: '2025-01-01'),
        ],
        reports: [
          ResearchEntry(
            question: 'q?',
            title: 'Title',
            executiveSummary: 'summary',
          ),
        ],
      );

      final jsonString = jsonEncode(original.toJson());
      final decoded = RagV040.fromJson(
        jsonDecode(jsonString) as Map<String, dynamic>,
      );
      expect(decoded.citations, hasLength(1));
      expect(decoded.qaHistory, hasLength(1));
      expect(decoded.documentFilter, equals('filter'));
      expect(decoded.searches, hasLength(1));
      expect(decoded.documents, hasLength(1));
      expect(decoded.reports, hasLength(1));
    });
  });

  group('QaHistoryEntry contract', () {
    test('JSON keys match backend QAHistoryEntry', () {
      final json = {
        'question': 'q?',
        'answer': 'a',
        'confidence': 0.75,
        'citations': [
          {
            'chunk_id': 'c1',
            'content': 'text',
            'document_id': 'd1',
            'document_uri': 'uri',
          },
        ],
      };
      final entry = QaHistoryEntry.fromJson(json);
      expect(entry.question, equals('q?'));
      expect(entry.answer, equals('a'));
      expect(entry.confidence, equals(0.75));
      expect(entry.citations, hasLength(1));
      expect(entry.citations!.first.chunkId, equals('c1'));
    });

    test('confidence defaults to 0.9 when absent in JSON', () {
      final entry = QaHistoryEntry.fromJson({
        'question': 'q?',
        'answer': 'a',
      });
      expect(entry.confidence, equals(0.9));
    });

    test('roundtrip', () {
      final original = QaHistoryEntry(
        question: 'q?',
        answer: 'a',
        confidence: 0.5,
        citations: [
          Citation(
            chunkId: 'c1',
            content: 'text',
            documentId: 'd1',
            documentUri: 'uri',
          ),
        ],
      );
      final decoded = QaHistoryEntry.fromJson(original.toJson());
      expect(decoded.question, equals(original.question));
      expect(decoded.answer, equals(original.answer));
      expect(decoded.confidence, equals(original.confidence));
      expect(decoded.citations, hasLength(1));
    });
  });

  group('DocumentInfo contract', () {
    test('JSON keys match backend DocumentInfo', () {
      final json = {
        'id': 'doc-1',
        'title': 'T',
        'uri': 'u',
        'created': '2025-01-01',
      };
      final doc = DocumentInfo.fromJson(json);
      expect(doc.id, equals('doc-1'));
      expect(doc.title, equals('T'));
      expect(doc.uri, equals('u'));
      expect(doc.created, equals('2025-01-01'));
    });

    test('roundtrip', () {
      final original = DocumentInfo(
        id: 'd',
        title: 'T',
        uri: 'u',
        created: '2025-01-01',
      );
      final decoded = DocumentInfo.fromJson(original.toJson());
      expect(decoded.id, equals(original.id));
      expect(decoded.title, equals(original.title));
      expect(decoded.uri, equals(original.uri));
      expect(decoded.created, equals(original.created));
    });
  });

  group('ResearchEntry contract', () {
    test('JSON keys match backend ResearchEntry', () {
      final json = {
        'question': 'q?',
        'title': 'T',
        'executive_summary': 'summary',
      };
      final entry = ResearchEntry.fromJson(json);
      expect(entry.question, equals('q?'));
      expect(entry.title, equals('T'));
      expect(entry.executiveSummary, equals('summary'));
    });

    test('roundtrip', () {
      final original = ResearchEntry(
        question: 'q?',
        title: 'T',
        executiveSummary: 'summary',
      );
      final decoded = ResearchEntry.fromJson(original.toJson());
      expect(decoded.question, equals(original.question));
      expect(decoded.title, equals(original.title));
      expect(decoded.executiveSummary, equals(original.executiveSummary));
    });
  });
}
