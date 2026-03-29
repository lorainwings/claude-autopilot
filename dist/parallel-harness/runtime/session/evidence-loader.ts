import { readFileSync, existsSync, statSync } from "fs";
import { join, relative } from "path";

export interface FileInfo {
  path: string;
  content: string;
  size: number;
  last_modified: string;
}

export interface TaskNode {
  id: string;
  allowed_paths: string[];
  dependencies: string[];
}

export interface EvidenceLoaderConfig {
  project_root: string;
  max_files_per_task: number;
  max_file_size_kb: number;
}

const DEFAULT_CONFIG: EvidenceLoaderConfig = {
  project_root: process.cwd(),
  max_files_per_task: 50,
  max_file_size_kb: 500,
};

export function loadEvidenceFiles(
  task: TaskNode,
  config: Partial<EvidenceLoaderConfig> = {}
): FileInfo[] {
  const cfg = { ...DEFAULT_CONFIG, ...config };
  const files: FileInfo[] = [];

  const pathsToLoad = [
    ...task.allowed_paths,
    ...task.dependencies.map((d: string) => `**/${d}/**`),
  ];

  for (const pattern of pathsToLoad.slice(0, cfg.max_files_per_task)) {
    try {
      const fullPath = join(cfg.project_root, pattern);
      if (!existsSync(fullPath)) continue;

      const stat = statSync(fullPath);
      if (stat.isDirectory() || stat.size > cfg.max_file_size_kb * 1024) continue;

      try {
        const content = readFileSync(fullPath, "utf-8");
        files.push({
          path: relative(cfg.project_root, fullPath),
          content,
          size: stat.size,
          last_modified: stat.mtime.toISOString(),
        });
      } catch {
        continue;
      }

      if (files.length >= cfg.max_files_per_task) break;
    } catch {
      continue;
    }
  }

  return files;
}
