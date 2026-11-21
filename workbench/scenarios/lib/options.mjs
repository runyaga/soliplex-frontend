export function parseScenarioArgs(args) {
  if (args.length === 1 && args[0] === '--help') return null;
  const usage = 'Use --deterministic, --models, --all, or --probes (alone)';
  if (!args.length || args.some(arg => !['--deterministic', '--models', '--all', '--probes'].includes(arg))) throw new Error(usage);
  if (args.includes('--probes') && args.length !== 1) throw new Error(usage);
  return {
    deterministic: args.includes('--deterministic') || args.includes('--all'),
    models: args.includes('--models') || args.includes('--all'),
    probes: args.includes('--probes'),
  };
}
