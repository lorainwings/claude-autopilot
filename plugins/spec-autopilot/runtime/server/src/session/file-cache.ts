/**
 * file-cache.ts — 增量文件读取引擎（字节偏移游标驱动）
 *
 * 替代旧的全量 size+mtime 缓存模型。每个文件维护独立的字节偏移游标，
 * 文件增长时仅读取新增部分并追加到缓存。
 */

import { readFile, stat } from "node:fs/promises";
import { safeJsonParse } from "../utils";

/** 游标状态：已读取的字节偏移 + 缓存的解析结果 */
interface FileCursor<T> {
  byteOffset: number;
  fileSize: number;
  items: T[];
}

/** 全局游标存储 */
const cursorStore = new Map<string, FileCursor<unknown>>();

/** 获取文件大小，不存在返回 -1 */
async function getFileSize(filePath: string): Promise<number> {
  try {
    const info = await stat(filePath);
    return info.size;
  } catch {
    return -1;
  }
}

/**
 * 增量读取 JSONL 文件。
 * - 首次读取：全量读取并建立游标
 * - 后续读取：仅读取 byteOffset 之后的新增字节
 * - 文件缩小（truncate/replace）：重置游标并全量重读
 */
export async function readJsonLinesCached<T>(filePath: string): Promise<T[]> {
  const fileSize = await getFileSize(filePath);
  if (fileSize <= 0) return [];

  const existing = cursorStore.get(filePath) as FileCursor<T> | undefined;

  // 文件未变化 → 直接返回缓存
  if (existing && existing.fileSize === fileSize && existing.byteOffset >= fileSize) {
    return existing.items;
  }

  // 文件缩小（被替换或 truncate）→ 重置游标全量重读
  if (existing && fileSize < existing.fileSize) {
    cursorStore.delete(filePath);
    return readJsonLinesFull<T>(filePath, fileSize);
  }

  // 文件增长 → 增量读取
  if (existing && existing.byteOffset > 0 && existing.byteOffset <= fileSize) {
    return readJsonLinesIncremental<T>(filePath, existing, fileSize);
  }

  // 首次读取 → 全量
  return readJsonLinesFull<T>(filePath, fileSize);
}

/** 全量读取并建立游标 */
async function readJsonLinesFull<T>(filePath: string, fileSize: number): Promise<T[]> {
  try {
    const content = await readFile(filePath, "utf-8");
    const items = parseLines<T>(content);
    cursorStore.set(filePath, { byteOffset: fileSize, fileSize, items });
    return items;
  } catch {
    return [];
  }
}

/** 增量读取：从 byteOffset 读到文件末尾，仅解析新行 */
async function readJsonLinesIncremental<T>(
  filePath: string,
  cursor: FileCursor<T>,
  fileSize: number,
): Promise<T[]> {
  try {
    const file = Bun.file(filePath);
    const newBytes = await file.slice(cursor.byteOffset, fileSize).text();

    if (!newBytes) {
      cursor.fileSize = fileSize;
      return cursor.items;
    }

    // 处理跨行边界：只消费到最后一个完整换行
    const lastNewline = newBytes.lastIndexOf("\n");
    if (lastNewline < 0) {
      // 新增内容没有完整行（可能正在写入中），不推进游标
      cursor.fileSize = fileSize;
      return cursor.items;
    }

    const safeText = newBytes.slice(0, lastNewline + 1);
    const newItems = parseLines<T>(safeText);
    const allItems = [...cursor.items, ...newItems];
    const newOffset = cursor.byteOffset + Buffer.byteLength(safeText, "utf-8");

    cursorStore.set(filePath, {
      byteOffset: newOffset,
      fileSize,
      items: allItems,
    });

    return allItems;
  } catch {
    // 读取失败，回退到全量
    cursorStore.delete(filePath);
    return readJsonLinesFull<T>(filePath, fileSize);
  }
}

/** 解析文本为 JSONL 行 */
function parseLines<T>(content: string): T[] {
  return content
    .split("\n")
    .filter(Boolean)
    .map((line: string) => safeJsonParse<T>(line))
    .filter((item: T | null): item is T => item !== null);
}

/**
 * 重置指定文件的游标（用于 session 切换时清除旧缓存）。
 * 传入空参数则重置所有游标。
 */
export function resetFileCursors(filePaths?: string[]) {
  if (!filePaths) {
    cursorStore.clear();
    return;
  }
  for (const fp of filePaths) {
    cursorStore.delete(fp);
  }
}
