#!/usr/bin/env node
/**
 * video_to_nfp.js
 *
 * Convert a video into per-frame NFP (narrow frame palette) files suitable for
 * ComputerCraft rendering. Frames are quantized to the 16 CC colors and saved
 * as background-blit rows (compact text format).
 *
 * Prerequisites:
 *   - Node.js
 *   - ffmpeg in PATH
 *
 * Usage:
 *   node tools/video_to_nfp.js input.mp4 output_dir --width 26 --height 20 --fps 10 --slug demo
 *
 * Output:
 *   output_dir/
 *     manifest.json  (metadata + frame list)
 *     frames/frame_0001.nfp ... frame_N.nfp
 */

const fs = require("fs");
const path = require("path");
const { spawnSync, spawn } = require("child_process");

// Approximate CC palette (RGB) with corresponding blit hex digit
const CC_COLORS = [
  { name: "white", hex: "0", rgb: [240, 240, 240] },
  { name: "orange", hex: "1", rgb: [242, 178, 51] },
  { name: "magenta", hex: "2", rgb: [229, 127, 216] },
  { name: "lightBlue", hex: "3", rgb: [153, 178, 242] },
  { name: "yellow", hex: "4", rgb: [222, 222, 108] },
  { name: "lime", hex: "5", rgb: [127, 204, 25] },
  { name: "pink", hex: "6", rgb: [242, 178, 204] },
  { name: "gray", hex: "7", rgb: [76, 76, 76] },
  { name: "lightGray", hex: "8", rgb: [153, 153, 153] },
  { name: "cyan", hex: "9", rgb: [76, 153, 178] },
  { name: "purple", hex: "a", rgb: [178, 102, 229] },
  { name: "blue", hex: "b", rgb: [51, 76, 178] },
  { name: "brown", hex: "c", rgb: [102, 76, 51] },
  { name: "green", hex: "d", rgb: [102, 127, 51] },
  { name: "red", hex: "e", rgb: [153, 51, 51] },
  { name: "black", hex: "f", rgb: [0, 0, 0] },
];

function nearestColor(r, g, b) {
  let best = CC_COLORS[0];
  let bestDist = Infinity;
  for (const c of CC_COLORS) {
    const dr = r - c.rgb[0];
    const dg = g - c.rgb[1];
    const db = b - c.rgb[2];
    const dist = dr * dr + dg * dg + db * db;
    if (dist < bestDist) {
      bestDist = dist;
      best = c;
    }
  }
  return best.hex;
}

function ensureDir(dir) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function parseArgs() {
  const args = process.argv.slice(2);
  if (args.length < 2) return null;
  const input = args[0];
  const output = args[1];
  const opts = {
    width: 26,
    height: 20,
    fps: 10,
    slug: "video",
    start: null,
    duration: null,
  };
  for (let i = 2; i < args.length; i++) {
    const [k, v] = args[i].split("=");
    const key = k.replace(/^--/, "");
    switch (key) {
      case "width":
        opts.width = parseInt(v, 10);
        break;
      case "height":
        opts.height = parseInt(v, 10);
        break;
      case "fps":
        opts.fps = parseFloat(v);
        break;
      case "slug":
        opts.slug = v;
        break;
      case "start":
        opts.start = v;
        break;
      case "duration":
        opts.duration = v;
        break;
      default:
        break;
    }
  }
  if (!Number.isFinite(opts.width) || !Number.isFinite(opts.height) || !Number.isFinite(opts.fps)) {
    return null;
  }
  return { input, output, opts };
}

function assertFfmpeg() {
  const res = spawnSync("ffmpeg", ["-version"], { stdio: "ignore" });
  if (res.error) {
    console.error("ffmpeg not found in PATH. Please install ffmpeg.");
    process.exit(1);
  }
}

function spawnFfmpeg(input, opts) {
  const args = ["-hide_banner", "-loglevel", "error"];
  if (opts.start) args.push("-ss", opts.start);
  args.push("-i", input);
  if (opts.duration) args.push("-t", opts.duration);
  args.push(
    "-vf",
    `scale=${opts.width}:${opts.height}:flags=lanczos,fps=${opts.fps}`,
    "-an",
    "-vcodec",
    "rawvideo",
    "-pix_fmt",
    "rgb24",
    "-f",
    "rawvideo",
    "pipe:1"
  );
  const ff = spawn("ffmpeg", args, { stdio: ["ignore", "pipe", "inherit"] });
  return ff;
}

function processVideo(input, outputDir, opts) {
  assertFfmpeg();
  ensureDir(outputDir);
  const framesDir = path.join(outputDir, "frames");
  ensureDir(framesDir);

  const ff = spawnFfmpeg(input, opts);
  const frameSize = opts.width * opts.height * 3;
  let buffer = Buffer.alloc(0);
  let frameIndex = 0;

  ff.stdout.on("data", (chunk) => {
    buffer = Buffer.concat([buffer, chunk]);
    while (buffer.length >= frameSize) {
      const frameBuf = buffer.subarray(0, frameSize);
      buffer = buffer.subarray(frameSize);
      frameIndex += 1;
      const rows = [];
      for (let y = 0; y < opts.height; y++) {
        let row = "";
        for (let x = 0; x < opts.width; x++) {
          const idx = (y * opts.width + x) * 3;
          const r = frameBuf[idx];
          const g = frameBuf[idx + 1];
          const b = frameBuf[idx + 2];
          row += nearestColor(r, g, b);
        }
        rows.push(row);
      }
      const filename = `frame_${String(frameIndex).padStart(4, "0")}.nfp`;
      const outPath = path.join(framesDir, filename);
      const header = `${opts.width} ${opts.height}\n`;
      fs.writeFileSync(outPath, header + rows.join("\n"), "utf8");
      if (frameIndex % 25 === 0) {
        process.stdout.write(`Processed ${frameIndex} frames...\r`);
      }
    }
  });

  ff.on("close", (code) => {
    if (code !== 0) {
      console.error(`ffmpeg exited with code ${code}`);
      process.exit(code);
    }
    if (buffer.length > 0) {
      console.warn("Trailing bytes ignored; likely partial frame at end.");
    }
    const manifest = {
      format: "nfp-bg-rows-v1",
      width: opts.width,
      height: opts.height,
      fps: opts.fps,
      frameCount: frameIndex,
      slug: opts.slug,
      framesBasePath: "frames",
      frames: Array.from({ length: frameIndex }, (_, i) => `frame_${String(i + 1).padStart(4, "0")}.nfp`),
    };
    fs.writeFileSync(path.join(outputDir, "manifest.json"), JSON.stringify(manifest, null, 2));
    console.log(`\nDone. Frames: ${frameIndex}. Manifest: ${path.join(outputDir, "manifest.json")}`);
  });
}

function main() {
  const parsed = parseArgs();
  if (!parsed) {
    console.error(
      "Usage: node tools/video_to_nfp.js <input> <output_dir> --width=26 --height=20 --fps=10 --slug=demo [--start=00:00:00] [--duration=5]"
    );
    process.exit(1);
  }
  processVideo(parsed.input, parsed.output, parsed.opts);
}

main();
