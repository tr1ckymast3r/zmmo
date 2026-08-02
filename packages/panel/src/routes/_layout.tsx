import { createFileRoute, Outlet } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import type { DeviceInfo } from "@/types/device";
import { getAgentStatus, getDevices } from "@/lib/api";
import { Navbar } from "@/components/Navbar";
import { Sidebar } from "@/components/Sidebar";
import { Toaster } from "@/components/ui/sonner";
import { toast } from "sonner";

export const Route = createFileRoute("/_layout")({
  component: LayoutComponent,
});

function LayoutComponent() {
  const queryClient = useQueryClient();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const agentQuery = useQuery({
    queryKey: ["agent-status"],
    queryFn: getAgentStatus,
    refetchInterval: 10000,
    retry: false,
  });

  const devicesQuery = useQuery({
    queryKey: ["devices"],
    queryFn: getDevices,
    refetchInterval: 10000,
    retry: false,
  });

  const agent = agentQuery.data ?? null;
  const devices: DeviceInfo[] = devicesQuery.data ?? [];
  const loading = agentQuery.isLoading || devicesQuery.isLoading;

  // Auto-select first device
  useEffect(() => {
    if (devices.length > 0 && !selectedId) {
      setSelectedId(devices[0].id);
    } else if (devices.length > 0 && selectedId) {
      const stillExists = devices.find((d) => d.id === selectedId);
      if (!stillExists) setSelectedId(devices[0].id);
    }
  }, [devices]);

  const handleReconnect = () => {
    queryClient.invalidateQueries({ queryKey: ["agent-status"] });
    queryClient.invalidateQueries({ queryKey: ["devices"] });
    toast.info("Reconnecting...");
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
        {/* Mobile backdrop */}
        {sidebarOpen && (
          <div
            className="fixed inset-0 z-30 bg-black/50 backdrop-blur-sm md:hidden"
            onClick={() => setSidebarOpen(false)}
          />
        )}

        <Sidebar
          open={sidebarOpen}
          devices={devices}
          selectedId={selectedId}
          onSelect={(d) => { setSelectedId(d.id); setSidebarOpen(false); }}
          onClose={() => setSidebarOpen(false)}
          loading={loading}
        />

        <main className="flex-1 min-w-0 transition-all duration-200 p-2 sm:p-4 md:p-6">
          <Outlet />
        </main>
      </div>

      <Toaster theme="dark" position="bottom-center" />
    </div>
  );
}
