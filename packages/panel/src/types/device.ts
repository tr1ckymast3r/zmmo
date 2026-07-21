// Types for Device Changer system

export interface DeviceInfo {
  id: string;
  serial: string;
  model: string;
  brand: string;
  androidVersion: string;
  sdkVersion: number;
  status: DeviceStatus;
  ip?: string;
  adbPort?: number;
  lastSeen: string;
  props: DeviceProps | null;
}

export type DeviceStatus = "online" | "offline" | "busy" | "error";

export interface DeviceProps {
  // SIM
  imei_slot1: PropValue;
  imei_slot2: PropValue;
  meid: PropValue;
  imsi_slot1: PropValue;
  imsi_slot2: PropValue;
  iccid_slot1: PropValue;
  iccid_slot2: PropValue;
  phone_number: PropValue;
  sim_operator: PropValue;
  sim_operator_name: PropValue;
  sim_country_iso: PropValue;
  // Device Identity
  brand: PropValue;
  model: PropValue;
  manufacturer: PropValue;
  device_name: PropValue;
  hardware: PropValue;
  fingerprint: PropValue;
  serial_number: PropValue;
  android_id: PropValue;
  os_version: PropValue;
  sdk_version: PropValue;
  build_id: PropValue;
  bootloader: PropValue;
  radio_version: PropValue;
  // Network
  mac_wifi: PropValue;
  mac_bluetooth: PropValue;
  wifi_ssid: PropValue;
  wifi_bssid: PropValue;
  // Geo
  latitude: PropValue;
  longitude: PropValue;
  altitude: PropValue;
  // Other
  gsf_id: PropValue;
  advertising_id: PropValue;
}

export interface PropValue {
  value: string;
  enabled: boolean;
}

export interface AgentStatus {
  version: string;
  uptime: number;
  port: number;
  deviceCount: number;
  devices: string[];
  license: LicenseInfo;
}

export interface LicenseInfo {
  valid: boolean;
  expiresAt: string;
  maxDevices: number;
  features: string[];
}

export type TaskType = "adb" | "backup" | "restore" | "reboot" | "shell" | "install" | "uninstall" | "push" | "pull" | "license_activate";

export type TaskStatus = "pending" | "running" | "completed" | "failed";

export interface Task {
  id: string;
  type: TaskType;
  deviceId?: string;
  params: Record<string, string>;
  status: TaskStatus;
  output: string;
  error?: string;
  createdAt: string;
  updatedAt: string;
}

export interface BackupInfo {
  id: string;
  deviceId: string;
  filename: string;
  size: number;
  props: DeviceProps;
  createdAt: string;
}

export interface DeviceMeta {
  serial: string;
  realSerial: string;
  imei1: string;
  imei2: string;
  meid: string;
  imsi1: string;
  imsi2: string;
  iccid1: string;
  iccid2: string;
  phoneNumber: string;
  simOperator: string;
  simCarrier: string;
  simCountry: string;
  brand: string;
  model: string;
  manufacturer: string;
  deviceName: string;
  productName: string;
  device: string;
  board: string;
  hardware: string;
  platform: string;
  fingerprint: string;
  buildId: string;
  buildType: string;
  buildTags: string;
  osVersion: string;
  sdkVersion: string;
  incremental: string;
  securityPatch: string;
  bootloader: string;
  radioBaseband: string;
  displayDensity: string;
  displayWidth: string;
  displayHeight: string;
  macWifi: string;
  macBluetooth: string;
  wifiSsid: string;
  wifiBssid: string;
  ipAddress: string;
  androidId: string;
  gsfId: string;
  advertisingId: string;
  timezone: string;
  language: string;
  cpuAbi: string;
  totalRam: string;
  internalSize: string;
  rawProps: Record<string, string>;
  collectedAt: string;
  agentVer: string;
}
