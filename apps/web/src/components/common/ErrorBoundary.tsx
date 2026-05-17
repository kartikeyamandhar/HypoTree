import { Component, type ReactNode } from 'react';

interface Props { children: ReactNode; fallback?: ReactNode; }
interface State { hasError: boolean; error: Error | null; }

export class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false, error: null };
  static getDerivedStateFromError(error: Error): State { return { hasError: true, error }; }
  render() {
    if (this.state.hasError) return (
      <div className="p-8 text-center">
        <h2 className="text-lg font-semibold mb-2" style={{ color: 'var(--accent-red)' }}>Something went wrong</h2>
        <p className="text-sm" style={{ color: 'var(--text-secondary)' }}>{this.state.error?.message}</p>
        <button onClick={() => this.setState({ hasError: false, error: null })} className="mt-4 px-4 py-2 rounded-lg text-sm"
          style={{ background: 'var(--bg-card)', color: 'var(--text-primary)' }}>Try again</button>
      </div>
    );
    return this.props.children;
  }
}
