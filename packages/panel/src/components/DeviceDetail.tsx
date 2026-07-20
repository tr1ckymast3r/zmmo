"use client";

import { useState, useCallback } from "react";
import type { DeviceInfo, DeviceProps, PropValue } from "@/types/device";
import { updateDeviceProps, applyDeviceProps, createBackup } from "@/lib/api";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Input } from "@/components/ui/input";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { ScrollArea } from "@/components/ui/scroll-area";
import { toast } from "sonner";

interface DeviceDetailProps {
  device: DeviceInfo;
  onUpdate: (device: DeviceInfo) => void;
}

const CATEGORIES = [
  { id: "sim", label: "SIM", icon: "📶" },
  { id: "device", label: "Device", icon: "📱" },
  { id: "network", label: "Network", icon: "📡" },
  { id: "geo", label: "Geo", icon: "📍" },
  { id: "other", label: "Other", icon: "🔧" },
] as const;

type CategoryId = (typeof CATEGORIES)[number]["id"];

interface PropDef {
  key: keyof DeviceProps;
  label: string;
  category: CategoryId;
}

const PROPS: PropDef[] = [
  // SIM
  { key: "imei_slot1", label: "IMEI Slot 1", category: "sim" },
  { key: "imei_slot2", label: "IMEI Slot 2", category: "sim" },
  { key: "meid", label: "MEID", category: "sim" },
  { key: "imsi_slot1", label: "IMSI Slot 1", category: "sim" },
  { key: "imsi_slot2", label: "IMSI Slot 2", category: "sim" },
  { key: "iccid_slot1", label: "ICCID Slot 1", category: "sim" },
  { key: "iccid_slot2", label: "ICCID Slot 2", category: "sim" },
  { key: "phone_number", label: "Phone Number", category: "sim" },
  { key: "sim_operator", label: "SIM Operator (MCC+MNC)", category: "sim" },
  { key: "sim_operator_name", label: "Carrier Name", category: "sim" },
  { key: "sim_country_iso", label: "SIM Country ISO", category: "sim" },
  // Device
  { key: "brand", label: "Brand", category: "device" },
  { key: "model", label: "Model", category: "device" },
  { key: "manufacturer", label: "Manufacturer", category: "device" },
  { key: "device_name", label: "Device Name", category: "device" },
  { key: "hardware", label: "Hardware", category: "device" },
  { key: "fingerprint", label: "Fingerprint", category: "device" },
  { key: "serial_number", label: "Serial Number", category: "device" },
  { key: "android_id", label: "Android ID", category: "device" },
  { key: "os_version", label: "OS Version", category: "device" },
  { key: "sdk_version", label: "SDK Version", category: "device" },
  { key: "build_id", label: "Build ID", category: "device" },
  { key: "bootloader", label: "Bootloader", category: "device" },
  { key: "radio_version", label: "Radio Version", category: "device" },
  // Network
  { key: "mac_wifi", label: "WiFi MAC", category: "network" },
  { key: "mac_bluetooth", label: "Bluetooth MAC", category: "network" },
  { key: "wifi_ssid", label: "WiFi SSID", category: "network" },
  { key: "wifi_bssid", label: "WiFi BSSID", category: "network" },
  // Geo
  { key: "latitude", label: "Latitude", category: "geo" },
  { key: "longitude", label: "Longitude", category: "geo" },
  { key: "altitude", label: "Altitude", category: "geo" },
  // Other
  { key: "gsf_id", label: "GSF ID", category: "other" },
  { key: "advertising_id", label: "Advertising ID", category: "other" },
];

export function DeviceDetail({ device, onUpdate }: DeviceDetailProps) {
  const [props, setProps] = useState<DeviceProps>(
    device.props ?? ({} as DeviceProps)
  );
  const [saving, setSaving] = useState(false);
  const [applying, setApplying] = useState(false);

  // Count enabled props
  const enabledCount = Object.values(props).filter(
    (p) => p && typeof p === "object" && "enabled" in p && p.enabled
  ).length;

  const handleToggle = useCallback(
    (key: keyof DeviceProps, enabled: boolean) => {
      setProps((prev) => {
        const current = prev[key];
        return {
          ...prev,
          [key]: {
            value: current?.value ?? "",
            enabled,
          },
        };
      });
    },
    []
  );

  const handleValue = useCallback(
    (key: keyof DeviceProps, value: string) => {
      setProps((prev) => {
        const current = prev[key];
        return {
          ...prev,
          [key]: {
            value,
            enabled: current?.enabled ?? false,
          },
        };
      });
    },
    []
  );

  const handleSave = async () => {
    setSaving(true);
    try {
      await updateDeviceProps(device.id, props);
      toast.success("Config saved to device");
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : "Save failed");
    } finally {
      setSaving(false);
    }
  };

  const handleApply = async () => {
    setApplying(true);
    try {
      await updateDeviceProps(device.id, props);
      await applyDeviceProps(device.id);
      toast.success("Config applied — device props updated");
      // Refresh device info
      const updated = { ...device, props };
      onUpdate(updated);
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : "Apply failed");
    } finally {
      setApplying(false);
    }
  };

  const handleBackup = async () => {
    try {
      const backup = await createBackup(device.id, props);
      toast.success(`Backup created: ${backup.filename}`);
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : "Backup failed");
    }
  };

  const statusColor: Record<string, string> = {
    online: "bg-emerald-400",
    offline: "bg-zinc-500",
    busy: "bg-amber-400 animate-pulse",
    error: "bg-red-400",
  };

  return (
    <div className="space-y-4">
      {/* Device Header */}
      <Card className="p-4 bg-zinc-900 border-zinc-800">
        <div className="flex items-center justify-between flex-wrap gap-3">
          <div className="flex items-center gap-3 min-w-0">
            <span className={`w-2.5 h-2.5 rounded-full flex-shrink-0 ${statusColor[device.status] ?? "bg-zinc-500"}`} />
            <div className="min-w-0">
              <h2 className="text-sm font-semibold text-zinc-100 truncate">
                {device.model ?? device.serial}
              </h2>
              <p className="text-xs text-zinc-500 font-mono">{device.serial}</p>
            </div>
            <Badge variant="outline" className="border-zinc-700 text-zinc-400 text-[10px]">
              {device.androidVersion ?? "?"}
            </Badge>
            {device.ip && (
              <Badge variant="secondary" className="bg-zinc-800 text-zinc-400 text-[10px] font-mono">
                {device.ip}
              </Badge>
            )}
          </div>
          <div className="flex items-center gap-2">
            <span className="text-[10px] text-zinc-500">
              {enabledCount}/{PROPS.length} props active
            </span>
          </div>
        </div>
      </Card>

      {/* Props Tabs */}
      <Tabs defaultValue="sim" className="w-full">
        <TabsList className="w-full bg-zinc-900 border border-zinc-800 p-1 h-auto justify-start overflow-x-auto">
          {CATEGORIES.map((cat) => {
            const catProps = PROPS.filter((p) => p.category === cat.id);
            const catEnabled = catProps.filter(
              (p) => props[p.key]?.enabled
            ).length;
            return (
              <TabsTrigger
                key={cat.id}
                value={cat.id}
                className="text-xs px-3 py-1.5 data-[state=active]:bg-zinc-800 flex items-center gap-1.5"
              >
                <span>{cat.icon}</span>
                <span className="hidden sm:inline">{cat.label}</span>
                <span className="text-[9px] text-zinc-500 tabular-nums">
                  {catEnabled}/{catProps.length}
                </span>
              </TabsTrigger>
            );
          })}
        </TabsList>

        {CATEGORIES.map((cat) => (
          <TabsContent key={cat.id} value={cat.id} className="mt-2">
            <Card className="bg-zinc-900 border-zinc-800">
              <ScrollArea className="h-[50vh] sm:h-[55vh]">
                <div className="p-3 divide-y divide-zinc-800/50">
                  {PROPS.filter((p) => p.category === cat.id).map((prop) => {
                    const val: PropValue | undefined = props[prop.key];
                    const enabled = val?.enabled ?? false;
                    const value = val?.value ?? "";
                    return (
                      <div
                        key={prop.key}
                        className="flex items-center gap-3 py-2.5 first:pt-0 last:pb-0"
                      >
                        <Switch
                          checked={enabled}
                          onCheckedChange={(v) => handleToggle(prop.key, v)}
                          className="flex-shrink-0"
                        />
                        <div className="flex-1 min-w-0">
                          <label className="text-xs font-medium text-zinc-300 block truncate">
                            {prop.label}
                          </label>
                          {enabled && (
                            <Input
                              value={value}
                              onChange={(e) =>
                                handleValue(prop.key, e.target.value)
                              }
                              placeholder={`Enter ${prop.label}...`}
                              className="mt-1 h-7 text-[11px] bg-zinc-800 border-zinc-700 text-zinc-200 font-mono"
                            />
                          )}
                        </div>
                      </div>
                    );
                  })}
                </div>
              </ScrollArea>
            </Card>
          </TabsContent>
        ))}
      </Tabs>

      {/* Action Bar */}
      <Card className="p-3 bg-zinc-900 border-zinc-800">
        <div className="flex items-center gap-2 flex-wrap">
          <Button
            size="sm"
            onClick={handleSave}
            disabled={saving}
            className="h-8 text-xs bg-blue-600 hover:bg-blue-500"
          >
            {saving ? "Saving..." : "💾 Save Config"}
          </Button>
          <Button
            size="sm"
            onClick={handleApply}
            disabled={applying}
            className="h-8 text-xs bg-emerald-600 hover:bg-emerald-500"
          >
            {applying ? "Applying..." : "⚡ Apply Now"}
          </Button>
          <Button
            size="sm"
            variant="outline"
            onClick={handleBackup}
            className="h-8 text-xs border-zinc-700 text-zinc-300 hover:bg-zinc-800"
          >
            📦 Backup
          </Button>
          <span className="text-[10px] text-zinc-600 ml-auto">
            Changes saved locally on device
          </span>
        </div>
      </Card>
    </div>
  );
}
