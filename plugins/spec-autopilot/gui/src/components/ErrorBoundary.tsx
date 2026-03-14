import { Component, type ReactNode } from "react";

interface Props {
  children: ReactNode;
}

interface State {
  error: Error | null;
}

export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  render() {
    if (this.state.error) {
      return (
        <div className="h-full flex items-center justify-center bg-void text-text-bright font-mono p-8">
          <div className="max-w-lg space-y-4 text-center">
            <div className="text-rose text-lg font-bold">GUI 渲染错误</div>
            <pre className="text-[11px] text-text-muted bg-surface p-4 rounded overflow-auto max-h-48 text-left">
              {this.state.error.message}
            </pre>
            <button
              onClick={() => this.setState({ error: null })}
              className="px-4 py-2 bg-cyan/10 border border-cyan/30 text-cyan text-xs font-bold rounded hover:bg-cyan/20"
            >
              重试
            </button>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}
