// API client for manager-agent backend
// Uses localStorage "zmmo-endpoint" if set, otherwise Vite proxy /api

import type { AgentStatus, DeviceInfo, DeviceProps, Task, BackupInfo } from "@/types/device";

function getBaseUrl(): string {
  try {
    const ep = localStorage.getItem("zmmo-endpoint");
    if (ep) return ep.replace(/\/+$/, "");
  } catch {}
  return "/api";
}

export function getEndpoint(): string {
  return getBaseUrl();
}

export function setEndpoint(url: string) {
  localStorage.setItem("zmmo-endpoint", url);
}

async function apiCall<T>(path: string, options?: RequestInit): Promise<T> {
  const url = `${getBaseUrl()}${path}`;
  const res = await fetch(url, {
    ...options,
    headers: { "Content-Type": "application/json", ...options?.headers },
    signal: options?.signal ?? AbortSignal.timeout(15000),
  });
  if (!res.ok) {
    const err = await res.text().catch(() => "Unknown error");
    throw new Error(`API ${res.status}: ${err}`);
  }
  return res.json();
}

// ── Agent Status ──
export async function getAgentStatus(): Promise<AgentStatus> {
  return apiCall<AgentStatus>("/status");
}

// ── Devices ──
export async function getDevices(): Promise<DeviceInfo[]> {
  return apiCall<DeviceInfo[]>("/devices");
}

export async function getDevice(id: string): Promise<DeviceInfo> {
  return apiCall<DeviceInfo>(`/devices/${id}`);
}

export async function updateDeviceProps(id: string, props: Partial<DeviceProps>): Promise<{ ok: boolean }> {
  return apiCall(`/devices/${id}/props`, {
    method: "PUT",
    body: JSON.stringify({ props }),
  });
}

export async function applyDeviceProps(id: string): Promise<{ ok: boolean }> {
  return apiCall(`/devices/${id}/apply`, { method: "POST" });
}

// ── Tasks ──
export async function getTasks(): Promise<Task[]> {
  return apiCall<Task[]>("/tasks");
}

export async function createTask(type: Task["type"], deviceId?: string, params?: Record<string, string>): Promise<Task> {
  return apiCall<Task>("/tasks", {
    method: "POST",
    body: JSON.stringify({ type, deviceId, params: params ?? {} }),
  });
}

export async function getTask(id: string): Promise<Task> {
  return apiCall<Task>(`/tasks/${id}`);
}

// ── Backups ──
export async function getBackups(): Promise<BackupInfo[]> {
  return apiCall<BackupInfo[]>("/backups");
}

export async function createBackup(
  deviceId: string,
  props?: any,
  packages?: string[],
  targetDir?: string
): Promise<{ ok: boolean; backup: BackupInfo }> {
  return apiCall("/backups", {
    method: "POST",
    body: JSON.stringify({ deviceId, packages: packages ?? [], targetDir }),
  });
}

export async function restoreBackup(backupId: string, deviceId: string): Promise<{ ok: boolean }> {
  return apiCall(`/backups/${backupId}/restore`, {
    method: "POST",
    body: JSON.stringify({ deviceId }),
  });
}

// ── License ──
export async function activateLicense(key: string): Promise<{ ok: boolean; message: string }> {
  return apiCall("/license/activate", {
    method: "POST",
    body: JSON.stringify({ key }),
  });
}

// ── ADB Commands ──
export async function adbCommand(deviceId: string, command: string): Promise<{ output: string }> {
  return apiCall(`/adb/${deviceId}`, {
    method: "POST",
    body: JSON.stringify({ command }),
  });
}

// ── Device Meta ──
export async function getDeviceMeta(
  deviceId: string
): Promise<{ ok: boolean; found: boolean; path: string; meta?: import("@/types/device").DeviceMeta; message?: string }> {
  return apiCall(`/devices/${deviceId}/meta`);
}

export async function refreshDeviceMeta(
  deviceId: string
): Promise<{ ok: boolean; path: string; meta: import("@/types/device").DeviceMeta }> {
  return apiCall(`/devices/${deviceId}/refresh-meta`, { method: "POST" });
}

// ── Packages ──
export interface PackageInfo {
  package: string;
  name: string;
}

export async function getPackages(deviceId: string): Promise<PackageInfo[]> {
  return apiCall<PackageInfo[]>(`/packages/${deviceId}`);
}
