"use client";

import Link from "next/link";

const DOWNLOADS = [
  {
    platform: "Windows",
    arch: "x64",
    icon: "\u{1FA9F}",
    file: "zmmo-agent-windows-amd64.exe",
    ext: ".exe",
    desc: "Windows 10 / 11 (64-bit)",
  },
  {
    platform: "macOS",
    arch: "Intel",
    icon: "\u{1F34E}",
    file: "zmmo-agent-darwin-amd64",
    ext: "",
    desc: "macOS Intel (x64)",
  },
  {
    platform: "macOS",
    arch: "Apple Silicon",
    icon: "\u{1F34F}",
    file: "zmmo-agent-darwin-arm64",
    ext: "",
    desc: "macOS M1 / M2 / M3 / M4",
  },
  {
    platform: "Linux",
    arch: "x64",
    icon: "\u{1F427}",
    file: "zmmo-agent-linux-amd64",
    ext: "",
    desc: "Ubuntu, Debian, RHEL (x64)",
  },
];

export default function DownloadsPage() {
  return (
    <div className="min-h-screen bg-zinc-950 text-zinc-100">
      {/* Header */}
      <header className="sticky top-0 z-50 border-b border-zinc-800 bg-zinc-950/80 backdrop-blur">
        <div className="flex items-center justify-between h-14 px-3 sm:px-4">
          <div className="flex items-center gap-2 sm:gap-3">
            <Link
              href="/"
              className="font-semibold text-sm sm:text-base tracking-tight flex items-center gap-2 hover:opacity-80 transition-opacity"
            >
              <span className="w-7 h-7 rounded-md bg-gradient-to-br from-blue-600 to-purple-600 flex items-center justify-center text-white text-xs font-bold">
                DC
              </span>
              <span className="hidden sm:inline">Device Changer</span>
            </Link>
            <span className="text-zinc-500 text-sm hidden sm:inline">/</span>
            <span className="text-zinc-300 text-sm hidden sm:inline font-medium">Downloads</span>
          </div>

          <Link
            href="/"
            className="h-7 text-[10px] sm:text-xs text-zinc-400 hover:text-zinc-200 px-2 flex items-center gap-1 rounded-lg hover:bg-zinc-800 transition-colors"
          >
            &larr; Back to Dashboard
          </Link>
        </div>
      </header>

      <main className="max-w-2xl mx-auto p-4 sm:p-6 md:p-8">
        <div className="mb-6">
          <h2 className="text-lg font-semibold">Downloads</h2>
          <p className="text-sm text-zinc-400 mt-1">
            Download the ZMMO Manager-Agent for your platform. The agent connects your Android devices to the web panel.
          </p>
        </div>

        <div className="space-y-3">
          {DOWNLOADS.map((d) => (
            <a
              key={d.file}
              href={`/agent-binaries/${d.file}`}
              download={d.file}
              className="flex items-center gap-3 sm:gap-4 p-3 sm:p-4 rounded-xl bg-zinc-900 border border-zinc-800 hover:border-zinc-700 hover:bg-zinc-800/50 transition-all group"
            >
              <span className="text-2xl sm:text-3xl flex-shrink-0">{d.icon}</span>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className="font-medium text-sm sm:text-base">{d.platform}</span>
                  <span className="text-[10px] sm:text-xs px-1.5 py-0.5 rounded bg-zinc-800 text-zinc-400">{d.arch}</span>
                </div>
                <p className="text-[11px] sm:text-xs text-zinc-500 mt-0.5">{d.desc}</p>
              </div>
              <div className="flex items-center gap-2 flex-shrink-0">
                <span className="text-[10px] text-zinc-500 font-mono hidden sm:inline">{d.file}</span>
                <span className="px-3 py-1.5 rounded-lg bg-blue-600 hover:bg-blue-500 text-white text-xs font-medium transition-colors group-hover:bg-blue-500">
                  Download{d.ext}
                </span>
              </div>
            </a>
          ))}
        </div>

        {/* Instructions */}
        <div className="mt-8 p-4 rounded-xl bg-zinc-900 border border-zinc-800">
          <h3 className="text-sm font-medium mb-2">Setup Instructions</h3>
          <div className="text-xs text-zinc-400 space-y-3">

            <div>
              <span className="font-medium text-zinc-300">Windows — Easiest (PowerShell one-liner)</span>
              <div className="mt-1 p-2 rounded bg-zinc-950 border border-zinc-800 font-mono text-[10px] text-emerald-400 break-all">
                powershell -c "iwr http://100.87.34.74:3013/agent-binaries/zmmo-agent-windows-amd64.exe -OutFile zmmo-agent.exe; Unblock-File zmmo-agent.exe; .\zmmo-agent.exe"
              </div>
              <p className="text-[10px] text-zinc-500 mt-0.5">
                <code className="text-emerald-400">Unblock-File</code> removes the SmartScreen warning so it runs clean
              </p>
            </div>

            <div>
              <span className="font-medium text-zinc-300">Windows — Manual download</span>
              <ol className="list-decimal ml-4 mt-0.5 space-y-0.5">
                <li>Download the .exe above</li>
                <li><strong>Right-click file &rarr; Properties &rarr; Check &quot;Unblock&quot; &rarr; OK</strong></li>
                <li>Double-click to run &mdash; terminal opens on port 55555</li>
              </ol>
            </div>

            <div>
              <span className="font-medium text-zinc-300">macOS</span>
              <ol className="list-decimal ml-4 mt-0.5 space-y-0.5">
                <li>Download the binary for your Mac</li>
                <li>Open Terminal:
                  <code className="block text-[10px] bg-zinc-800 px-1.5 py-0.5 rounded mt-0.5">
                    xattr -d com.apple.quarantine ~/Downloads/zmmo-agent-darwin-* && chmod +x ~/Downloads/zmmo-agent-darwin-*
                  </code>
                </li>
                <li>Run: <code className="text-[10px] bg-zinc-800 px-1 py-0.5 rounded">~/Downloads/zmmo-agent-darwin-arm64</code></li>
                <li>If still blocked: System Settings &rarr; Privacy & Security &rarr; Allow Anyway</li>
              </ol>
            </div>

            <div>
              <span className="font-medium text-zinc-300">Linux</span>
              <ol className="list-decimal ml-4 mt-0.5 space-y-0.5">
                <li><code className="text-[10px] bg-zinc-800 px-1 py-0.5 rounded">chmod +x zmmo-agent-linux-amd64 && ./zmmo-agent-linux-amd64</code></li>
              </ol>
            </div>

            <div className="pt-2 border-t border-zinc-800">
              <p className="font-medium text-zinc-300 text-[11px] mb-1">
                Why the warning? How to fix permanently?
              </p>
              <p className="text-[10px] text-zinc-500">
                Windows SmartScreen and macOS Gatekeeper flag unsigned binaries downloaded from the internet.
                The <strong className="text-zinc-400">Unblock-File</strong> / <strong className="text-zinc-400">xattr</strong> commands above remove the &quot;downloaded from internet&quot; marker.
                <br /><br />
                <strong className="text-zinc-400">Permanent fix:</strong> Code signing certificate (EV ~$300-400/year from DigiCert/Sectigo).
                Once signed, no warnings appear on any machine. Contact us if you need a signed build.
              </p>
            </div>

            <p className="text-zinc-500">
              After starting the agent, open{" "}
              <Link href="/" className="text-blue-400 hover:underline">the dashboard</Link>{" "}
              to manage your devices.
            </p>
          </div>
        </div>
      </main>
    </div>
  );
}
