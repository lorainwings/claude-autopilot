import { describe, test, expect } from "bun:test";
import { normalizePath, normalizePathList, type NormalizedPath } from "../../runtime/schemas/ga-schemas";

describe("NormalizedPath (P0-1)", () => {
  const repoRoot = "/tmp/test-repo";

  test("normalizes '.' to repo_root kind", () => {
    const np = normalizePath(".", repoRoot);
    expect(np.kind).toBe("repo_root");
    expect(np.repo_relative).toBe(".");
  });

  test("normalizes './' to repo_root kind", () => {
    const np = normalizePath("./", repoRoot);
    expect(np.kind).toBe("repo_root");
    expect(np.repo_relative).toBe(".");
  });

  test("normalizes absolute path to repo_relative", () => {
    const np = normalizePath("/tmp/test-repo/src/index.ts", repoRoot);
    expect(np.repo_relative).toBe("src/index.ts");
    expect(np.kind).toBe("file");
  });

  test("normalizes relative path preserving relativity", () => {
    const np = normalizePath("src/utils.ts", repoRoot);
    expect(np.repo_relative).toBe("src/utils.ts");
    expect(np.repo_absolute).toContain("src/utils.ts");
  });

  test("detects glob pattern", () => {
    const np = normalizePath("src/**/*.ts", repoRoot);
    expect(np.kind).toBe("glob");
    expect(np.repo_relative).toBe("src/**/*.ts");
  });

  test("detects absolute glob pattern", () => {
    const np = normalizePath("/tmp/test-repo/src/**/*.ts", repoRoot);
    expect(np.kind).toBe("glob");
    expect(np.repo_relative).toBe("src/**/*.ts");
  });

  test("normalizePathList handles mixed inputs", () => {
    const paths = [".", "src/index.ts", "/tmp/test-repo/lib/utils.ts", "tests/**/*.test.ts"];
    const results = normalizePathList(paths, repoRoot);
    expect(results).toHaveLength(4);
    expect(results[0].kind).toBe("repo_root");
    expect(results[1].kind).toBe("file");
    expect(results[2].repo_relative).toBe("lib/utils.ts");
    expect(results[3].kind).toBe("glob");
  });

  test("handles path outside repo root", () => {
    const np = normalizePath("/other/path/file.ts", repoRoot);
    expect(np.repo_relative).toContain("..");
  });

  test("handles empty path components gracefully", () => {
    const np = normalizePath("src//index.ts", repoRoot);
    expect(np.repo_relative).toBeDefined();
  });
});
