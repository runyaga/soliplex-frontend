/// A2UI catalogs for the Soliplex frontend whose components run Python in a
/// Monty sandbox, only on a user gesture.
library;

export 'src/lab_catalog.dart'
    show
        PythonReplView,
        ReplEntry,
        ReplExample,
        ReplLimits,
        ReplMode,
        ReplRetry,
        ReplRuntimeStarter,
        labCatalog,
        labCatalogId;
export 'src/python_ui.dart' show PythonUiArena, StagedSurface, basicSignatures;
export 'src/repair_chain.dart' show RepairChain, RepairChains, RepairStatus;
export 'src/repl_examples.dart' show replExamples;
export 'src/repl_surface.dart' show pythonReplSurfaceMessages;
