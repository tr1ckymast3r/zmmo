"use client";

import { useState, useMemo } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import type { DeviceInfo, BackupInfo } from "@/types/device";
import { getPackages, createBackup, getBackups, restoreBackup, type PackageInfo } from "@/lib/api";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Switch } from "@/components/ui/switch";
import { toast } from "sonner";

interface BackupManagerProps {
  selectedDevice: string;
  devices: DeviceInfo[];
}

export function BackupManager({ selectedDevice, devices }: BackupManagerProps) {
  const queryClient = useQueryClient();
  const [deviceId, setDeviceId] = useState(selectedDevice);
  const [search, setSearch] = useState("");
  const [selectedPkgs, setSelectedPkgs] = useState<Set<string>>(new Set());
  const [targetDir, setTargetDir] = useState("");
  const [backing, setBacking] = useState(false);
  const [restoring, setRestoring] = useState<string | null>(null);

  // Packages list
  const pkgsQuery = useQuery({
    queryKey: ["packages", deviceId],
    queryFn: () => getPackages(deviceId),
    enabled: !!deviceId,
    refetchOnMount: true,
  });

  // Backups list
  const backupsQuery = useQuery({
    queryKey: ["backups"],
    queryFn: getBackups,
    refetchInterval: 5000,
  });

  const packages = pkgsQuery.data ?? [];
  const backups = backupsQuery.data ?? [];

  const filtered = useMemo(() => {
    if (!search) return packages;
    const q = search.toLowerCase();
    return packages.filter((p) => p.package.toLowerCase().includes(q));
  }, [packages, search]);

  const togglePkg = (pkg: string) => {
    setSelectedPkgs((prev) => {
      const next = new Set(prev);
      if (next.has(pkg)) next.delete(pkg);
      else next.add(pkg);
      return next;
    });
  };

  const selectAll = () => {
    if (selectedPkgs.size === filtered.length) {
      setSelectedPkgs(new Set());
    } else {
      setSelectedPkgs(new Set(filtered.map((p) => p.package)));
    }
  };

  const handleBackup = async () => {
    if (selectedPkgs.size === 0) return;
    setBacking(true);
    try {
      const pkgList = Array.from(selectedPkgs);
      await createBackup(deviceId, null as any, pkgList, targetDir || undefined);
      toast.success(`Backup created: ${pkgList.length} packages`);
      setSelectedPkgs(new Set());
      queryClient.invalidateQueries({ queryKey: ["backups"] });
    } catch (e: any) {
      toast.error(`Backup failed: ${e.message}`);
    } finally {
      setBacking(false);
    }
  };

  const handleRestore = async (backup: BackupInfo) => {
    setRestoring(backup.id);
    try {
      await restoreBackup(backup.id, deviceId);
      toast.success(`Restored ${backup.packages?.length ?? 0} packages`);
    } catch (e: any) {
      toast.error(`Restore failed: ${e.message}`);
    } finally {
      setRestoring(null);
    }
  };

  const sizeFmt = (bytes: number) => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  };

  return (
    <div className="space-y-4">
      {/* Device Picker */}
      <Card className="bg-zinc-900 border-zinc-800">
        <CardHeader className="pb-2">
          <CardTitle className="text-sm font-medium">Backup & Restore</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <select
            value={deviceId}
            onChange={(e) => setDeviceId(e.target.value)}
            className="w-full h-8 rounded-lg bg-zinc-800 border border-zinc-700 text-zinc-200 text-xs px-2"
          >
            {devices.map((d) => (
              <option key={d.id} value={d.id}>
                {d.model ?? d.serial} ({d.serial})
              </option>
            ))}
          </select>

          {/* Package list */}
          <div>
            <div className="flex items-center justify-between mb-2">
              <span className="text-xs text-zinc-400">
                {pkgsQuery.isLoading
                  ? "Loading packages..."
                  : `${selectedPkgs.size} / ${packages.length} selected`}
              </span>
              <button onClick={selectAll} className="text-[10px] text-blue-400 hover:underline">
                {selectedPkgs.size === filtered.length ? "Deselect all" : "Select all"}
              </button>
            </div>
            <Input
              placeholder="Search packages..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="h-7 text-[11px] mb-2 bg-zinc-800 border-zinc-700"
            />
            <ScrollArea className="h-64 rounded-lg border border-zinc-800">
              <div className="p-1">
                {filtered.map((pkg) => (
                  <label
                    key={pkg.package}
                    className="flex items-center gap-2 px-2 py-1.5 hover:bg-zinc-800/50 rounded cursor-pointer"
                  >
                    <Switch
                      checked={selectedPkgs.has(pkg.package)}
                      onCheckedChange={() => togglePkg(pkg.package)}
                      className="scale-75"
                    />
                    <span className="text-[11px] text-zinc-300 font-mono truncate flex-1">
                      {pkg.package}
                    </span>
                  </label>
                ))}
                {filtered.length === 0 && !pkgsQuery.isLoading && (
                  <p className="text-[11px] text-zinc-500 text-center py-4">
                    {packages.length === 0 ? "No packages found" : "No matches"}
                  </p>
                )}
              </div>
            </ScrollArea>
          </div>

          {/* Target dir + Backup button */}
          <div className="flex gap-2">
            <Input
              placeholder="Target dir (default: ./backups)"
              value={targetDir}
              onChange={(e) => setTargetDir(e.target.value)}
              className="h-7 text-[11px] flex-1 bg-zinc-800 border-zinc-700"
            />
            <Button
              onClick={handleBackup}
              disabled={selectedPkgs.size === 0 || backing}
              className="h-7 text-[11px] bg-blue-600 hover:bg-blue-500"
            >
              {backing ? "Backing up..." : `Backup (${selectedPkgs.size})`}
            </Button>
          </div>
        </CardContent>
      </Card>

      {/* Existing Backups */}
      <Card className="bg-zinc-900 border-zinc-800">
        <CardHeader className="pb-2">
          <CardTitle className="text-sm font-medium">
            Saved Backups ({backups.length})
          </CardTitle>
        </CardHeader>
        <CardContent>
          {backups.length === 0 ? (
            <p className="text-xs text-zinc-500 text-center py-4">No backups yet</p>
          ) : (
            <div className="space-y-2">
              {backups.map((b) => (
                <div
                  key={b.id}
                  className="flex items-center gap-3 p-2.5 rounded-lg bg-zinc-800/50 border border-zinc-700/50"
                >
                  <div className="flex-1 min-w-0">
                    <p className="text-xs text-zinc-200 font-mono truncate">{b.filename}</p>
                    <div className="flex items-center gap-2 mt-0.5">
                      <span className="text-[10px] text-zinc-500">{sizeFmt(b.size)}</span>
                      {b.packages && (
                        <Badge variant="outline" className="text-[9px] px-1 py-0 h-4 border-zinc-700 text-zinc-400">
                          {b.packages.length} pkgs
                        </Badge>
                      )}
                      {b.deviceSerial && (
                        <span className="text-[10px] text-zinc-600">{b.deviceSerial}</span>
                      )}
                    </div>
                  </div>
                  <Button
                    onClick={() => handleRestore(b)}
                    disabled={restoring === b.id}
                    className="h-6 text-[10px] px-2 bg-emerald-600 hover:bg-emerald-500"
                  >
                    {restoring === b.id ? "Restoring..." : "Restore"}
                  </Button>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
