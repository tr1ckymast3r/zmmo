import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useState, useCallback } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import type { DeviceInfo, AgentStatus } from "@/types/device";
import { getAgentStatus, getDevices, resetPort } from "@/lib/api";
import { DeviceDetail } from "@/components/DeviceDetail";
import { Navbar } from "@/components/Navbar";
import { Sidebar } from "@/components/Sidebar";
import { TaskRunner } from "@/components/TaskRunner";
import { Toaster } from "@/components/ui/sonner";
import { toast } from "sonner";

export const Route = createFileRoute("/")({
  component: Dashboard,
});

function Dashboard() {
  const queryClient = useQueryClient();
  const [selectedDevice, setSelectedDevice] = useState<DeviceInfo | null>(null);
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // TanStack Query for agent status
  const agentQuery = useQuery({
    queryKey: ["agent-status"],
    queryFn: getAgentStatus,
    refetchInterval: 10000,
    retry: false,
  });

  // TanStack Query for devices
  const devicesQuery = useQuery({
    queryKey: ["devices"],
    queryFn: getDevices,
    refetchInterval: 10000,
    retry: false,
  });

  const agent = agentQuery.data ?? null;
  const devices = devicesQuery.data ?? [];
  const loading = agentQuery.isLoading || devicesQuery.isLoading;

  // Auto-select first device
  useEffect(() => {
    if (devices.length > 0 && !selectedDevice) {
      setSelectedDevice(devices[0]);
    }
    // Update selected if it changed
    if (selectedDevice) {
      const updated = devices.find((d) => d.id === selectedDevice.id);
      if (updated) setSelectedDevice(updated);
    }
  }, [devices]);

  // Handle agent errors
  useEffect(() => {
    const agentErr = agentQuery.error;
    const devicesErr = devicesQuery.error;
    const msg = agentErr ? (agentErr instanceof Error ? agentErr.message : "Agent error") :
                devicesErr ? (devicesErr instanceof Error ? devicesErr.message : "Device error") : null;
    if (msg && !msg.includes("Agent not running")) {
      setError(msg);
    } else if (!msg) {
      setError(null);
    }
  }, [agentQuery.error, devicesQuery.error]);

  const handleReconnect = () => {
    resetPort();
    queryClient.invalidateQueries({ queryKey: ["agent-status"] });
    queryClient.invalidateQueries({ queryKey: ["devices"] });
    toast.info("Reconnecting to agent...");
  };

  const handleDeviceUpdated = (device: DeviceInfo) => {
    setSelectedDevice(device);
    queryClient.invalidateQueries({ queryKey: ["devices"] });
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
          ) : null}
        </main>
      </div>

      <Toaster theme="dark" position="bottom-center" />
    </div>
  );
}
