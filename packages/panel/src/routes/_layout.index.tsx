import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import type { DeviceInfo } from "@/types/device";
import { getDevices } from "@/lib/api";
import { DeviceDetail } from "@/components/DeviceDetail";
import { TaskRunner } from "@/components/TaskRunner";

export const Route = createFileRoute("/_layout/")({
  component: DashboardContent,
});

function DashboardContent() {
  const queryClient = useQueryClient();
  const [selectedDevice, setSelectedDevice] = useState<DeviceInfo | null>(null);

  const devicesQuery = useQuery({
    queryKey: ["devices"],
    queryFn: getDevices,
    refetchInterval: 10000,
    retry: false,
  });

  const devices = devicesQuery.data ?? [];
  const loading = devicesQuery.isLoading;

  useEffect(() => {
    if (devices.length > 0 && !selectedDevice) {
      setSelectedDevice(devices[0]);
    }
    if (selectedDevice) {
      const updated = devices.find((d) => d.id === selectedDevice.id);
      if (updated) setSelectedDevice(updated);
    }
  }, [devices]);

  const handleDeviceUpdated = (device: DeviceInfo) => {
    setSelectedDevice(device);
    queryClient.invalidateQueries({ queryKey: ["devices"] });
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="flex flex-col items-center gap-3">
          <div className="w-8 h-8 border-2 border-zinc-500 border-t-blue-500 rounded-full animate-spin" />
          <p className="text-zinc-400 text-sm">Connecting to agent...</p>
        </div>
      </div>
    );
  }

  if (devices.length === 0) {
    return (
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
    );
  }

  if (!selectedDevice) return null;

  return (
    <div className="space-y-4">
      <DeviceDetail
        device={selectedDevice}
        onUpdate={handleDeviceUpdated}
      />
      <TaskRunner selectedDevice={selectedDevice.id} />
    </div>
  );
}
