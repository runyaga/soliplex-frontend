import 'package:a2ui_flutter/a2ui_flutter.dart' show CatalogImplementation;
import 'package:soliplex_design/soliplex_design.dart' show BrandTheme;

import '../core/app_identity.dart';
import '../core/flavor.dart';
import '../interfaces/workbench_presentation.dart';
import '../modules/auth/consent_notice.dart';
import '../modules/auth/platform/callback_params.dart';
import '../modules/room/document_browser_url.dart';
import 'standard.dart';

/// Builds the standard module graph with explicit workbench room presentation.
/// The ordinary [standardFlavor] remains unchanged unless opted in directly.
Future<Flavor> workbenchFlavor({
  required WorkbenchPresentation presentation,
  AppIdentity? identity,
  FlavorTheme theme = const FlavorTheme.brand(BrandTheme.soliplex()),
  String redirectScheme = 'ai.soliplex.client',
  String defaultBackendUrl = 'http://localhost:8000',
  CallbackParams callbackParams = const NoCallbackParams(),
  ConsentNotice? consentNotice,
  String? signedOutLandingPath,
  DocumentBrowserUrlResolver? documentBrowserUrl,
  List<CatalogImplementation> surfaceCatalogs = const [],
}) =>
    standardFlavor(
      identity: identity,
      theme: theme,
      redirectScheme: redirectScheme,
      defaultBackendUrl: defaultBackendUrl,
      callbackParams: callbackParams,
      consentNotice: consentNotice,
      signedOutLandingPath: signedOutLandingPath,
      documentBrowserUrl: documentBrowserUrl,
      surfaceCatalogs: surfaceCatalogs,
      workbenchPresentation: presentation,
    );
