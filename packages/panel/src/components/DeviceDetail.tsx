"use client";

import { useState, useCallback, useEffect, useMemo } from "react";
import type { DeviceInfo, DeviceMeta, PropValue, BackupInfo } from "@/types/device";
import {
  updateDeviceProps,
  applyDeviceProps,
  createBackup,
  getDeviceMeta,
  refreshDeviceMeta,
  getPackages,
  getBackups,
  restoreBackup,
  type PackageInfo,
} from "@/lib/api";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Input } from "@/components/ui/input";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { ScrollArea } from "@/components/ui/scroll-area";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
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

/* ─────────────────────────────────────────────────────────────
   Backup Modal
   ───────────────────────────────────────────────────────────── */
function BackupModal({
  open,
  onClose,
  deviceId,
}: {
  open: boolean;
  onClose: () => void;
  deviceId: string;
}) {
  const [packages, setPackages] = useState<PackageInfo[]>([]);
  const [loading, setLoading] = useState(false);
  const [search, setSearch] = useState("");
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [backing, setBacking] = useState(false);
  const [activePresets, setActivePresets] = useState<Set<string>>(new Set());

  // ── Preset groups ──
  const presets: { id: string; label: string; desc: string; pkgs: string[] }[] = [
    {
      id: "google",
      label: "🔐 Google Account",
      desc: "Play Services + GSF + Login + Play Store — keeps Google accounts after fingerprint change",
      pkgs: ["com.google.android.gms", "com.google.android.gsf", "com.google.android.gsf.login", "com.android.vending"],
    },
    {
      id: "social",
      label: "💬 Social Apps",
      desc: "Zalo, Facebook, Messenger, Telegram, WhatsApp — chat & social media",
      pkgs: ["com.zing.zalo", "com.facebook.katana", "com.facebook.orca", "org.telegram.messenger", "com.whatsapp"],
    },
    {
      id: "banking",
      label: "🏦 Banking & Finance",
      desc: "Banking apps, e-wallets — MoMo, VCB, MB Bank, Vietinbank, TPBank, BIDV",
      pkgs: ["com.mservice.momotransfer", "com.vnpay.wallet", "com.vcb.vietcombank", "com.mbmobile", "com.vietinbank.ipay", "com.tpbank.mobile", "com.bidv.smartbanking"],
    },
    {
      id: "google_full",
      label: "🟢 Google Full Suite",
      desc: "All Google apps — Gmail, Drive, Photos, Maps, YouTube, Chrome, Meet, Calendar",
      pkgs: ["com.google.android.gm", "com.google.android.apps.docs", "com.google.android.apps.photos", "com.google.android.apps.maps", "com.google.android.youtube", "com.android.chrome", "com.google.android.apps.meetings", "com.google.android.calendar"],
    },
    {
      id: "system",
      label: "⚙️ System IDs",
      desc: "Settings app + system UI — preserves device config, wallpaper, ringtone",
      pkgs: ["com.android.settings", "com.android.systemui", "com.android.providers.settings"],
    },
  ];

  const applyPreset = (id: string, pkgs: string[]) => {
    const isActive = activePresets.has(id);
    setActivePresets((prev) => {
      const next = new Set(prev);
      if (isActive) next.delete(id); else next.add(id);
      return next;
    });
    setSelected((prev) => {
      const next = new Set(prev);
      if (isActive) {
        pkgs.forEach((p) => next.delete(p));
      } else {
        pkgs.forEach((p) => next.add(p));
      }
      return next;
    });
  };

  // Load packages when modal opens
  useEffect(() => {
    if (!open || !deviceId) return;
    let cancelled = false;
    (async () => {
      setLoading(true);
      try {
        const pkgs = await getPackages(deviceId);
        if (!cancelled) setPackages(pkgs);
      } catch (e: any) {
        toast.error(`Failed to load packages: ${e.message}`);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, [open, deviceId]);

  const filtered = useMemo(() => {
    if (!search) return packages;
    const q = search.toLowerCase();
    return packages.filter((p) => p.package.toLowerCase().includes(q));
  }, [packages, search]);

  const toggle = (pkg: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(pkg)) next.delete(pkg);
      else next.add(pkg);
      return next;
    });
    // Deactivate preset if this package belonged to an active preset
    setActivePresets((prev) => {
      const next = new Set(prev);
      for (const preset of presets) {
        if (prev.has(preset.id) && preset.pkgs.includes(pkg)) {
          next.delete(preset.id);
        }
      }
      return next;
    });
  };

  const handleBackup = async () => {
    setBacking(true);
    try {
      const result = await createBackup(deviceId, null as any, Array.from(selected));
      toast.success(`Backup created: ${result.backup.filename}`);
      setSelected(new Set());
      onClose();
    } catch (e: any) {
      toast.error(`Backup failed: ${e.message}`);
    } finally {
      setBacking(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="sm:max-w-lg bg-zinc-900 border-zinc-800 text-zinc-100 max-h-[85vh] flex flex-col">
        <DialogHeader>
          <DialogTitle className="text-sm">📦 Backup App Data</DialogTitle>
        </DialogHeader>

        {/* Search with autocomplete dropdown */}
        <div className="relative">
          <Input
            placeholder="Search packages..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="h-7 text-[11px] bg-zinc-800 border-zinc-700"
          />
          {search && filtered.length > 0 && (
            <div className="absolute z-50 top-full left-0 right-0 mt-1 bg-zinc-800 border border-zinc-700 rounded-lg shadow-xl max-h-48 overflow-y-auto">
              {filtered
                .filter((p) => !selected.has(p.package))
                .map((pkg) => (
                  <div
                    key={pkg.package}
                    className="flex items-center gap-2 px-2 py-1.5 hover:bg-zinc-700 cursor-pointer text-[11px]"
                    onClick={() => { toggle(pkg.package); setSearch(""); }}
                  >
                    <span className="text-zinc-300 font-mono truncate">{pkg.package}</span>
                    {pkg.name && <span className="text-zinc-500 truncate ml-auto">{pkg.name}</span>}
                  </div>
                ))}
              {filtered.every((p) => selected.has(p.package)) && (
                <p className="text-[10px] text-zinc-500 text-center py-2">All matches already selected</p>
              )}
            </div>
          )}
        </div>

        {/* Stats bar */}
        <div className="flex items-center justify-between text-[10px] text-zinc-500">
          <span>{loading ? "Loading..." : `${selected.size} selected`}</span>
          {selected.size > 0 && (
            <button onClick={() => { setSelected(new Set()); setActivePresets(new Set()); }} className="text-red-400 hover:underline">
              Clear all
            </button>
          )}
        </div>

        {/* Preset groups */}
        <div className="flex flex-wrap gap-1.5">
          {presets.map((preset) => (
            <button
              key={preset.id}
              onClick={() => applyPreset(preset.id, preset.pkgs)}
              className={`group relative text-[10px] px-2 py-1 rounded border transition-colors
                ${activePresets.has(preset.id)
                  ? "bg-blue-600/20 border-blue-500/50 text-blue-300"
                  : "bg-zinc-800/70 border-zinc-700/50 text-zinc-400 hover:bg-zinc-700 hover:border-zinc-600 hover:text-zinc-200"
                }`}
              title={preset.desc}
            >
              {preset.label}
              <span className="ml-1 opacity-60">{preset.pkgs.length}</span>
            </button>
          ))}
        </div>

        {/* Selected packages — fixed height, scrollable */}
        <ScrollArea className="h-64 border border-zinc-800 rounded-lg">
          {selected.size === 0 ? (
            <p className="text-[11px] text-zinc-500 text-center py-12">
              {loading ? "Loading..." : "Search and click packages to add"}
            </p>
          ) : (
            <div className="p-1">
              {Array.from(selected).map((pkg) => (
                <div
                  key={pkg}
                  className="flex items-center gap-2 px-2 py-1.5 hover:bg-zinc-800/50 rounded group"
                >
                  <button
                    onClick={() => toggle(pkg)}
                    className="text-zinc-500 hover:text-red-400 text-xs"
                    title="Remove"
                  >
                    ✕
                  </button>
                  <span className="text-[11px] text-zinc-300 font-mono truncate">{pkg}</span>
                </div>
              ))}
            </div>
          )}
        </ScrollArea>

        <div className="flex gap-2 pt-2">
          <Button variant="outline" onClick={onClose} className="h-7 text-[11px] border-zinc-700 text-zinc-300 flex-1">
            Cancel
          </Button>
          <Button
            onClick={handleBackup}
            disabled={selected.size === 0 || backing}
            className="h-7 text-[11px] bg-blue-600 hover:bg-blue-500 flex-1"
          >
            {backing ? "Backing up..." : `Backup (${selected.size})`}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}

/* ─────────────────────────────────────────────────────────────
   Restore Modal
   ───────────────────────────────────────────────────────────── */
function RestoreModal({
  open,
  onClose,
  deviceId,
}: {
  open: boolean;
  onClose: () => void;
  deviceId: string;
}) {
  const [backups, setBackups] = useState<BackupInfo[]>([]);
  const [loading, setLoading] = useState(false);
  const [restoring, setRestoring] = useState<string | null>(null);

  useEffect(() => {
    if (!open) return;
    let cancelled = false;
    (async () => {
      setLoading(true);
      try {
        const list = await getBackups();
        if (!cancelled) setBackups(list);
      } catch (e: any) {
        toast.error(`Failed to load backups: ${e.message}`);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, [open]);

  const handleRestore = async (backup: BackupInfo) => {
    setRestoring(backup.id);
    try {
      await restoreBackup(backup.id, deviceId);
      toast.success(`Restored ${backup.packages?.length ?? 0} packages`);
      onClose();
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
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="sm:max-w-lg bg-zinc-900 border-zinc-800 text-zinc-100 max-h-[85vh] flex flex-col">
        <DialogHeader>
          <DialogTitle className="text-sm">📥 Restore Backup</DialogTitle>
        </DialogHeader>

        {loading ? (
          <div className="flex items-center justify-center h-40">
            <div className="w-5 h-5 border-2 border-zinc-500 border-t-blue-500 rounded-full animate-spin" />
          </div>
        ) : backups.length === 0 ? (
          <div className="text-center py-8 space-y-2">
            <p className="text-zinc-500 text-sm">No backups saved</p>
            <p className="text-zinc-600 text-xs">Use the Backup tab to create one first</p>
          </div>
        ) : (
          <ScrollArea className="flex-1">
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
                        <span className="text-[10px] text-zinc-600 font-mono">{b.deviceSerial}</span>
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
          </ScrollArea>
        )}

        <div className="pt-2">
          <Button variant="outline" onClick={onClose} className="h-7 text-[11px] border-zinc-700 text-zinc-300 w-full">
            Close
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}

/* ─────────────────────────────────────────────────────────────
   Main DeviceDetail
   ───────────────────────────────────────────────────────────── */
export function DeviceDetail({ device, onUpdate }: DeviceDetailProps) {
  const [meta, setMeta] = useState<DeviceMeta | null>(null);
  const [metaLoading, setMetaLoading] = useState(false);
  const [metaError, setMetaError] = useState<string | null>(null);
  const [refreshingMeta, setRefreshingMeta] = useState(false);
  const [editFields, setEditFields] = useState<EditField[]>([]);
  const [saving, setSaving] = useState(false);
  const [applying, setApplying] = useState(false);
  const [backupOpen, setBackupOpen] = useState(false);
  const [restoreOpen, setRestoreOpen] = useState(false);

  // Load meta on mount (skip if offline)
  useEffect(() => {
    if (device.status === "offline") return;
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

  const statusColor: Record<string, string> = {
    online: "bg-emerald-400",
    offline: "bg-zinc-500",
    busy: "bg-amber-400 animate-pulse",
    error: "bg-red-400",
  };

  const isOffline = device.status === "offline";

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
          {!isOffline && (
            <div className="flex items-center gap-1 sm:gap-1.5 flex-wrap">
              <Button
                size="sm"
                variant="outline"
                onClick={() => window.open("http://" + window.location.hostname + ":6081/vnc.html", "_blank")}
                className="h-7 text-[10px] sm:text-[11px] border-zinc-700 text-zinc-300 hover:bg-zinc-800"
              >
                🖥️ VNC
              </Button>
              <Button
                size="sm"
                variant="outline"
                onClick={handleRefreshMeta}
                disabled={refreshingMeta}
                className="h-7 text-[10px] sm:text-[11px] border-zinc-700 text-zinc-300 hover:bg-zinc-800"
              >
                {refreshingMeta ? "⏳" : "🔄"} <span className="hidden sm:inline">{refreshingMeta ? "Collecting..." : meta ? "Refresh Meta" : "Get Info"}</span>
              </Button>
            </div>
          )}
        </div>
      </Card>



      {/* ── Offline message ── */}
      {isOffline && (
        <Card className="p-6 bg-zinc-900 border-zinc-800 text-center">
          <p className="text-sm text-zinc-500">🔌 Device is offline</p>
          <p className="text-[11px] text-zinc-600 mt-1">Connect the device via ADB to manage properties</p>
        </Card>
      )}

      {!isOffline && (
        <>
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
                                <label className="w-[90px] sm:w-[130px] flex-shrink-0 text-[10px] sm:text-[11px] font-medium text-zinc-400 truncate">
                                  {field.label}
                                </label>

                                {/* Input — shows current value, editable when enabled */}
                                <Input
                                  value={field.enabled ? field.newValue : field.currentValue}
                                  onChange={(e) => handleValue(field.key, e.target.value)}
                                  disabled={!field.enabled}
                                  placeholder={field.enabled ? `Enter new ${field.label}...` : ""}
                                  className={`flex-1 min-w-0 h-7 text-[11px] font-mono ${field.enabled
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
              <Card className="p-2 sm:p-3 bg-zinc-900 border-zinc-800">
                <div className="flex items-center gap-1.5 sm:gap-2 flex-wrap">
                  <Button
                    size="sm"
                    onClick={handleSave}
                    disabled={saving}
                    className="h-7 text-[11px] bg-blue-600 hover:bg-blue-500 flex-1 sm:flex-none"
                  >
                    {saving ? "Saving..." : "💾 Save"}
                  </Button>
                  <Button
                    size="sm"
                    onClick={handleApply}
                    disabled={applying || totalEnabled === 0}
                    className="h-7 text-[11px] bg-emerald-600 hover:bg-emerald-500 flex-1 sm:flex-none"
                  >
                    {applying ? "Applying..." : `⚡ Apply (${totalEnabled})`}
                  </Button>
                  <span className="text-[9px] sm:text-[10px] text-zinc-600 w-full sm:w-auto sm:ml-auto text-center sm:text-right">
                    {totalEnabled > 0
                      ? `${totalEnabled} field${totalEnabled !== 1 ? "s" : ""} to change`
                      : "Check ☑ to enable editing"}
                  </span>
                </div>
              </Card>
            </>
          )}
          {/* ── Backup / Restore Quick Actions ── */}
          <Card className="p-2 sm:p-3 bg-zinc-900 border-zinc-800">
            <div className="flex items-center gap-2">
              <span className="text-[10px] text-zinc-500 uppercase tracking-wider">Data</span>
              <Button
                size="sm"
                onClick={() => setBackupOpen(true)}
                className="h-7 text-[11px] bg-blue-600 hover:bg-blue-500 flex-1 sm:flex-none"
              >
                📦 Backup
              </Button>
              <Button
                size="sm"
                variant="outline"
                onClick={() => setRestoreOpen(true)}
                className="h-7 text-[11px] border-zinc-700 text-zinc-300 hover:bg-zinc-800 flex-1 sm:flex-none"
              >
                📥 Restore
              </Button>
            </div>
          </Card>
          {/* ── Modals ── */}
          <BackupModal open={backupOpen} onClose={() => setBackupOpen(false)} deviceId={device.id} />
          <RestoreModal open={restoreOpen} onClose={() => setRestoreOpen(false)} deviceId={device.id} />
        </>
      )}
    </div>
  );
}
