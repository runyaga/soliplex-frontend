/// Soliplex A2UI graphics catalogs shared by chat and workbench surfaces.
/// Includes bar, line, gauge, scatter, pie, radar and candlestick charts.
library;

export 'src/demo_components.dart' show demoComponents;
export 'src/static_chart.dart'
    show chartGraphicsCatalog, chartGraphicsCatalogId, validateStaticChartSpec;
export 'src/surface_catalog.dart'
    show chatGraphicsCatalog, chatGraphicsCatalogId;
