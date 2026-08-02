import { createFileRoute } from "@tanstack/react-router";

export const Route = createFileRoute("/_layout/downloads")({
  component: DownloadsContent,
});

function DownloadsContent() {
  return (
    <div className="max-w-3xl mx-auto">
      <h2 className="text-sm font-semibold text-zinc-100 mb-4">Downloads</h2>

      <div className="space-y-3">
        {/* Manager Agent */}
        <div className="p-4 rounded-xl bg-zinc-900 border border-zinc-800">
          <h3 className="text-xs font-medium text-zinc-300 mb-2">Manager Agent</h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
            {[
              { platform: "Linux (amd64)", file: "zmmo-agent-linux-amd64" },
              { platform: "Windows (amd64)", file: "zmmo-agent-windows-amd64.exe" },
              { platform: "macOS (Intel)", file: "zmmo-agent-darwin-amd64" },
              { platform: "macOS (Apple Silicon)", file: "zmmo-agent-darwin-arm64" },
            ].map((b) => (
              <a
                key={b.file}
                href={`/agent-binaries/${b.file}`}
                className="flex items-center gap-2 p-2 rounded-lg bg-zinc-800/50 hover:bg-zinc-700/50 transition-colors text-[11px] text-zinc-300 group"
              >
                <svg className="w-3.5 h-3.5 text-zinc-500 group-hover:text-blue-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
                </svg>
                <span>{b.platform}</span>
              </a>
            ))}
          </div>
        </div>

        {/* ROM Patcher */}
        <div className="p-4 rounded-xl bg-zinc-900 border border-zinc-800">
          <h3 className="text-xs font-medium text-zinc-300 mb-2">ROM Patcher</h3>
          <p className="text-[11px] text-zinc-500 mb-3">
            Clone the repo and run the patcher scripts:
          </p>
          <code className="block p-2 rounded-lg bg-zinc-800 text-[10px] text-zinc-300 font-mono">
            git clone https://github.com/tr1ckymast3r/zmmo.git<br />
            cd zmmo/packages/rom-patcher<br />
            chmod +x patch.sh &amp;&amp; ./patch.sh
          </code>
        </div>
      </div>
    </div>
  );
}
