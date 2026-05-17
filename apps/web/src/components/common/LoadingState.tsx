const STEPS = [
  'Classifying question type...',
  'Generating hypothesis tree...',
  'Validating MECE structure...',
  'Classifying testability...',
  'Designing analyses...',
  'Fetching financial data...',
  'Matching data to hypotheses...',
  'Running Devil\'s Advocate...',
  'Surfacing hidden assumptions...',
  'Analyzing sensitivity...',
  'Detecting contradictions...',
  'Compiling stress test report...',
];

export function LoadingState() {
  return (
    <div className="flex flex-col items-center justify-center py-16">
      <div className="w-8 h-8 border-4 border-blue-200 border-t-blue-600 rounded-full animate-spin mb-6" />
      <div className="space-y-2 text-center">
        {STEPS.map((step, i) => (
          <p key={i} className="text-sm text-slate-500 animate-pulse" style={{ animationDelay: `${i * 0.3}s` }}>
            {step}
          </p>
        ))}
      </div>
      <p className="text-xs text-slate-400 mt-6">Full pipeline typically takes 6-10 minutes</p>
    </div>
  );
}
