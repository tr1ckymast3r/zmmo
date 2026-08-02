"use client";

import { useState, useEffect } from "react";
import type { AgentStatus } from "@/types/device";
import { Link } from "@tanstack/react-router";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { getEndpoint, setEndpoint } from "@/lib/api";

interface NavbarProps {
  agent: AgentStatus | null;
  onReconnect: () => void;
  sidebarOpen: boolean;
  onToggleSidebar: () => void;
}

export function Navbar({ agent, onReconnect, sidebarOpen, onToggleSidebar }: NavbarProps) {
  const [endpoint, setEp] = useState("");
  const [editing, setEditing] = useState(false);

  useEffect(() => {
    setEp(getEndpoint());
  }, []);

  const saveEndpoint = () => {
    const url = endpoint.trim();
    if (url) {
      setEndpoint(url);
      setEditing(false);
      onReconnect();
    }
  };

  return (
    <header className="sticky top-0 z-50 border-b border-zinc-800 bg-zinc-950/80 backdrop-blur">
      <div className="flex items-center justify-between h-14 px-2 sm:px-4 gap-1 sm:gap-2">
        {/* Left */}
        <div className="flex items-center gap-1 sm:gap-3 flex-shrink-0">
          <button
            onClick={onToggleSidebar}
            className="md:hidden p-2 -ml-1 rounded-lg hover:bg-zinc-800 active:bg-zinc-700 touch-manipulation"
            aria-label="Toggle menu"
          >
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              {sidebarOpen ? (
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              ) : (
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 6h16M4 12h16M4 18h16" />
              )}
            </svg>
          </button>
          <Link to="/" className="font-semibold text-sm sm:text-base tracking-tight flex items-center gap-1.5 sm:gap-2">
            <span className="w-7 h-7 rounded-md bg-gradient-to-br from-blue-600 to-purple-600 flex items-center justify-center text-white text-xs font-bold flex-shrink-0">DC</span>
            <span className="hidden sm:inline">Device Changer</span>
          </Link>
        </div>

        {/* Center: Endpoint */}
        <div className="flex-1 flex justify-center max-w-[200px] sm:max-w-md mx-1">
          {editing ? (
            <div className="flex items-center gap-1 w-full">
              <Input
                value={endpoint}
                onChange={(e) => setEp(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && saveEndpoint()}
                placeholder="http://100.87.34.74:55555"
                className="h-7 text-[10px] sm:text-xs bg-zinc-800 border-zinc-700 text-zinc-200 font-mono"
                autoFocus
              />
              <Button onClick={saveEndpoint} className="h-7 text-[10px] px-2 bg-blue-600 hover:bg-blue-500 flex-shrink-0">Save</Button>
              <Button onClick={() => { setEditing(false); setEp(getEndpoint()); }} variant="ghost" className="h-7 text-[10px] px-1 text-zinc-500 flex-shrink-0">✕</Button>
            </div>
          ) : (
            <button
              onClick={() => setEditing(true)}
              className="text-[10px] sm:text-xs text-zinc-500 hover:text-zinc-300 font-mono truncate max-w-[120px] sm:max-w-[300px] px-1.5 sm:px-2 py-1 rounded hover:bg-zinc-800/50 transition-colors"
              title="Click to change agent endpoint"
            >
              {endpoint === "/api" ? "localhost" : endpoint.replace(/^https?:\/\//, "").replace(/:\d+$/, "")}
            </button>
          )}
        </div>

        {/* Right */}
        <div className="flex items-center gap-1 sm:gap-3 flex-shrink-0">
          {agent ? (
            <div className="flex items-center gap-1 sm:gap-2">
              <Badge variant="default" className="bg-emerald-500/10 text-emerald-400 border-emerald-500/20 text-[9px] sm:text-xs gap-1 px-1.5 sm:px-2 py-0.5">
                <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse flex-shrink-0" />
                <span className="hidden sm:inline">Agent v{agent.version}</span>
              </Badge>
              <span className="text-[10px] sm:text-xs text-zinc-500">
                {agent.deviceCount}d
              </span>
            </div>
          ) : (
            <Badge variant="destructive" className="text-[9px] sm:text-xs gap-1 px-1.5 sm:px-2 py-0.5">
              <span className="w-1.5 h-1.5 rounded-full bg-red-400 flex-shrink-0" />
              <span className="hidden sm:inline">Disconnected</span>
            </Badge>
          )}
          <Button
            variant="ghost"
            size="sm"
            onClick={onReconnect}
            className="h-7 text-[10px] sm:text-xs text-zinc-400 hover:text-zinc-200 px-1.5 sm:px-2"
          >
            <svg className="w-3.5 h-3.5 sm:hidden" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
            </svg>
            <span className="hidden sm:inline">{agent ? "Refresh" : "Reconnect"}</span>
          </Button>
        </div>
      </div>
    </header>
  );
}
