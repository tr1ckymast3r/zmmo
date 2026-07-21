"use client";

import type { DeviceInfo } from "@/types/device";
import { Link } from "@tanstack/react-router";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";

interface SidebarProps {
  open: boolean;
  devices: DeviceInfo[];
  selectedId: string | null;
  onSelect: (device: DeviceInfo) => void;
  loading: boolean;
}

const statusColor: Record<string, string> = {
  online: "bg-emerald-400",
  offline: "bg-zinc-500",
  busy: "bg-amber-400 animate-pulse",
  error: "bg-red-400",
};

const statusLabel: Record<string, string> = {
  online: "Online",
  offline: "Offline",
  busy: "Busy",
  error: "Error",
};

export function Sidebar({ open, devices, selectedId, onSelect, loading }: SidebarProps) {
  return (
    <aside
      className={`fixed md:sticky top-14 left-0 z-40 h-[calc(100vh-3.5rem)] w-64 border-r border-zinc-800 bg-zinc-950/95 backdrop-blur transition-transform duration-200 ${
        open ? "translate-x-0" : "-translate-x-full md:translate-x-0"
      }`}
    >
      <div className="p-3 border-b border-zinc-800">
        <p className="text-xs font-medium text-zinc-400 uppercase tracking-wider">
          Devices
        </p>
        {devices.length > 0 && (
          <p className="text-[10px] text-zinc-600 mt-0.5">
            {devices.filter((d) => d.status === "online").length} online /{" "}
            {devices.length} total
          </p>
        )}
      </div>

      <ScrollArea className="h-[calc(100vh-10rem)]">
        {loading ? (
          <div className="p-4 space-y-2">
            {[1, 2, 3].map((i) => (
              <div key={i} className="h-16 rounded-lg bg-zinc-800/50 animate-pulse" />
            ))}
          </div>
        ) : devices.length === 0 ? (
          <div className="p-4 text-center">
            <p className="text-xs text-zinc-500">No devices</p>
          </div>
        ) : (
          <div className="p-2 space-y-1">
            {devices.map((d) => (
              <button
                key={d.id}
                onClick={() => onSelect(d)}
                className={`w-full text-left p-2.5 rounded-lg transition-colors ${
                  selectedId === d.id
                    ? "bg-blue-600/20 border border-blue-500/30"
                    : "hover:bg-zinc-800/50 border border-transparent"
                }`}
              >
                <div className="flex items-center gap-2">
                  <span className={`w-2 h-2 rounded-full flex-shrink-0 ${statusColor[d.status] ?? "bg-zinc-500"}`} />
                  <div className="min-w-0 flex-1">
                    <p className="text-xs font-medium text-zinc-200 truncate">
                      {d.model ?? d.serial}
                    </p>
                    <p className="text-[10px] text-zinc-500 truncate">{d.serial}</p>
                  </div>
                  <Badge
                    variant="outline"
                    className="text-[9px] px-1 py-0 h-4 border-zinc-700 text-zinc-400"
                  >
                    {d.androidVersion ?? "?"}
                  </Badge>
                </div>
                <div className="flex items-center gap-2 mt-1.5">
                  <span className="text-[9px] text-zinc-600">
                    {statusLabel[d.status] ?? d.status}
                  </span>
                  {d.ip && (
                    <span className="text-[9px] text-zinc-600 font-mono">
                      {d.ip}
                    </span>
                  )}
                </div>
              </button>
            ))}
          </div>
        )}
      </ScrollArea>

      {/* Footer nav */}
      <div className="absolute bottom-0 left-0 right-0 p-3 border-t border-zinc-800 bg-zinc-950/95">
        <Link
          to="/downloads"
          className="flex items-center gap-2 text-[11px] text-zinc-400 hover:text-zinc-200 px-2 py-1.5 rounded-lg hover:bg-zinc-800/50 transition-colors"
        >
          <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
          </svg>
          Downloads
        </Link>
      </div>
    </aside>
  );
}
