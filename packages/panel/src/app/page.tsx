"use client";

import { useEffect, useState, useCallback } from "react";
import type { DeviceInfo, AgentStatus } from "@/types/device";
import { getAgentStatus, getDevices, resetPort } from "@/lib/api";
import { DeviceGrid } from "@/components/DeviceGrid";
import { DeviceDetail } from "@/components/DeviceDetail";
import { Navbar } from "@/components/Navbar";
import { Sidebar } from "@/components/Sidebar";
import { Toaster } from "@/components/ui/sonner";
import { toast } from "sonner";
import { TaskRunner } from "@/components/TaskRunner";

export default function Home() {
  const [agent, setAgent] = useState<AgentStatus | null>(null);
  const [devices, setDevices] = useState<DeviceInfo[]>([]);
  const [selectedDevice, setSelectedDevice] = useState<DeviceInfo | null>(null);
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      const [a, d] = await Promise.all([getAgentStatus(), getDevices()]);
      setAgent(a);
      setDevices(d);
      // Update selected device if it still exists
      if (selectedDevice) {
        const updated = d.find((x) => x.id === selectedDevice.id);
        setSelectedDevice(updated ?? (d.length > 0 ? d[0] : null));
      } else if (d.length > 0) {
        setSelectedDevice(d[0]);
      }
      setError(null);
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : "Connection failed";
      if (!msg.includes("Agent not running")) {
        setError(msg);
      }
      setAgent(null);
      setDevices([]);
    } finally {
      setLoading(false);
    }
  }, [selectedDevice]);

  useEffect(() => {
    refresh();
    const interval = setInterval(refresh, 10000);
    return () => clearInterval(interval);
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const handleReconnect = () => {
    resetPort();
    setLoading(true);
    refresh();
    toast.info("Reconnecting to agent...");
  };

  const handleDeviceUpdated = (device: DeviceInfo) => {
    setDevices((prev) => prev.map((d) => (d.id === device.id ? device : d)));
    setSelectedDevice(device);
  };

  return (
    <div className="min-h-screen bg-zinc-950 text-zinc-100">
      <Navbar
        agent={agent}
        onReconnect={handleReconnect}
        sidebarOpen={sidebarOpen}
        onToggleSidebar={() => setSidebarOpen(!sidebarOpen)}
      />

      <div className="flex">
        <Sidebar
          open={sidebarOpen}
          devices={devices}
          selectedId={selectedDevice?.id ?? null}
          onSelect={(d) => { setSelectedDevice(d); setSidebarOpen(false); }}
          loading={loading}
        />

        <main
          className={`flex-1 transition-all duration-200 p-3 sm:p-4 md:p-6 ${
            sidebarOpen ? "md:ml-64" : ""
          }`}
        >
          {loading ? (
            <div className="flex items-center justify-center h-64">
              <div className="flex flex-col items-center gap-3">
                <div className="w-8 h-8 border-2 border-zinc-500 border-t-blue-500 rounded-full animate-spin" />
                <p className="text-zinc-400 text-sm">Connecting to agent...</p>
              </div>
            </div>
          ) : error ? (
            <div className="flex items-center justify-center h-64">
              <div className="text-center space-y-3">
                <p className="text-red-400 text-sm">{error}</p>
                <button
                  onClick={handleReconnect}
                  className="px-4 py-2 bg-blue-600 hover:bg-blue-500 rounded-lg text-sm transition-colors"
                >
                  Retry Connection
                </button>
              </div>
            </div>
          ) : devices.length === 0 ? (
            <div className="flex items-center justify-center h-64">
              <div className="text-center space-y-2">
                <div className="w-16 h-16 mx-auto rounded-full bg-zinc-800 flex items-center justify-center text-2xl">
                  📱
                </div>
                <p className="text-zinc-500 text-sm">No devices connected</p>
                <p className="text-zinc-600 text-xs">
                  Connect a device via USB or WiFi to get started
                </p>
              </div>
            </div>
          ) : selectedDevice ? (
            <div className="space-y-4">
              <DeviceDetail
                device={selectedDevice}
                onUpdate={handleDeviceUpdated}
              />
              <TaskRunner selectedDevice={selectedDevice.id} />
            </div>
          ) : (
            <DeviceGrid
              devices={devices}
              onSelect={setSelectedDevice}
            />
          )}
        </main>
      </div>

      <Toaster theme="dark" position="bottom-center" />
    </div>
  );
}
