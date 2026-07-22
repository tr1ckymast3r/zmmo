import { createFileRoute, Link } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import { getDevices } from "@/lib/api";
import { BackupManager } from "@/components/BackupManager";
import { Toaster } from "@/components/ui/sonner";

export const Route = createFileRoute("/backups")({
  component: BackupsPage,
});

function BackupsPage() {
  const devicesQuery = useQuery({
    queryKey: ["devices"],
    queryFn: getDevices,
    refetchInterval: 10000,
  });

  const devices = devicesQuery.data ?? [];

  return (
    <div className="min-h-screen bg-zinc-950 text-zinc-100">
      <header className="sticky top-0 z-50 border-b border-zinc-800 bg-zinc-950/80 backdrop-blur">
        <div className="flex items-center justify-between h-14 px-3 sm:px-4">
          <div className="flex items-center gap-2 sm:gap-3">
            <Link
              to="/"
              className="font-semibold text-sm sm:text-base tracking-tight flex items-center gap-2 hover:opacity-80 transition-opacity"
            >
              <span className="w-7 h-7 rounded-md bg-gradient-to-br from-blue-600 to-purple-600 flex items-center justify-center text-white text-xs font-bold">DC</span>
              <span className="hidden sm:inline">Device Changer</span>
            </Link>
            <span className="text-zinc-500 text-sm hidden sm:inline">/</span>
            <span className="text-zinc-300 text-sm hidden sm:inline font-medium">Backup & Restore</span>
          </div>
          <Link
            to="/"
            className="h-7 text-[10px] sm:text-xs text-zinc-400 hover:text-zinc-200 px-2 flex items-center gap-1 rounded-lg hover:bg-zinc-800 transition-colors"
          >
            &larr; Back to Dashboard
          </Link>
        </div>
      </header>

      <main className="max-w-2xl mx-auto p-4 sm:p-6 md:p-8">
        {devicesQuery.isLoading ? (
          <div className="flex items-center justify-center h-64">
            <div className="w-8 h-8 border-2 border-zinc-500 border-t-blue-500 rounded-full animate-spin" />
          </div>
        ) : devices.length === 0 ? (
          <div className="text-center py-16">
            <p className="text-zinc-500 text-sm">No devices connected</p>
            <p className="text-zinc-600 text-xs mt-1">Connect a device to backup app data</p>
          </div>
        ) : (
          <BackupManager selectedDevice={devices[0]?.id ?? ""} devices={devices} />
        )}
      </main>

      <Toaster theme="dark" position="bottom-center" />
    </div>
  );
}
