import 'dart:convert';

import 'package:soliplex_client/src/domain/workbench_layout_validator.dart';

/// Defines an authenticated workbench registration role.
enum WorkbenchRole {
  /// Registers the workspace layout activity.
  layout,

  /// Registers a user-facing content activity.
  content,

  /// Registers a client program activity.
  program,
}

/// A server-issued identity binding for one A2UI activity.
class WorkbenchRegistration {
  /// Creates an authenticated identity binding for one A2UI activity.
  const WorkbenchRegistration({
    required this.role,
    required this.activityMessageId,
    required this.surfaceId,
  });

  /// Parses a registration from its closed JSON representation.
  factory WorkbenchRegistration.fromJson(Map<String, dynamic> json) {
    const allowed = {'role', 'activityMessageId', 'surfaceId'};
    if (json.keys.any((key) => !allowed.contains(key)) ||
        json.length != allowed.length) {
      throw const FormatException('Invalid workbench registration fields');
    }
    final role = switch (json['role']) {
      'layout' => WorkbenchRole.layout,
      'content' => WorkbenchRole.content,
      'program' => WorkbenchRole.program,
      _ => throw const FormatException('Unknown workbench registration role'),
    };
    final activityId = json['activityMessageId'];
    final surfaceId = json['surfaceId'];
    if (!_validId(activityId) || !_validId(surfaceId)) {
      throw const FormatException('Invalid workbench registration identity');
    }
    return WorkbenchRegistration(
      role: role,
      activityMessageId: activityId as String,
      surfaceId: surfaceId as String,
    );
  }

  /// Identifies the registered activity's workbench role.
  final WorkbenchRole role;

  /// Identifies the registered A2UI activity message.
  final String activityMessageId;

  /// Identifies the registered A2UI surface.
  final String surfaceId;
}

/// Holds workbench ordering data beside opaque activity content.
class WorkbenchPartMetadata {
  /// Creates ordering metadata for one publication part.
  const WorkbenchPartMetadata({
    required this.sequence,
    required this.publicationId,
    required this.partIndex,
    required this.partCount,
  });

  /// Identifies the publication sequence.
  final int sequence;

  /// Identifies the publication containing this part.
  final String publicationId;

  /// Gives this part's zero-based position in the publication.
  final int partIndex;

  /// Gives the total number of parts in the publication.
  final int partCount;
}

/// Holds trusted ordering data for one workbench activity.
class WorkbenchActivityMetadata {
  /// Creates metadata for an authenticated workbench activity.
  const WorkbenchActivityMetadata({
    required this.registration,
    required this.revision,
    required this.part,
  });

  /// Parses activity metadata from its closed JSON representation.
  factory WorkbenchActivityMetadata.fromJson(Map<String, dynamic> json) {
    const keys = {
      'role',
      'registration',
      'sequence',
      'revision',
      'publicationId',
      'partIndex',
      'partCount',
    };
    if (json.keys.any((key) => !keys.contains(key)) ||
        json.length != keys.length ||
        json['registration'] is! Map<String, dynamic> ||
        json['sequence'] is! int ||
        (json['sequence'] as int) < 0 ||
        json['revision'] is! int ||
        (json['revision'] as int) < 0 ||
        !_validId(json['publicationId']) ||
        json['partIndex'] is! int ||
        json['partCount'] is! int) {
      throw const FormatException('Malformed workbench activity metadata');
    }
    final registrationJson = json['registration']! as Map<String, dynamic>;
    if (registrationJson.length != 2 ||
        !registrationJson.keys.every(
          {'activityMessageId', 'surfaceId'}.contains,
        )) {
      throw const FormatException('Malformed nested workbench registration');
    }
    final trustedRegistrationJson = Map<String, dynamic>.from(registrationJson);
    trustedRegistrationJson['role'] = json['role'];
    final registration =
        WorkbenchRegistration.fromJson(trustedRegistrationJson);
    final index = json['partIndex'] as int;
    final count = json['partCount'] as int;
    if (index < 0 || count < 1 || index >= count) {
      throw const FormatException('Invalid workbench activity part');
    }
    return WorkbenchActivityMetadata(
      registration: registration,
      revision: json['revision'] as int,
      part: WorkbenchPartMetadata(
        sequence: json['sequence'] as int,
        publicationId: json['publicationId'] as String,
        partIndex: index,
        partCount: count,
      ),
    );
  }

  /// Identifies the server registration for this activity.
  final WorkbenchRegistration registration;

  /// Gives the revision associated with this activity.
  final int revision;

  /// Gives this activity's publication ordering metadata.
  final WorkbenchPartMetadata part;

  /// Returns the publication sequence for this activity.
  int get sequence => part.sequence;

  /// Returns the publication identity for this activity.
  String get publicationId => part.publicationId;

  /// Returns this activity's zero-based publication part index.
  int get partIndex => part.partIndex;

  /// Returns the number of parts in this activity's publication.
  int get partCount => part.partCount;

  /// Serializes this activity metadata to JSON.
  Map<String, dynamic> toJson() => {
        'role': registration.role.name,
        'registration': {
          'activityMessageId': registration.activityMessageId,
          'surfaceId': registration.surfaceId,
        },
        'sequence': part.sequence,
        'revision': revision,
        'publicationId': part.publicationId,
        'partIndex': part.partIndex,
        'partCount': part.partCount,
      };
}

/// One complete part of an ordered publication record.
class WorkbenchPublicationPart {
  /// Creates one complete part of an ordered publication record.
  WorkbenchPublicationPart({
    required this.recordId,
    required this.sequence,
    required this.partIndex,
    required this.partCount,
    required Map<String, dynamic> content,
  }) : content = _validatedPartContent(
          recordId,
          sequence,
          partIndex,
          partCount,
          content,
        );

  /// Parses a publication part from its closed JSON representation.
  factory WorkbenchPublicationPart.fromJson(Map<String, dynamic> json) {
    const fields = {
      'recordId',
      'sequence',
      'partIndex',
      'partCount',
      'content',
    };
    if (json.keys.any((key) => !fields.contains(key)) ||
        json.length != fields.length ||
        !_validId(json['recordId']) ||
        json['sequence'] is! int ||
        json['partIndex'] is! int ||
        json['partCount'] is! int ||
        json['content'] is! Map<String, dynamic>) {
      throw const FormatException('Malformed workbench publication part');
    }
    return WorkbenchPublicationPart(
      recordId: json['recordId'] as String,
      sequence: json['sequence'] as int,
      partIndex: json['partIndex'] as int,
      partCount: json['partCount'] as int,
      content: json['content'] as Map<String, dynamic>,
    );
  }

  /// Creates one complete part of an ordered publication record.
  /// Identifies the publication record.
  final String recordId;

  /// Gives this record's sequence in the publication journal.
  final int sequence;

  /// Gives this part's zero-based position in the record.
  final int partIndex;

  /// Gives the total number of parts in the record.
  final int partCount;

  /// Holds an immutable copy of the part's content.
  final Map<String, dynamic> content;

  /// Returns a stable identity for this part.
  String get identity => '$recordId:$partIndex/$partCount';
}

Map<String, dynamic> _validatedPartContent(
  String recordId,
  int sequence,
  int partIndex,
  int partCount,
  Map<String, dynamic> content,
) {
  if (!_validId(recordId) ||
      sequence < 0 ||
      partCount < 1 ||
      partIndex < 0 ||
      partIndex >= partCount) {
    throw const FormatException('Invalid workbench publication ordering');
  }
  return _freezeMap(content);
}

/// A coherent authenticated snapshot, including all publication parts.
class WorkbenchSnapshot {
  /// Creates an immutable snapshot and orders its publication records.
  WorkbenchSnapshot({
    required this.revision,
    required Map<String, dynamic> layout,
    required List<WorkbenchRegistration> registrations,
    required List<WorkbenchPublicationPart> records,
  })  : layout = _validatedLayout(revision, layout, registrations),
        registrations = List<WorkbenchRegistration>.unmodifiable(
          registrations,
        ),
        records = List<WorkbenchPublicationPart>.unmodifiable(
          _orderedRecords(records),
        );

  /// Parses a snapshot from its closed JSON representation.
  factory WorkbenchSnapshot.fromJson(Map<String, dynamic> json) {
    const fields = {'revision', 'layout', 'registrations', 'records'};
    if (json.keys.any((key) => !fields.contains(key)) ||
        json.length != fields.length ||
        json['revision'] is! int ||
        (json['revision'] as int) < 0 ||
        json['layout'] is! Map<String, dynamic> ||
        json['registrations'] is! List ||
        json['records'] is! List ||
        (json['registrations']! as List).any((item) => item is! Map) ||
        (json['records']! as List).any((item) => item is! Map)) {
      throw const FormatException('Malformed workbench snapshot');
    }
    final registrations = [
      for (final item in json['registrations']! as List)
        WorkbenchRegistration.fromJson(item as Map<String, dynamic>),
    ];
    return WorkbenchSnapshot(
      revision: json['revision'] as int,
      layout: json['layout'] as Map<String, dynamic>,
      registrations: registrations,
      records: [
        for (final item in json['records']! as List)
          WorkbenchPublicationPart.fromJson(item as Map<String, dynamic>),
      ],
    );
  }

  /// Gives the accepted snapshot revision.
  final int revision;

  /// Holds the immutable workspace layout.
  final Map<String, dynamic> layout;

  /// Holds the authenticated registrations in the snapshot.
  final List<WorkbenchRegistration> registrations;

  /// Holds publication parts in deterministic journal order.
  final List<WorkbenchPublicationPart> records;
}

Map<String, dynamic> _validatedLayout(
  int revision,
  Map<String, dynamic> layout,
  List<WorkbenchRegistration> registrations,
) {
  if (revision < 0) {
    throw const FormatException('Invalid workbench snapshot revision');
  }
  validateWorkbenchLayout(layout, registrations);
  return _freezeMap(layout);
}

bool _validId(Object? value) =>
    value is String && RegExp(r'^[A-Za-z][A-Za-z0-9_-]{0,63}$').hasMatch(value);

List<WorkbenchPublicationPart> _orderedRecords(
  List<WorkbenchPublicationPart> records,
) {
  final ordered = [...records]..sort((a, b) {
      final bySequence = a.sequence.compareTo(b.sequence);
      if (bySequence != 0) return bySequence;
      final byRecord = a.recordId.compareTo(b.recordId);
      if (byRecord != 0) return byRecord;
      return a.partIndex.compareTo(b.partIndex);
    });
  final identities = <String>{};
  final partsByRecord = <String, List<WorkbenchPublicationPart>>{};
  for (final record in ordered) {
    if (!identities.add(record.identity)) {
      throw const FormatException('Duplicate workbench publication part');
    }
    partsByRecord.putIfAbsent(record.recordId, () => []).add(record);
  }
  for (final parts in partsByRecord.values) {
    final first = parts.first;
    final indices = parts.map((part) => part.partIndex).toSet();
    if (parts.any(
          (part) =>
              part.partCount != first.partCount ||
              part.sequence != first.sequence,
        ) ||
        indices.length != first.partCount ||
        !List<int>.generate(first.partCount, (index) => index)
            .every(indices.contains)) {
      throw const FormatException('Inconsistent workbench publication parts');
    }
  }
  return ordered;
}

Map<String, dynamic> _freezeMap(Map<String, dynamic> value) {
  try {
    final decoded = jsonDecode(jsonEncode(value));
    return _deepFreezeMap(decoded as Map<String, dynamic>);
  } on FormatException {
    rethrow;
  } on Object {
    throw const FormatException('Value is not JSON encodable');
  }
}

Map<String, dynamic> _deepFreezeMap(Map<String, dynamic> value) =>
    Map.unmodifiable({
      for (final entry in value.entries) entry.key: _freeze(entry.value),
    });

Object? _freeze(Object? value) => switch (value) {
      Map<String, dynamic>() => _deepFreezeMap(value),
      List() => List<Object?>.unmodifiable(value.map(_freeze)),
      _ => value,
    };
