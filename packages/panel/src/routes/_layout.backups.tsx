import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { getDevices } from "@/lib/api";
import { BackupManager } from "@/components/BackupManager";

export const Route = createFileRoute("/_layout/backups")({
  component: BackupsContent,
});

function BackupsContent() {
  const devicesQuery = useQuery({
    queryKey: ["devices"],
    queryFn: getDevices,
    refetchInterval: 10000,
  });

  const devices = devicesQuery.data ?? [];

  if (devicesQuery.isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="w-8 h-8 border-2 border-zinc-500 border-t-blue-500 rounded-full animate-spin" />
      </div>
    );
  }

  if (devices.length === 0) {
    return (
      <div className="text-center py-16">
        <p className="text-zinc-500 text-sm">No devices connected</p>
        <p className="text-zinc-600 text-xs mt-1">Connect a device to backup app data</p>
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto">
      <h2 className="text-sm font-semibold text-zinc-100 mb-4">Backup & Restore</h2>
      <BackupManager selectedDevice={devices[0]?.id ?? ""} devices={devices} />
    </div>
  );
}
