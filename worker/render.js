// Renders a job to its final output.
//   node render.js --job <dir>
//
// Remotion only ever renders the graphics layer. Modes:
//   separate     -> output/graphics.mov (ProRes 4444 with alpha), final result
//   video-top    -> graphics panel + ffmpeg vstack, source on top -> output/final.mp4
//   video-bottom -> same, source on the bottom
import {bundle} from '@remotion/bundler';
import {renderMedia, selectComposition} from '@remotion/renderer';
import {spawn} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {arg, emit, fail, ffmpegPath, jobPaths, webpackOverride, workerDir} from './lib.js';

// Anchor cwd to the worker so Remotion finds node_modules/.remotion for the
// headless browser, even when the app is launched from Finder (cwd "/").
process.chdir(workerDir);

const jobDir = arg('job');
if (!jobDir) fail('usage: render.js --job <dir>');
const paths = jobPaths(jobDir);
const meta = JSON.parse(fs.readFileSync(paths.metaFile, 'utf8'));
const stacked = meta.mode === 'video-top' || meta.mode === 'video-bottom';

emit({type: 'stage', stage: 'bundling'});
const serveUrl = await bundle({entryPoint: paths.entryPoint, webpackOverride});

const composition = await selectComposition({
  serveUrl,
  id: 'Main',
  inputProps: {meta},
  logLevel: 'error',
});

fs.mkdirSync(paths.outputDir, {recursive: true});
const graphicsFile = path.join(paths.outputDir, stacked ? 'graphics.mp4' : 'graphics.mov');

emit({type: 'stage', stage: 'rendering'});
let lastPercent = -1;
await renderMedia({
  composition,
  serveUrl,
  outputLocation: graphicsFile,
  inputProps: {meta},
  logLevel: 'error',
  ...(stacked
    ? {codec: 'h264', crf: 18}
    : {
        codec: 'prores',
        proResProfile: '4444',
        imageFormat: 'png',
        pixelFormat: 'yuva444p10le',
      }),
  onProgress: ({progress}) => {
    const percent = Math.floor(progress * 100);
    if (percent !== lastPercent) {
      lastPercent = percent;
      emit({type: 'progress', stage: 'rendering', percent});
    }
  },
});

if (!stacked) {
  emit({type: 'done', output: graphicsFile});
  process.exit(0);
}

emit({type: 'stage', stage: 'stitching'});
const sourceFile = path.join(jobDir, meta.sourceFileName);
const finalFile = path.join(paths.outputDir, 'final.mp4');
const videoOnTop = meta.mode === 'video-top';
const filter = [
  `[0:v]fps=${meta.fps},format=yuv420p[src]`,
  `[1:v]format=yuv420p[gfx]`,
  videoOnTop ? `[src][gfx]vstack=inputs=2[v]` : `[gfx][src]vstack=inputs=2[v]`,
].join(';');

// Stream ffmpeg's machine-readable progress so the user sees a real bar.
// out_time_us is the microseconds encoded so far; the total is the graphics
// duration (which equals the composition length).
await new Promise((resolve, reject) => {
  const child = spawn(ffmpegPath, [
    '-y',
    '-i', sourceFile,
    '-i', graphicsFile,
    '-filter_complex', filter,
    '-map', '[v]',
    '-map', '0:a?',
    '-c:v', 'libx264',
    '-preset', 'veryfast',
    '-crf', '18',
    '-c:a', 'aac',
    '-b:a', '192k',
    '-movflags', '+faststart',
    '-shortest',
    '-progress', 'pipe:1',
    '-nostats',
    finalFile,
  ]);

  let stderrTail = '';
  let lastPercent = -1;
  child.stdout.on('data', (chunk) => {
    for (const line of chunk.toString().split('\n')) {
      const match = line.match(/^out_time_us=(\d+)/);
      if (match) {
        const seconds = Number(match[1]) / 1e6;
        const percent = Math.min(100, Math.floor((seconds / meta.durationInSeconds) * 100));
        if (percent !== lastPercent) {
          lastPercent = percent;
          emit({type: 'progress', stage: 'stitching', percent});
        }
      }
    }
  });
  child.stderr.on('data', (chunk) => {
    stderrTail = (stderrTail + chunk.toString()).slice(-4000);
  });
  child.on('close', (code) => {
    if (code === 0) resolve();
    else reject(new Error(stderrTail.trim().split('\n').pop() || `exit ${code}`));
  });
});

emit({type: 'done', output: finalFile});
