// ɳClaw Desktop — ModelPicker component (T01, T06)
//
// Searches HuggingFace for GGUF models and lets the user select + download one.
// Triggers llm_swap_model after download completes.

import React, { useCallback, useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import type { HfModel, HfGgufFile } from "@/types/llm";
import { useDownloadQueue } from "@/hooks/useDownloadQueue";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Label } from "@/components/ui/label";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function formatBytes(bytes: number | null): string {
  if (bytes === null) return "unknown size";
  const gb = bytes / (1024 ** 3);
  if (gb >= 1) return `${gb.toFixed(1)} GB`;
  const mb = bytes / (1024 ** 2);
  return `${Math.round(mb)} MB`;
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

interface ModelPickerProps {
  /** Called when a model is successfully loaded (post-swap). */
  onModelLoaded?: (modelName: string) => void;
}

export function ModelPicker({ onModelLoaded }: ModelPickerProps) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<HfModel[]>([]);
  const [searching, setSearching] = useState(false);
  const [searchError, setSearchError] = useState<string | null>(null);

  // Selected model + file.
  const [selectedModel, setSelectedModel] = useState<HfModel | null>(null);
  const [selectedFile, setSelectedFile] = useState<HfGgufFile | null>(null);

  // Swap state.
  const [swapping, setSwapping] = useState(false);
  const [swapError, setSwapError] = useState<string | null>(null);

  const { startDownload, queue } = useDownloadQueue();
  const swapUnlistenRef = useRef<UnlistenFn | null>(null);

  // Subscribe to swap events.
  useEffect(() => {
    let mounted = true;

    Promise.all([
      listen<string>("llm://swap-done", (e) => {
        if (!mounted) return;
        setSwapping(false);
        onModelLoaded?.(e.payload);
      }),
      listen<string>("llm://swap-error", (e) => {
        if (!mounted) return;
        setSwapping(false);
        setSwapError(e.payload);
      }),
    ]).then(([u1, u2]) => {
      if (!mounted) {
        u1();
        u2();
      } else {
        swapUnlistenRef.current = () => { u1(); u2(); };
      }
    });

    return () => {
      mounted = false;
      swapUnlistenRef.current?.();
    };
  }, [onModelLoaded]);

  const handleSearch = useCallback(async () => {
    if (!query.trim()) return;
    setSearching(true);
    setSearchError(null);
    try {
      const models = await invoke<HfModel[]>("llm_search_hf", {
        query: query.trim(),
        limit: 20,
      });
      setResults(models);
      setSelectedModel(null);
      setSelectedFile(null);
    } catch (e) {
      setSearchError(String(e));
    } finally {
      setSearching(false);
    }
  }, [query]);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter") handleSearch();
  };

  const handleSelectModel = (model: HfModel) => {
    setSelectedModel(model);
    // Auto-select first Q4_K_M file, or first file.
    const preferred = model.gguf_files.find((f) => f.quant === "Q4_K_M");
    setSelectedFile(preferred ?? model.gguf_files[0] ?? null);
    setSwapError(null);
  };

  const handleDownloadAndSwap = useCallback(async () => {
    if (!selectedModel || !selectedFile) return;
    setSwapError(null);

    // Construct the download URL from the HF model ID and filename.
    const url = `https://huggingface.co/${selectedModel.id}/resolve/main/${selectedFile.filename}`;

    try {
      const downloadId = await startDownload(url, selectedFile.filename);

      // Watch for completion of this specific download, then swap.
      const watchId = downloadId;
      const unlistenProgress = await listen<import("@/types/llm").DownloadProgress>(
        "llm://download-progress",
        async (event) => {
          if (event.payload.id !== watchId) return;
          if (event.payload.status === "done") {
            unlistenProgress();
            // File is in the models_dir — construct the path and swap.
            const modelsDir = await invoke<string>("llm_get_models_dir").catch(() => "");
            if (!modelsDir) {
              setSwapError("Could not determine models directory");
              return;
            }
            setSwapping(true);
            invoke("llm_swap_model", {
              path: `${modelsDir}/${selectedFile.filename}`,
            }).catch((e) => {
              setSwapping(false);
              setSwapError(String(e));
            });
          } else if (
            typeof event.payload.status === "object" &&
            "failed" in event.payload.status
          ) {
            unlistenProgress();
            setSwapError((event.payload.status as { failed: string }).failed);
          }
        }
      );
    } catch (e) {
      setSwapError(String(e));
    }
  }, [selectedModel, selectedFile, startDownload]);

  // Check if there's an active download for the selected file.
  const activeDownload = selectedFile
    ? queue.find(
        (d) =>
          d.filename === selectedFile.filename &&
          (d.status === "downloading" || d.status === "queued" || d.status === "verifying")
      )
    : null;

  return (
    <div className="space-y-4">
      {/* Search bar */}
      <div className="flex gap-2">
        <Input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="Search HuggingFace GGUF models…"
          aria-label="Model search query"
          data-testid="model-search-input"
          className="flex-1"
        />
        <Button
          onClick={handleSearch}
          disabled={searching || !query.trim()}
          aria-label="Search HuggingFace"
          data-testid="model-search-button"
        >
          {searching ? "Searching…" : "Search"}
        </Button>
      </div>

      {searchError && (
        <p role="alert" className="text-sm text-red-400">
          {searchError}
        </p>
      )}

      {/* Results list */}
      {results.length > 0 && (
        <ul
          className="max-h-64 overflow-y-auto rounded border border-slate-700 divide-y divide-slate-700"
          role="listbox"
          aria-label="Search results"
        >
          {results.map((model) => (
            <li
              key={model.id}
              role="option"
              aria-selected={selectedModel?.id === model.id}
              data-testid={`model-result-${model.id.replace(/\//g, "-")}`}
              className={`px-3 py-2 cursor-pointer text-sm hover:bg-slate-800 ${
                selectedModel?.id === model.id
                  ? "bg-slate-800 border-l-2 border-sky-500"
                  : ""
              }`}
              onClick={() => handleSelectModel(model)}
            >
              <div className="font-medium text-slate-100">{model.name}</div>
              <div className="text-xs text-slate-400">
                {model.downloads.toLocaleString()} downloads ·{" "}
                {model.gguf_files.length} GGUF file
                {model.gguf_files.length !== 1 ? "s" : ""}
              </div>
            </li>
          ))}
        </ul>
      )}

      {/* File selection */}
      {selectedModel && selectedModel.gguf_files.length > 0 && (
        <div className="space-y-2">
          <Label htmlFor="gguf-file-select" className="text-sm text-slate-300">
            GGUF file
          </Label>
          <Select
            value={selectedFile?.filename ?? ""}
            onValueChange={(v) => {
              const file = selectedModel.gguf_files.find((f) => f.filename === v);
              setSelectedFile(file ?? null);
            }}
          >
            <SelectTrigger id="gguf-file-select" aria-label="Select GGUF file">
              <SelectValue placeholder="Select a file…" />
            </SelectTrigger>
            <SelectContent>
              {selectedModel.gguf_files.map((file) => (
                <SelectItem key={file.filename} value={file.filename}>
                  {file.filename}
                  {file.quant ? ` (${file.quant})` : ""}
                  {` — ${formatBytes(file.size_bytes)}`}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      )}

      {/* Download + swap button */}
      {selectedFile && (
        <Button
          onClick={handleDownloadAndSwap}
          disabled={!!activeDownload || swapping}
          aria-label={
            swapping
              ? "Loading model…"
              : activeDownload
              ? "Downloading…"
              : `Download and load ${selectedFile.filename}`
          }
          data-testid="model-download-button"
          className="w-full"
        >
          {swapping
            ? "Loading model…"
            : activeDownload
            ? "Downloading…"
            : `Download & Load`}
        </Button>
      )}

      {swapError && (
        <p role="alert" className="text-sm text-red-400">
          {swapError}
        </p>
      )}
    </div>
  );
}
