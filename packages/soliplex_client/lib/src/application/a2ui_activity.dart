import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:soliplex_client/src/domain/activity_record.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_client/src/domain/conversation.dart';
import 'package:soliplex_client/src/domain/workbench_snapshot.dart';
import 'package:soliplex_client/src/errors/exceptions.dart';

/// The activity discriminator used by AG-UI's A2UI middleware.
const a2uiActivityType = 'a2ui-surface';

/// Projects a canonical activity snapshot into one generated chat message.
Conversation projectA2uiActivity(
  Conversation conversation,
  ActivityRecord activity, {
  required DateTime? createdAt,
  List<WorkbenchRegistration> registeredWorkbenchActivities = const [],
}) {
  final Map<String, dynamic> content;
  try {
    content = jsonDecode(jsonEncode(activity.content)) as Map<String, dynamic>;
  } on Object {
    _malformed(activity.messageId, 'JSON content');
  }
  final List<Map<String, dynamic>> messages;
  final status = content['status'];
  if (content.containsKey('a2ui_operations')) {
    final raw = content['a2ui_operations'];
    if (raw is! List) _malformed(activity.messageId, 'a2ui_operations');
    messages = [
      for (final operation in raw) _operation(operation, activity.messageId),
    ];
  } else if (const ['building', 'retrying', 'failed'].contains(status)) {
    messages = [];
  } else {
    _malformed(activity.messageId, 'a2ui_operations or lifecycle status');
  }

  final index = conversation.messages.indexWhere(
    (message) => message.id == activity.messageId,
  );
  final existing = index < 0 ? null : conversation.messages[index];
  if (existing != null &&
      (existing is! GenUiMessage || existing.widgetName != 'a2ui')) {
    _malformed(activity.messageId, 'message identity');
  }
  final ownedConversation = conversation.copyWith(
    activities: [
      for (final record in conversation.activities)
        if (record.messageId == activity.messageId)
          record.copyWith(content: content)
        else
          record,
    ],
  );

  final workbenchMetadata = content['workbench'];
  final metadata = workbenchMetadata == null
      ? null
      : _workbenchMetadata(
          workbenchMetadata,
          activity.messageId,
          messages,
          registeredWorkbenchActivities,
        );

  // This closed role binding is issued by the server's deterministic tools,
  // on canonical activities only. Names and data-model keys grant no role.
  WorkbenchRegistration? publication;
  final rawPublication = content['workbenchPublication'];
  if (rawPublication is Map<String, dynamic>) {
    try {
      final candidate = WorkbenchRegistration.fromJson(rawPublication);
      if (candidate.activityMessageId == activity.messageId &&
          messages.isNotEmpty &&
          messages.every(
            (message) => _operations.where(message.containsKey).every(
                  (key) =>
                      (message[key] as Map)['surfaceId'] == candidate.surfaceId,
                ),
          )) {
        publication = candidate;
      }
    } on FormatException {
      // Malformed role declarations remain ordinary A2UI activities.
    }
  }

  final surfaces = <String>{};
  for (final message in messages) {
    for (final key in _operations) {
      final operation = message[key];
      if (operation is! Map) continue;
      final surfaceId = operation['surfaceId'] as String;
      if (key == 'deleteSurface') {
        surfaces.remove(surfaceId);
      } else {
        surfaces.add(surfaceId);
      }
    }
  }
  if (content.containsKey('a2ui_operations') && surfaces.isEmpty) {
    if (index < 0) return ownedConversation;
    return ownedConversation.copyWith(
      messages: [...conversation.messages]..removeAt(index),
    );
  }

  final runId = switch (conversation.status) {
    Running(:final runId) => runId,
    _ => null,
  };
  final previousUpdates =
      existing is GenUiMessage ? existing.data['updatedByRunIds'] : null;
  final updatedByRunIds = <String>{
    if (previousUpdates is List) ...previousUpdates.whereType<String>(),
  };
  if (messages.isNotEmpty && surfaces.isNotEmpty && runId != null) {
    updatedByRunIds.add(runId);
  }
  final data = <String, dynamic>{
    'messages': messages,
    if (publication != null)
      'workbenchRegistration': {
        'role': publication.role.name,
        'activityMessageId': publication.activityMessageId,
        'surfaceId': publication.surfaceId,
      },
    if (metadata != null) 'workbench': metadata.toJson(),
    if (!content.containsKey('a2ui_operations')) 'status': status,
    if (updatedByRunIds.isNotEmpty)
      'updatedByRunIds': updatedByRunIds.toList(growable: false),
  };
  if (existing is GenUiMessage &&
      const DeepCollectionEquality().equals(existing.data, data)) {
    return ownedConversation;
  }
  final message = GenUiMessage(
    id: activity.messageId,
    createdAt: existing?.createdAt ?? createdAt,
    runId: existing?.runId ?? runId,
    widgetName: 'a2ui',
    data: data,
  );
  return index < 0
      ? ownedConversation.withAppendedMessage(message)
      : ownedConversation.copyWith(
          messages: [...conversation.messages]..[index] = message,
        );
}

WorkbenchActivityMetadata? _workbenchMetadata(
  Object? raw,
  String messageId,
  List<Map<String, dynamic>> messages,
  List<WorkbenchRegistration> registeredWorkbenchActivities,
) {
  if (raw is! Map<String, dynamic>) {
    return null;
  }
  final WorkbenchActivityMetadata metadata;
  try {
    metadata = WorkbenchActivityMetadata.fromJson(raw);
  } on Object {
    return null;
  }
  if (metadata.registration.activityMessageId != messageId) {
    return null;
  }
  if (!registeredWorkbenchActivities.any(
    (registration) =>
        registration.role == metadata.registration.role &&
        registration.activityMessageId == messageId &&
        registration.surfaceId == metadata.registration.surfaceId,
  )) {
    return null;
  }
  final surfaceId = metadata.registration.surfaceId;
  for (final message in messages) {
    for (final operationKey in _operations) {
      final operation = message[operationKey];
      if (operation is Map && operation['surfaceId'] is String) {
        if (operation['surfaceId'] != surfaceId) return null;
      }
    }
  }
  return metadata;
}

const _operations = [
  'createSurface',
  'updateComponents',
  'updateDataModel',
  'deleteSurface',
];

Map<String, dynamic> _operation(Object? raw, String messageId) {
  if (raw is! Map<String, dynamic>) _malformed(messageId, 'operation');
  final version = raw['version'];
  if (version is! String || version.trim().isEmpty) {
    _malformed(messageId, 'version');
  }
  final keys = _operations.where(raw.containsKey).toList();
  if (keys.length != 1) _malformed(messageId, 'operation discriminator');
  final body = raw[keys.single];
  if (body is! Map<String, dynamic>) _malformed(messageId, keys.single);
  final surfaceId = body['surfaceId'];
  if (surfaceId is! String || surfaceId.trim().isEmpty) {
    _malformed(messageId, 'surfaceId');
  }
  try {
    return jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
  } on Object {
    _malformed(messageId, 'JSON operation');
  }
}

Never _malformed(String messageId, String field) =>
    throw MalformedResponseException(
      message: 'A2UI activity $messageId has invalid $field',
    );
