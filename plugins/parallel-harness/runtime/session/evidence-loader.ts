import { readFileSync, existsSync, statSync, readdirSync } from "fs";
import { join, relative } from "path";
import { normalizePath, type NormalizedPath } from "../schemas/ga-schemas";

export interface FileInfo {
  path: string;
  content: string;
  size: number;
  last_modified: string;
}

export interface EvidenceLoaderTask {
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

/**
 * 加载任务相关的证据文件。
 * 支持：精确文件路径、目录（递归扫描）、glob 模式、"." 项目根目录。
 */
export function loadEvidenceFiles(
  task: EvidenceLoaderTask,
  config: Partial<EvidenceLoaderConfig> = {}
): FileInfo[] {
  const cfg = { ...DEFAULT_CONFIG, ...config };
  const files: FileInfo[] = [];
  const seen = new Set<string>();

  // 归一化路径：支持绝对路径、相对路径、"." 场景
  const normalizedPaths = task.allowed_paths.map(p => normalizePath(p, cfg.project_root));

  for (const np of normalizedPaths) {
    if (files.length >= cfg.max_files_per_task) break;

    // repo_root — 扫描根目录下的顶层文件
    if (np.kind === "repo_root") {
      collectFromDirectory(np.repo_absolute, cfg, files, seen, 1);
      continue;
    }

    // glob 模式 — 使用 Bun.Glob
    if (np.kind === "glob") {
      try {
        const glob = new Bun.Glob(np.repo_relative);
        for (const match of glob.scanSync({ cwd: cfg.project_root, absolute: false })) {
          if (files.length >= cfg.max_files_per_task) break;
          collectFile(join(cfg.project_root, match), cfg, files, seen);
        }
      } catch {
        // glob 失败，跳过
      }
      continue;
    }

    // 使用归一化后的绝对路径
    const fullPath = np.repo_absolute;
    if (!existsSync(fullPath)) continue;

    const stat = statSync(fullPath);
    if (stat.isDirectory()) {
      collectFromDirectory(fullPath, cfg, files, seen, 3);
    } else {
      collectFile(fullPath, cfg, files, seen);
    }
  }

  // P0-1: 若 allowed_paths 非空但未选出文件，标记 context_blocked
  if (task.allowed_paths.length > 0 && files.length === 0) {
    console.warn(`[EvidenceLoader] context_blocked: allowed_paths=${JSON.stringify(task.allowed_paths)} 但未选出任何文件`);
  }

  return files;
}

function collectFile(
  fullPath: string,
  cfg: EvidenceLoaderConfig,
  files: FileInfo[],
  seen: Set<string>
): void {
  if (files.length >= cfg.max_files_per_task) return;

  const relPath = relative(cfg.project_root, fullPath);
  if (seen.has(relPath)) return;

  try {
    if (!existsSync(fullPath)) return;
    const stat = statSync(fullPath);
    if (stat.isDirectory()) return;
    if (stat.size > cfg.max_file_size_kb * 1024) return;

    const content = readFileSync(fullPath, "utf-8");
    seen.add(relPath);
    files.push({
      path: relPath,
      content,
      size: stat.size,
      last_modified: stat.mtime.toISOString(),
    });
  } catch {
    // 文件不可读，跳过
  }
}

function collectFromDirectory(
  dirPath: string,
  cfg: EvidenceLoaderConfig,
  files: FileInfo[],
  seen: Set<string>,
  maxDepth: number,
  currentDepth: number = 0
): void {
  if (currentDepth >= maxDepth || files.length >= cfg.max_files_per_task) return;

  try {
    const entries = readdirSync(dirPath, { withFileTypes: true });
    for (const entry of entries) {
      if (files.length >= cfg.max_files_per_task) break;
      if (entry.name.startsWith(".") || entry.name === "node_modules") continue;

      const entryPath = join(dirPath, entry.name);
      if (entry.isFile()) {
        collectFile(entryPath, cfg, files, seen);
      } else if (entry.isDirectory()) {
        collectFromDirectory(entryPath, cfg, files, seen, maxDepth, currentDepth + 1);
      }
    }
  } catch {
    // 目录不可读，跳过
  }
}
