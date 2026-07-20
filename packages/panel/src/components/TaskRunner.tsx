"use client";

import { useState } from "react";
import { createTask, adbCommand } from "@/lib/api";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { toast } from "sonner";

interface TaskRunnerProps {
  selectedDevice: string | null;
}

const QUICK_ACTIONS = [
  { icon: "🔌", label: "ADB Devices", cmd: "devices" },
  { icon: "📦", label: "Install APK", cmd: "install /path/to/app.apk" },
  { icon: "🔄", label: "Reboot", cmd: "reboot" },
  { icon: "💾", label: "Backup Props", cmd: "" },
  { icon: "🔑", label: "Activate License", cmd: "" },
];

export function TaskRunner({ selectedDevice }: TaskRunnerProps) {
  const [adbInput, setAdbInput] = useState("");
  const [running, setRunning] = useState(false);
  const [output, setOutput] = useState("");

  const runAdb = async (cmd: string) => {
    if (!selectedDevice) {
      toast.error("Select a device first");
      return;
    }
    const command = cmd || adbInput;
    if (!command) return;

    setRunning(true);
    setOutput("");
    try {
      const result = await adbCommand(selectedDevice, command);
      setOutput(result.output);
      toast.success("Command executed");
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : "Failed";
      setOutput(msg);
      toast.error(msg);
    } finally {
      setRunning(false);
    }
  };

  const handleBackup = async () => {
    if (!selectedDevice) return;
    try {
      await createTask("backup", selectedDevice);
      toast.success("Backup task created");
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : "Backup failed");
    }
  };

  const handleRestore = async () => {
    if (!selectedDevice) return;
    try {
      await createTask("restore", selectedDevice);
      toast.success("Restore task created");
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : "Restore failed");
    }
  };

  const handleLicense = async () => {
    const key = prompt("Enter license key:");
    if (!key) return;
    try {
      await createTask("license_activate", undefined, { key });
      toast.success("License activation submitted");
    } catch (e: unknown) {
      toast.error(e instanceof Error ? e.message : "Activation failed");
    }
  };

  return (
    <Card className="bg-zinc-900 border-zinc-800">
      <div className="p-3 border-b border-zinc-800">
        <h3 className="text-xs font-medium text-zinc-300 uppercase tracking-wider">
          Task Runner
        </h3>
        <p className="text-[10px] text-zinc-500 mt-0.5">
          Execute ADB commands and device tasks
        </p>
      </div>

      {/* Quick actions */}
      <div className="p-3 grid grid-cols-2 sm:grid-cols-3 md:grid-cols-5 gap-2">
        <button
          onClick={() => runAdb("devices")}
          disabled={running || !selectedDevice}
          className="flex flex-col items-center gap-1 p-2 rounded-lg bg-zinc-800/50 hover:bg-zinc-800 border border-zinc-700/50 disabled:opacity-40 transition-colors"
        >
          <span className="text-lg">🔌</span>
          <span className="text-[9px] text-zinc-400">ADB Devices</span>
        </button>
        <button
          disabled={running || !selectedDevice}
          className="flex flex-col items-center gap-1 p-2 rounded-lg bg-zinc-800/50 hover:bg-zinc-800 border border-zinc-700/50 disabled:opacity-40 transition-colors"
        >
          <span className="text-lg">🔄</span>
          <span className="text-[9px] text-zinc-400">Reboot</span>
        </button>
        <button
          onClick={handleBackup}
          disabled={running || !selectedDevice}
          className="flex flex-col items-center gap-1 p-2 rounded-lg bg-zinc-800/50 hover:bg-zinc-800 border border-zinc-700/50 disabled:opacity-40 transition-colors"
        >
          <span className="text-lg">💾</span>
          <span className="text-[9px] text-zinc-400">Backup</span>
        </button>
        <button
          onClick={handleRestore}
          disabled={running || !selectedDevice}
          className="flex flex-col items-center gap-1 p-2 rounded-lg bg-zinc-800/50 hover:bg-zinc-800 border border-zinc-700/50 disabled:opacity-40 transition-colors"
        >
          <span className="text-lg">📥</span>
          <span className="text-[9px] text-zinc-400">Restore</span>
        </button>
        <button
          onClick={handleLicense}
          disabled={running}
          className="flex flex-col items-center gap-1 p-2 rounded-lg bg-zinc-800/50 hover:bg-zinc-800 border border-zinc-700/50 disabled:opacity-40 transition-colors"
        >
          <span className="text-lg">🔑</span>
          <span className="text-[9px] text-zinc-400">License</span>
        </button>
      </div>

      {/* ADB shell */}
      <div className="px-3 pb-3">
        <div className="flex gap-2">
          <Input
            value={adbInput}
            onChange={(e) => setAdbInput(e.target.value)}
            placeholder="adb shell command..."
            className="h-7 text-[11px] bg-zinc-800 border-zinc-700 font-mono"
            onKeyDown={(e) => e.key === "Enter" && runAdb(adbInput)}
          />
          <Button
            size="sm"
            onClick={() => runAdb(adbInput)}
            disabled={running || !adbInput.trim() || !selectedDevice}
            className="h-7 text-[11px] bg-zinc-700 hover:bg-zinc-600 flex-shrink-0"
          >
            {running ? "..." : "Run"}
          </Button>
        </div>

        {/* Output */}
        {output && (
          <div className="mt-2 p-2 rounded bg-zinc-950 border border-zinc-800 max-h-32 overflow-y-auto">
            <pre className="text-[10px] text-emerald-400 font-mono whitespace-pre-wrap break-all">
              {output}
            </pre>
          </div>
        )}

        {!selectedDevice && (
          <p className="text-[10px] text-amber-500 mt-2">
            ⚠️ Select a device to run tasks
          </p>
        )}
      </div>
    </Card>
  );
}
