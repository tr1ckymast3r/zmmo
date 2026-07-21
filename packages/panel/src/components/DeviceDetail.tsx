"use client";

import { useState, useCallback, useEffect } from "react";
import type { DeviceInfo, DeviceMeta, PropValue } from "@/types/device";
import { updateDeviceProps, applyDeviceProps, createBackup, getDeviceMeta, refreshDeviceMeta } from "@/lib/api";
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

interface EditField {
  key: string;
  label: string;
  currentValue: string;
  newValue: string;
  enabled: boolean;
  category: CategoryId;
}

const CATEGORIES = [
  { id: "sim", label: "SIM", icon: "📶" },
  { id: "device", label: "Device", icon: "📱" },
  { id: "network", label: "Network", icon: "📡" },
  { id: "geo", label: "Geo", icon: "📍" },
  { id: "other", label: "Other", icon: "🔧" },
] as const;

type CategoryId = (typeof CATEGORIES)[number]["id"];

// Map DeviceMeta fields → editable form fields
function buildEditFields(meta: DeviceMeta | null): EditField[] {
  const empty = (v: string = "") => v;
  const m = meta ?? ({} as DeviceMeta);

  return [
    // SIM
    { key: "imei1", label: "IMEI Slot 1", currentValue: empty(m.imei1), newValue: empty(m.imei1), enabled: false, category: "sim" },
    { key: "imei2", label: "IMEI Slot 2", currentValue: empty(m.imei2), newValue: empty(m.imei2), enabled: false, category: "sim" },
    { key: "meid", label: "MEID", currentValue: empty(m.meid), newValue: empty(m.meid), enabled: false, category: "sim" },
    { key: "imsi1", label: "IMSI Slot 1", currentValue: empty(m.imsi1), newValue: empty(m.imsi1), enabled: false, category: "sim" },
    { key: "imsi2", label: "IMSI Slot 2", currentValue: empty(m.imsi2), newValue: empty(m.imsi2), enabled: false, category: "sim" },
    { key: "iccid1", label: "ICCID Slot 1", currentValue: empty(m.iccid1), newValue: empty(m.iccid1), enabled: false, category: "sim" },
    { key: "iccid2", label: "ICCID Slot 2", currentValue: empty(m.iccid2), newValue: empty(m.iccid2), enabled: false, category: "sim" },
    { key: "phoneNumber", label: "Phone Number", currentValue: empty(m.phoneNumber), newValue: empty(m.phoneNumber), enabled: false, category: "sim" },
    { key: "simOperator", label: "SIM Operator (MCC+MNC)", currentValue: empty(m.simOperator), newValue: empty(m.simOperator), enabled: false, category: "sim" },
    { key: "simCarrier", label: "Carrier Name", currentValue: empty(m.simCarrier), newValue: empty(m.simCarrier), enabled: false, category: "sim" },
    { key: "simCountry", label: "SIM Country ISO", currentValue: empty(m.simCountry), newValue: empty(m.simCountry), enabled: false, category: "sim" },
    // Device Identity
    { key: "brand", label: "Brand", currentValue: empty(m.brand), newValue: empty(m.brand), enabled: false, category: "device" },
    { key: "model", label: "Model", currentValue: empty(m.model), newValue: empty(m.model), enabled: false, category: "device" },
    { key: "manufacturer", label: "Manufacturer", currentValue: empty(m.manufacturer), newValue: empty(m.manufacturer), enabled: false, category: "device" },
    { key: "deviceName", label: "Device Name", currentValue: empty(m.deviceName), newValue: empty(m.deviceName), enabled: false, category: "device" },
    { key: "productName", label: "Product Name", currentValue: empty(m.productName), newValue: empty(m.productName), enabled: false, category: "device" },
    { key: "device", label: "Device (codename)", currentValue: empty(m.device), newValue: empty(m.device), enabled: false, category: "device" },
    { key: "board", label: "Board", currentValue: empty(m.board), newValue: empty(m.board), enabled: false, category: "device" },
    { key: "hardware", label: "Hardware", currentValue: empty(m.hardware), newValue: empty(m.hardware), enabled: false, category: "device" },
    { key: "platform", label: "Platform", currentValue: empty(m.platform), newValue: empty(m.platform), enabled: false, category: "device" },
    // Build
    { key: "fingerprint", label: "Fingerprint", currentValue: empty(m.fingerprint), newValue: empty(m.fingerprint), enabled: false, category: "device" },
    { key: "buildId", label: "Build ID", currentValue: empty(m.buildId), newValue: empty(m.buildId), enabled: false, category: "device" },
    { key: "buildType", label: "Build Type", currentValue: empty(m.buildType), newValue: empty(m.buildType), enabled: false, category: "device" },
    { key: "osVersion", label: "OS Version", currentValue: empty(m.osVersion), newValue: empty(m.osVersion), enabled: false, category: "device" },
    { key: "sdkVersion", label: "SDK Version", currentValue: empty(m.sdkVersion), newValue: empty(m.sdkVersion), enabled: false, category: "device" },
    { key: "incremental", label: "Incremental", currentValue: empty(m.incremental), newValue: empty(m.incremental), enabled: false, category: "device" },
    { key: "securityPatch", label: "Security Patch", currentValue: empty(m.securityPatch), newValue: empty(m.securityPatch), enabled: false, category: "device" },
    { key: "bootloader", label: "Bootloader", currentValue: empty(m.bootloader), newValue: empty(m.bootloader), enabled: false, category: "device" },
    { key: "radioBaseband", label: "Radio Baseband", currentValue: empty(m.radioBaseband), newValue: empty(m.radioBaseband), enabled: false, category: "device" },
    // Display
    { key: "displayDensity", label: "Display Density", currentValue: empty(m.displayDensity), newValue: empty(m.displayDensity), enabled: false, category: "device" },
    { key: "displayWidth", label: "Display Width", currentValue: empty(m.displayWidth), newValue: empty(m.displayWidth), enabled: false, category: "device" },
    { key: "displayHeight", label: "Display Height", currentValue: empty(m.displayHeight), newValue: empty(m.displayHeight), enabled: false, category: "device" },
    // Network
    { key: "macWifi", label: "WiFi MAC", currentValue: empty(m.macWifi), newValue: empty(m.macWifi), enabled: false, category: "network" },
    { key: "macBluetooth", label: "Bluetooth MAC", currentValue: empty(m.macBluetooth), newValue: empty(m.macBluetooth), enabled: false, category: "network" },
    { key: "wifiSsid", label: "WiFi SSID", currentValue: empty(m.wifiSsid), newValue: empty(m.wifiSsid), enabled: false, category: "network" },
    { key: "wifiBssid", label: "WiFi BSSID", currentValue: empty(m.wifiBssid), newValue: empty(m.wifiBssid), enabled: false, category: "network" },
    { key: "ipAddress", label: "IP Address", currentValue: empty(m.ipAddress), newValue: empty(m.ipAddress), enabled: false, category: "network" },
    // Geo
    { key: "latitude", label: "Latitude", currentValue: "", newValue: "", enabled: false, category: "geo" },
    { key: "longitude", label: "Longitude", currentValue: "", newValue: "", enabled: false, category: "geo" },
    { key: "altitude", label: "Altitude", currentValue: "", newValue: "", enabled: false, category: "geo" },
    // Other
    { key: "androidId", label: "Android ID", currentValue: empty(m.androidId), newValue: empty(m.androidId), enabled: false, category: "other" },
    { key: "gsfId", label: "GSF ID", currentValue: empty(m.gsfId), newValue: empty(m.gsfId), enabled: false, category: "other" },
    { key: "advertisingId", label: "Advertising ID", currentValue: empty(m.advertisingId), newValue: empty(m.advertisingId), enabled: false, category: "other" },
    { key: "timezone", label: "Timezone", currentValue: empty(m.timezone), newValue: empty(m.timezone), enabled: false, category: "other" },
    { key: "language", label: "Language", currentValue: empty(m.language), newValue: empty(m.language), enabled: false, category: "other" },
    { key: "cpuAbi", label: "CPU ABI", currentValue: empty(m.cpuAbi), newValue: empty(m.cpuAbi), enabled: false, category: "other" },
    { key: "totalRam", label: "Total RAM", currentValue: empty(m.totalRam), newValue: empty(m.totalRam), enabled: false, category: "other" },
    { key: "internalSize", label: "Internal Storage", currentValue: empty(m.internalSize), newValue: empty(m.internalSize), enabled: false, category: "other" },
  ];
}

// Compact info cards shown above the edit form
function InfoSummary({ meta }: { meta: DeviceMeta }) {
  const items = [
    { label: "IMEI 1", value: meta.imei1 || "—" },
    { label: "MAC WiFi", value: meta.macWifi || "—" },
    { label: "Android ID", value: meta.androidId?.slice(0, 12) + "…" || "—" },
    { label: "SIM Carrier", value: meta.simCarrier || "—" },
    { label: "Fingerprint", value: meta.fingerprint?.slice(0, 20) + "…" || "—" },
    { label: "IP", value: meta.ipAddress || "—" },
    { label: "Display", value: meta.displayWidth && meta.displayHeight ? `${meta.displayWidth}×${meta.displayHeight}` : "—" },
    { label: "RAM", value: meta.totalRam || "—" },
  ];

  return (
    <Card className="p-3 bg-zinc-900/70 border-zinc-800">
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
        {items.map((item) => (
          <div key={item.label} className="space-y-0.5">
            <p className="text-[9px] text-zinc-500 uppercase tracking-wider">{item.label}</p>
            <p className="text-[11px] text-zinc-300 font-mono truncate" title={item.value}>
              {item.value}
            </p>
          </div>
        ))}
      </div>
      <p className="text-[9px] text-zinc-600 mt-2">
        Collected {meta.collectedAt ? new Date(meta.collectedAt).toLocaleString() : "unknown"}
      </p>
    </Card>
  );
}

export function DeviceDetail({ device, onUpdate }: DeviceDetailProps) {
  const [meta, setMeta] = useState<DeviceMeta | null>(null);
  const [metaLoading, setMetaLoading] = useState(false);
  const [metaError, setMetaError] = useState<string | null>(null);
  const [refreshingMeta, setRefreshingMeta] = useState(false);
  const [editFields, setEditFields] = useState<EditField[]>([]);
  const [saving, setSaving] = useState(false);
  const [applying, setApplying] = useState(false);

  // Load meta on mount
  useEffect(() => {
    let cancelled = false;
    async function load() {
      setMetaLoading(true);
      setMetaError(null);
      try {
        const result = await getDeviceMeta(device.id);
        if (cancelled) return;
        if (result.found && result.meta) {
          setMeta(result.meta);
          setEditFields(buildEditFields(result.meta));
        } else {
          setMetaError(result.message ?? "No metadata");
        }
      } catch (e: unknown) {
        if (!cancelled) {
          setMetaError(e instanceof Error ? e.message : "Failed to load meta");
        }
      } finally {
        if (!cancelled) setMetaLoading(false);
      }
    }
    load();
    return () => { cancelled = true; };
  }, [device.id]);

  // Refresh Meta
  const handleRefreshMeta = async () => {
    setRefreshingMeta(true);
    setMetaError(null);
    try {
      const result = await refreshDeviceMeta(device.id);
      setMeta(result.meta);
      setEditFields(buildEditFields(result.meta));
      toast.success(`Meta collected → ${result.path}`);
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : "Meta refresh failed");
    } finally {
      setRefreshingMeta(false);
    }
  };

  // Toggle edit checkbox
  const handleToggle = useCallback((key: string, enabled: boolean) => {
    setEditFields((prev) =>
      prev.map((f) => (f.key === key ? { ...f, enabled } : f))
    );
  }, []);

  // Update value
  const handleValue = useCallback((key: string, value: string) => {
    setEditFields((prev) =>
      prev.map((f) => (f.key === key ? { ...f, newValue: value } : f))
    );
  }, []);

  // Count enabled fields per category
  const catStats = (catId: CategoryId) => {
    const fields = editFields.filter((f) => f.category === catId);
    const enabled = fields.filter((f) => f.enabled).length;
    return { total: fields.length, enabled };
  };

  const totalEnabled = editFields.filter((f) => f.enabled).length;

  // Save config to device (PUT /devices/:id/props)
  const handleSave = async () => {
    setSaving(true);
    try {
      const props: Record<string, PropValue> = {};
      for (const f of editFields) {
        props[f.key] = { value: f.newValue, enabled: f.enabled };
      }
      // Convert to the format the backend expects and save
      const deviceProps = {} as Record<string, PropValue>;
      for (const f of editFields) {
        deviceProps[f.key] = { value: f.newValue, enabled: f.enabled };
      }
      await updateDeviceProps(device.id, deviceProps as any);
      toast.success("Config saved to device");
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : "Save failed");
    } finally {
      setSaving(false);
    }
  };

  // Apply changes to device
  const handleApply = async () => {
    setApplying(true);
    try {
      await handleSave();
      await applyDeviceProps(device.id);
      toast.success("Config applied — device props updated");
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : "Apply failed");
    } finally {
      setApplying(false);
    }
  };

  // Backup
  const handleBackup = async () => {
    try {
      const backup = await createBackup(device.id, {} as any);
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
    <div className="space-y-3">
      {/* ── Device Header ── */}
      <Card className="p-3 bg-zinc-900 border-zinc-800">
        <div className="flex items-center justify-between flex-wrap gap-2">
          <div className="flex items-center gap-3 min-w-0">
            <span className={`w-2.5 h-2.5 rounded-full flex-shrink-0 ${statusColor[device.status] ?? "bg-zinc-500"}`} />
            <div className="min-w-0">
              <h2 className="text-sm font-semibold text-zinc-100 truncate">
                {device.model ?? device.serial}
              </h2>
              <p className="text-[10px] text-zinc-500 font-mono">{device.serial}</p>
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
          <Button
            size="sm"
            variant="outline"
            onClick={handleRefreshMeta}
            disabled={refreshingMeta}
            className="h-7 text-[11px] border-zinc-700 text-zinc-300 hover:bg-zinc-800"
          >
            {refreshingMeta ? "⏳ Collecting..." : `🔄 ${meta ? "Refresh Meta" : "Get Device Info"}`}
          </Button>
        </div>
      </Card>

      {/* ── Meta Loading / Error / Summary ── */}
      {metaLoading && (
        <Card className="p-6 bg-zinc-900 border-zinc-800 text-center">
          <p className="text-sm text-zinc-400">⏳ Loading device metadata...</p>
        </Card>
      )}

      {!metaLoading && metaError && !meta && (
        <Card className="p-4 bg-zinc-900 border-zinc-800 text-center space-y-3">
          <p className="text-sm text-amber-400">⚠️ No device metadata yet</p>
          <p className="text-[11px] text-zinc-500">Click &quot;Get Device Info&quot; to collect all device properties via ADB</p>
          <Button
            size="sm"
            onClick={handleRefreshMeta}
            disabled={refreshingMeta}
            className="h-7 text-[11px] bg-blue-600 hover:bg-blue-500"
          >
            {refreshingMeta ? "⏳ Collecting..." : "🔄 Collect Device Info Now"}
          </Button>
        </Card>
      )}

      {/* ── Info Summary ── */}
      {meta && <InfoSummary meta={meta} />}

      {/* ── Edit Form ── */}
      {meta && (
        <>
          <Tabs defaultValue="sim" className="w-full">
            <TabsList className="w-full bg-zinc-900 border border-zinc-800 p-1 h-auto justify-start overflow-x-auto sticky top-0 z-10">
              {CATEGORIES.map((cat) => {
                const stats = catStats(cat.id);
                return (
                  <TabsTrigger
                    key={cat.id}
                    value={cat.id}
                    className="text-[10px] px-2.5 py-1 data-[state=active]:bg-zinc-800 flex items-center gap-1"
                  >
                    <span>{cat.icon}</span>
                    <span className="hidden sm:inline">{cat.label}</span>
                    <Badge variant="outline" className={`text-[8px] px-1 py-0 border-zinc-700 ${stats.enabled > 0 ? "text-emerald-400 border-emerald-800" : "text-zinc-500"}`}>
                      {stats.enabled}/{stats.total}
                    </Badge>
                  </TabsTrigger>
                );
              })}
            </TabsList>

            {CATEGORIES.map((cat) => {
              const fields = editFields.filter((f) => f.category === cat.id);
              return (
                <TabsContent key={cat.id} value={cat.id} className="mt-2">
                  <Card className="bg-zinc-900 border-zinc-800">
                    <ScrollArea className="h-[50vh] sm:h-[55vh]">
                      <div className="divide-y divide-zinc-800/50">
                        {fields.map((field) => (
                          <div key={field.key} className="flex items-center gap-2 px-3 py-2">
                            {/* Label */}
                            <label className="w-[120px] sm:w-[140px] flex-shrink-0 text-[11px] font-medium text-zinc-400 truncate">
                              {field.label}
                            </label>

                            {/* Input — shows current value, editable when enabled */}
                            <Input
                              value={field.enabled ? field.newValue : field.currentValue}
                              onChange={(e) => handleValue(field.key, e.target.value)}
                              disabled={!field.enabled}
                              placeholder={field.enabled ? `Enter new ${field.label}...` : ""}
                              className={`flex-1 min-w-0 h-7 text-[11px] font-mono ${
                                field.enabled
                                  ? "bg-zinc-800 border-zinc-600 text-zinc-200"
                                  : "bg-zinc-900/50 border-zinc-800 text-zinc-500"
                              }`}
                            />

                            {/* Checkbox to enable editing */}
                            <div className="flex items-center gap-1 flex-shrink-0">
                              <Switch
                                checked={field.enabled}
                                onCheckedChange={(v) => handleToggle(field.key, v)}
                                className="scale-75"
                              />
                              <span className="text-[8px] text-zinc-600 w-5 text-center">
                                {field.enabled ? "ON" : ""}
                              </span>
                            </div>
                          </div>
                        ))}
                      </div>
                    </ScrollArea>
                  </Card>
                </TabsContent>
              );
            })}
          </Tabs>

          {/* ── Action Bar ── */}
          <Card className="p-3 bg-zinc-900 border-zinc-800">
            <div className="flex items-center gap-2 flex-wrap">
              <Button
                size="sm"
                onClick={handleSave}
                disabled={saving}
                className="h-7 text-[11px] bg-blue-600 hover:bg-blue-500"
              >
                {saving ? "Saving..." : "💾 Save Config"}
              </Button>
              <Button
                size="sm"
                onClick={handleApply}
                disabled={applying || totalEnabled === 0}
                className="h-7 text-[11px] bg-emerald-600 hover:bg-emerald-500"
              >
                {applying ? "Applying..." : `⚡ Apply Now (${totalEnabled})`}
              </Button>
              <Button
                size="sm"
                variant="outline"
                onClick={handleBackup}
                className="h-7 text-[11px] border-zinc-700 text-zinc-300 hover:bg-zinc-800"
              >
                📦 Backup
              </Button>
              <span className="text-[10px] text-zinc-600 ml-auto">
                {totalEnabled > 0
                  ? `${totalEnabled} field${totalEnabled !== 1 ? "s" : ""} to change`
                  : "Check ☑ to enable editing"}
              </span>
            </div>
          </Card>
        </>
      )}
    </div>
  );
}
