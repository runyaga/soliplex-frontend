/// The Python `ui` and `chart` modules without the lab's runtime layer.
///
/// Apps that drive Monty sessions themselves import this library, so they do
/// not compile the lab catalog against their dart_monty version.
library;

export 'src/chart_module.dart' show chartModule;
export 'src/python_ui.dart' show PythonUiArena, StagedSurface;
