"use client";

import type { DeviceInfo } from "@/types/device";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";

interface DeviceGridProps {
  devices: DeviceInfo[];
  onSelect: (device: DeviceInfo) => void;
}

const statusColor: Record<string, string> = {
  online: "bg-emerald-400",
  offline: "bg-zinc-500",
  busy: "bg-amber-400 animate-pulse",
  error: "bg-red-400",
};

export function DeviceGrid({ devices, onSelect }: DeviceGridProps) {
  return (
    <div>
      <div className="mb-4">
        <h2 className="text-sm font-medium text-zinc-300">All Devices</h2>
        <p className="text-xs text-zinc-500 mt-0.5">
          {devices.filter((d) => d.status === "online").length} online
        </p>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3">
        {devices.map((d) => (
          <Card
            key={d.id}
            className="p-4 bg-zinc-900 border-zinc-800 hover:border-zinc-700 cursor-pointer transition-colors"
            onClick={() => onSelect(d)}
          >
            <div className="flex items-start justify-between mb-3">
              <div className="flex items-center gap-2">
                <span className={`w-2 h-2 rounded-full ${statusColor[d.status] ?? "bg-zinc-500"}`} />
                <span className="text-xs font-medium text-zinc-300">{d.model ?? d.serial}</span>
              </div>
              <Badge variant="outline" className="text-[9px] px-1.5 py-0 h-4 border-zinc-700 text-zinc-400">
                {d.androidVersion ?? "?"}
              </Badge>
            </div>

            <div className="space-y-1 text-[10px] text-zinc-500">
              <div className="flex justify-between">
                <span>Serial</span>
                <span className="font-mono text-zinc-400">{d.serial}</span>
              </div>
              {d.ip && (
                <div className="flex justify-between">
                  <span>IP</span>
                  <span className="font-mono text-zinc-400">{d.ip}</span>
                </div>
              )}
              <div className="flex justify-between">
                <span>Brand</span>
                <span>{d.brand ?? "-"}</span>
              </div>
            </div>

            {/* Mini props preview */}
            {d.props && (
              <div className="mt-3 pt-3 border-t border-zinc-800">
                <div className="grid grid-cols-2 gap-x-3 gap-y-1 text-[9px]">
                  {d.props.imei_slot1?.enabled && (
                    <>
                      <span className="text-zinc-600">IMEI</span>
                      <span className="font-mono text-zinc-400 truncate">
                        {d.props.imei_slot1.value.slice(0, 8)}...
                      </span>
                    </>
                  )}
                  {d.props.sim_operator_name?.enabled && (
                    <>
                      <span className="text-zinc-600">Carrier</span>
                      <span className="text-zinc-400 truncate">
                        {d.props.sim_operator_name.value}
                      </span>
                    </>
                  )}
                </div>
              </div>
            )}
          </Card>
        ))}
      </div>
    </div>
  );
}
