#!/usr/bin/env node

import { existsSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import { pathToFileURL } from "node:url";

const USAGE = [
  "Usage:",
  "  node visual-diff.mjs --figma figma.png --local local.png --diff diff.png [options]",
  "",
  "Options:",
  "  --figma <path>             Figma golden PNG path.",
  "  --local <path>             Local screenshot PNG path.",
  "  --diff <path>              Output diff PNG path.",
  "  --project-root <path>      Dependency resolution root, default process.cwd().",
  "  --threshold <number>       pixelmatch threshold, default 0.1.",
  "  --max-diff-ratio <number>  Maximum allowed diff ratio, default 0.005.",
  "  --mask <x,y,w,h>           Ignore a rectangle. Repeat or pass comma groups.",
  "",
  "Mask examples:",
  "  --mask 0,0,24,24 --mask 320,0,55,20",
  "  --mask 0,0,24,24,320,0,55,20",
].join("\n");

class CliError extends Error {
  constructor(message, code = "CLI_ERROR", details = {}) {
    super(message);
    this.name = "CliError";
    this.code = code;
    this.details = details;
  }
}

function printJson(payload) {
  process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
}

function parseArgs(argv) {
  const args = {
    figma: undefined,
    local: undefined,
    diff: undefined,
    projectRoot: undefined,
    threshold: undefined,
    maxDiffRatio: undefined,
    maskValues: [],
    help: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];

    if (token === "--help" || token === "-h") {
      args.help = true;
      continue;
    }

    if (!token.startsWith("--")) {
      throw new CliError(`Unexpected positional argument: ${token}`, "UNEXPECTED_ARGUMENT", {
        usage: USAGE,
      });
    }

    const equalsIndex = token.indexOf("=");
    const name = equalsIndex === -1 ? token.slice(2) : token.slice(2, equalsIndex);
    let value = equalsIndex === -1 ? undefined : token.slice(equalsIndex + 1);

    if (value === undefined) {
      value = argv[i + 1];
      if (value === undefined || value.startsWith("--")) {
        throw new CliError(`Missing value for --${name}`, "MISSING_OPTION_VALUE", {
          option: name,
          usage: USAGE,
        });
      }
      i += 1;
    }

    switch (name) {
      case "figma":
        args.figma = value;
        break;
      case "local":
        args.local = value;
        break;
      case "diff":
        args.diff = value;
        break;
      case "project-root":
        args.projectRoot = value;
        break;
      case "threshold":
        args.threshold = value;
        break;
      case "max-diff-ratio":
        args.maxDiffRatio = value;
        break;
      case "mask":
        args.maskValues.push(value);
        break;
      default:
        throw new CliError(`Unknown option: --${name}`, "UNKNOWN_OPTION", {
          option: name,
          usage: USAGE,
        });
    }
  }

  return args;
}

function parseBoundedNumber(name, value, defaultValue, min, max) {
  if (value === undefined) {
    return defaultValue;
  }

  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < min || parsed > max) {
    throw new CliError(`${name} must be a number from ${min} to ${max}.`, "INVALID_NUMBER", {
      option: name,
      value,
    });
  }

  return parsed;
}

function parseInteger(name, value) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed)) {
    throw new CliError(`${name} must be an integer.`, "INVALID_MASK", {
      value,
    });
  }
  return parsed;
}

function parseMasks(maskValues) {
  const masks = [];

  for (const rawValue of maskValues) {
    const parts = rawValue.split(",").map((part) => part.trim());

    if (parts.some((part) => part.length === 0) || parts.length % 4 !== 0) {
      throw new CliError(
        "Mask must be x,y,w,h or repeated comma groups of x,y,w,h.",
        "INVALID_MASK",
        { value: rawValue },
      );
    }

    for (let i = 0; i < parts.length; i += 4) {
      const x = parseInteger("mask x", parts[i]);
      const y = parseInteger("mask y", parts[i + 1]);
      const w = parseInteger("mask w", parts[i + 2]);
      const h = parseInteger("mask h", parts[i + 3]);

      if (w <= 0 || h <= 0) {
        throw new CliError("Mask width and height must be greater than 0.", "INVALID_MASK", {
          value: parts.slice(i, i + 4).join(","),
        });
      }

      masks.push({ x, y, w, h });
    }
  }

  return masks;
}

function normalizeOptions(parsed) {
  if (parsed.help) {
    return { help: true };
  }

  const missing = [];
  if (!parsed.figma) missing.push("--figma");
  if (!parsed.local) missing.push("--local");
  if (!parsed.diff) missing.push("--diff");

  if (missing.length > 0) {
    throw new CliError(`Missing required options: ${missing.join(", ")}`, "MISSING_REQUIRED_OPTIONS", {
      missing,
      usage: USAGE,
    });
  }

  const figmaPath = path.resolve(parsed.figma);
  const localPath = path.resolve(parsed.local);
  const diffPath = path.resolve(parsed.diff);

  if (diffPath === figmaPath || diffPath === localPath) {
    throw new CliError("--diff must not overwrite --figma or --local.", "UNSAFE_DIFF_PATH", {
      figma: figmaPath,
      local: localPath,
      diff: diffPath,
    });
  }

  return {
    figmaPath,
    localPath,
    diffPath,
    projectRoot: path.resolve(parsed.projectRoot ?? process.cwd()),
    threshold: parseBoundedNumber("--threshold", parsed.threshold, 0.1, 0, 1),
    maxDiffRatio: parseBoundedNumber("--max-diff-ratio", parsed.maxDiffRatio, 0.005, 0, 1),
    masks: parseMasks(parsed.maskValues),
  };
}

function isMissingPackageError(error, packageName) {
  return (
    error &&
    (error.code === "ERR_MODULE_NOT_FOUND" || error.code === "MODULE_NOT_FOUND") &&
    typeof error.message === "string" &&
    error.message.includes(packageName)
  );
}

function installCommand(projectRoot) {
  try {
    const packageJson = JSON.parse(readFileSync(path.join(projectRoot, "package.json"), "utf8"));
    const manager = String(packageJson.packageManager ?? "").split("@", 1)[0];
    if (manager === "pnpm") return "pnpm add -D pixelmatch pngjs";
    if (manager === "yarn") return "yarn add -D pixelmatch pngjs";
    if (manager === "bun") return "bun add -d pixelmatch pngjs";
    if (manager === "npm") return "npm install -D pixelmatch pngjs";
  } catch {}

  if (existsSync(path.join(projectRoot, "pnpm-lock.yaml"))) {
    return "pnpm add -D pixelmatch pngjs";
  }

  if (existsSync(path.join(projectRoot, "yarn.lock"))) {
    return "yarn add -D pixelmatch pngjs";
  }

  if (existsSync(path.join(projectRoot, "bun.lock"))) {
    return "bun add -d pixelmatch pngjs";
  }

  if (existsSync(path.join(projectRoot, "bun.lockb"))) {
    return "bun add -d pixelmatch pngjs";
  }

  return "npm install -D pixelmatch pngjs";
}

async function importFromProject(projectRoot, packageName) {
  const requireFromProject = createRequire(path.join(projectRoot, "package.json"));
  try {
    const resolved = requireFromProject.resolve(packageName);
    const resolvedReal = realpathSync(resolved);
    const expectedPrefix = realpathSync(path.join(projectRoot, "node_modules")) + path.sep;
    if (!resolvedReal.startsWith(expectedPrefix)) {
      throw Object.assign(
        new Error(`Dependency ${packageName} resolved outside --project-root: ${resolvedReal}`),
        { code: "MODULE_NOT_FOUND" },
      );
    }
    return await import(pathToFileURL(resolvedReal).href);
  } catch (error) {
    throw error;
  }
}

async function loadDependencies(projectRoot) {
  const dependencyNames = ["pixelmatch", "pngjs"];
  const results = await Promise.allSettled(
    dependencyNames.map((name) => importFromProject(projectRoot, name)),
  );
  const missing = [];
  const command = installCommand(projectRoot);

  for (let i = 0; i < results.length; i += 1) {
    const result = results[i];
    if (result.status === "rejected" && isMissingPackageError(result.reason, dependencyNames[i])) {
      missing.push(dependencyNames[i]);
    }
  }

  if (missing.length > 0) {
    throw new CliError(
      `Missing dependencies: ${missing.join(", ")}. Install with: ${command}`,
      "MISSING_DEPENDENCIES",
      {
        missing,
        projectRoot,
        installCommand: command,
      },
    );
  }

  for (let i = 0; i < results.length; i += 1) {
    const result = results[i];
    if (result.status === "rejected") {
      throw result.reason;
    }
  }

  const pixelmatchModule = results[0].value;
  const pngjsModule = results[1].value;
  const pixelmatch = pixelmatchModule.default ?? pixelmatchModule.pixelmatch ?? pixelmatchModule;
  const PNG = pngjsModule.PNG ?? pngjsModule.default?.PNG;

  if (typeof pixelmatch !== "function") {
    throw new CliError("Dependency pixelmatch did not export a function.", "INVALID_DEPENDENCY");
  }

  if (!PNG || !PNG.sync || typeof PNG.sync.read !== "function" || typeof PNG.sync.write !== "function") {
    throw new CliError("Dependency pngjs did not export PNG.sync read/write.", "INVALID_DEPENDENCY");
  }

  return { pixelmatch, PNG };
}

function readPng(PNG, filePath, label) {
  try {
    return PNG.sync.read(readFileSync(filePath));
  } catch (error) {
    throw new CliError(`Failed to read ${label} PNG: ${error.message}`, "READ_PNG_FAILED", {
      label,
      path: filePath,
    });
  }
}

function copyIntoCanvas(image, width, height) {
  const canvas = Buffer.alloc(width * height * 4, 0);

  for (let y = 0; y < image.height; y += 1) {
    const sourceStart = y * image.width * 4;
    const sourceEnd = sourceStart + image.width * 4;
    const targetStart = y * width * 4;
    image.data.copy(canvas, targetStart, sourceStart, sourceEnd);
  }

  return canvas;
}

function buildMaskBitmap(masks, width, height) {
  const bitmap = new Uint8Array(width * height);
  const effectiveMasks = [];
  let maskPixels = 0;

  for (const mask of masks) {
    const x0 = Math.max(0, mask.x);
    const y0 = Math.max(0, mask.y);
    const x1 = Math.min(width, mask.x + mask.w);
    const y1 = Math.min(height, mask.y + mask.h);

    if (x1 <= x0 || y1 <= y0) {
      continue;
    }

    effectiveMasks.push({ x: x0, y: y0, w: x1 - x0, h: y1 - y0 });

    for (let y = y0; y < y1; y += 1) {
      const rowOffset = y * width;
      for (let x = x0; x < x1; x += 1) {
        const index = rowOffset + x;
        if (bitmap[index] === 0) {
          bitmap[index] = 1;
          maskPixels += 1;
        }
      }
    }
  }

  return { bitmap, effectiveMasks, maskPixels };
}

function applyMask(figmaData, localData, bitmap) {
  for (let pixelIndex = 0; pixelIndex < bitmap.length; pixelIndex += 1) {
    if (bitmap[pixelIndex] === 0) {
      continue;
    }

    const byteIndex = pixelIndex * 4;
    localData[byteIndex] = figmaData[byteIndex];
    localData[byteIndex + 1] = figmaData[byteIndex + 1];
    localData[byteIndex + 2] = figmaData[byteIndex + 2];
    localData[byteIndex + 3] = figmaData[byteIndex + 3];
  }
}

function writeDiff(PNG, diffPath, diffImage) {
  try {
    mkdirSync(path.dirname(diffPath), { recursive: true });
    writeFileSync(diffPath, PNG.sync.write(diffImage));
  } catch (error) {
    throw new CliError(`Failed to write diff PNG: ${error.message}`, "WRITE_DIFF_FAILED", {
      path: diffPath,
    });
  }
}

async function run() {
  const parsed = parseArgs(process.argv.slice(2));
  const options = normalizeOptions(parsed);

  if (options.help) {
    printJson({
      ok: true,
      usage: USAGE,
      defaults: {
        threshold: 0.1,
        maxDiffRatio: 0.005,
      },
    });
    return 0;
  }

  const { pixelmatch, PNG } = await loadDependencies(options.projectRoot);
  const figmaImage = readPng(PNG, options.figmaPath, "figma");
  const localImage = readPng(PNG, options.localPath, "local");
  const width = Math.max(figmaImage.width, localImage.width);
  const height = Math.max(figmaImage.height, localImage.height);
  const figmaData = copyIntoCanvas(figmaImage, width, height);
  const localData = copyIntoCanvas(localImage, width, height);
  const { bitmap, effectiveMasks, maskPixels } = buildMaskBitmap(options.masks, width, height);

  applyMask(figmaData, localData, bitmap);

  const diffImage = new PNG({ width, height });
  const diffPixels = pixelmatch(figmaData, localData, diffImage.data, width, height, {
    threshold: options.threshold,
  });

  writeDiff(PNG, options.diffPath, diffImage);

  const totalPixels = width * height;
  const comparedPixels = totalPixels - maskPixels;
  const diffRatio = comparedPixels === 0 ? 0 : diffPixels / comparedPixels;
  const dimensionMismatch = figmaImage.width !== localImage.width || figmaImage.height !== localImage.height;
  const failures = [];
  const warnings = [];

  if (dimensionMismatch) {
    failures.push({
      code: "DIMENSION_MISMATCH",
      message: "Figma and local PNG dimensions must match.",
    });
  }

  if (diffRatio > options.maxDiffRatio) {
    failures.push({
      code: "DIFF_RATIO_EXCEEDED",
      message: `Diff ratio ${diffRatio} exceeds max ${options.maxDiffRatio}.`,
    });
  }

  if (comparedPixels === 0) {
    warnings.push("All pixels are masked; diffRatio is reported as 0.");
  }

  const ok = failures.length === 0;

  const result = {
    ok,
    engine: "pixelmatch",
    figma: options.figmaPath,
    local: options.localPath,
    diff: options.diffPath,
    projectRoot: options.projectRoot,
    threshold: options.threshold,
    maxDiffRatio: options.maxDiffRatio,
    dimensions: {
      width,
      height,
      figma: {
        width: figmaImage.width,
        height: figmaImage.height,
      },
      local: {
        width: localImage.width,
        height: localImage.height,
      },
      mismatch: dimensionMismatch,
    },
    pixels: {
      total: totalPixels,
      masked: maskPixels,
      compared: comparedPixels,
      diff: diffPixels,
    },
    diffRatio,
    masks: {
      requested: options.masks,
      effective: effectiveMasks,
    },
  };

  if (!ok) {
    result.failure = {
      code: failures.length === 1 ? failures[0].code : "VISUAL_DIFF_FAILED",
      message: failures.length === 1 ? failures[0].message : "Multiple visual diff checks failed.",
      checks: failures,
    };
  }

  if (warnings.length > 0) {
    result.warnings = warnings;
  }

  printJson(result);
  return ok ? 0 : 1;
}

run()
  .then((exitCode) => {
    process.exitCode = exitCode;
  })
  .catch((error) => {
    const payload = {
      ok: false,
      error: {
        code: error.code ?? "VISUAL_DIFF_ERROR",
        message: error.message,
      },
    };

    if (error.details) {
      payload.error.details = error.details;
    }

    if (process.env.VISUAL_DIFF_DEBUG === "1" && error.stack) {
      payload.error.stack = error.stack;
    }

    printJson(payload);
    process.exitCode = 1;
  });
