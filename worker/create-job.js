// Prepares a project folder for rendering. Safe to re-run: on a fresh
// project it copies the Remotion template and the source video; on reopen
// it preserves the agent's Graphics.tsx and the transcript, and only
// refreshes meta.json (dimensions and the chosen layout mode).
//   node create-job.js --source <video> --mode <mode> --job <projectDir>
// --source may be omitted when the project already holds a source file.
import {execFile} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {promisify} from 'node:util';
import {arg, emit, fail, ffprobePath, jobPaths, workerDir} from './lib.js';

const execFileAsync = promisify(execFile);

const source = arg('source');
const mode = arg('mode') ?? 'separate';
const jobDir = arg('job');

if (!jobDir) fail('usage: create-job.js --source <video> --mode <mode> --job <dir>');
if (!['separate', 'video-top', 'video-bottom'].includes(mode)) fail(`unknown mode: ${mode}`);

const SOURCE_RE = /^source\.(mp4|mov|webm|mkv|m4v)$/i;
const existingSource = fs.existsSync(jobDir)
  ? fs.readdirSync(jobDir).find((f) => SOURCE_RE.test(f))
  : undefined;

const probeTarget = source && fs.existsSync(source)
  ? source
  : existingSource
    ? path.join(jobDir, existingSource)
    : undefined;
if (!probeTarget) fail('no source video provided and none found in the project');

const probe = async (file) => {
  const {stdout} = await execFileAsync(ffprobePath, [
    '-v', 'error',
    '-select_streams', 'v:0',
    '-show_entries', 'stream=width,height,avg_frame_rate:format=duration',
    '-of', 'json',
    file,
  ]);
  const data = JSON.parse(stdout);
  const stream = data.streams?.[0];
  if (!stream) throw new Error('no video stream found');
  const [num, den] = stream.avg_frame_rate.split('/').map(Number);
  return {
    width: stream.width,
    height: stream.height,
    fps: Math.max(1, Math.round(num / (den || 1))),
    durationInSeconds: Number(data.format.duration),
  };
};

const info = await probe(probeTarget).catch((e) => fail(`could not read video: ${e.message}`));

const paths = jobPaths(jobDir);
fs.mkdirSync(paths.outputDir, {recursive: true});

// Copy the template only for a fresh project. On reopen this is skipped so
// the agent's Graphics.tsx and the transcript survive.
if (!fs.existsSync(paths.project)) {
  fs.cpSync(path.join(workerDir, 'template'), paths.project, {recursive: true});
}

// Bring in the source video only if the project does not already have one.
let sourceName = existingSource;
if (!sourceName) {
  const ext = path.extname(probeTarget) || '.mp4';
  sourceName = `source${ext}`;
  fs.copyFileSync(probeTarget, path.join(jobDir, sourceName));
}

const meta = {
  mode,
  width: info.width,
  height: info.height,
  fps: info.fps,
  durationInSeconds: info.durationInSeconds,
  sourceFileName: sourceName,
};
fs.writeFileSync(paths.metaFile, JSON.stringify(meta, null, 2));

emit({type: 'done', jobDir, meta});
