/// Soliplex A2UI graphics catalogs shared by chat and workbench surfaces.
/// Includes bar, line, gauge, scatter, pie, radar and candlestick charts.
library;

export 'src/program_app.dart';

export 'src/demo_components.dart' show demoComponents;
export 'src/static_chart.dart'
    show
        chartGraphicsCatalog,
        chartGraphicsCatalogId,
        validateStaticChartSpec,
        validateChartComponent;
export 'src/surface_catalog.dart'
    show chatGraphicsCatalog, chatGraphicsCatalogId;

export 'src/host_function_schemas.dart';
export 'src/host_signatures.dart';
