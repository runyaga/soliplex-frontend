import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:soliplex_monty/soliplex_monty.dart';

/// Catalogs registered by this app and read by the room-teaching generator.
List<CatalogImplementation> workbenchCatalogs({
  bool Function(BuildContext)? isLive,
  String? Function(BuildContext)? activeRunId,
}) => [labCatalog(isLive: isLive, activeRunId: activeRunId)];
