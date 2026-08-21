// Fast correctness check for a job's composition. The design agent runs
// this after editing Graphics.tsx; a webpack or React error prints here.
//   node validate.js --job <dir>
import {bundle} from '@remotion/bundler';
import {selectComposition} from '@remotion/renderer';
import fs from 'node:fs';
import {arg, emit, fail, jobPaths, webpackOverride, workerDir} from './lib.js';

// selectComposition launches the headless browser; anchor cwd so Remotion
// resolves node_modules/.remotion (see setup.js for the full explanation).
process.chdir(workerDir);

const jobDir = arg('job');
if (!jobDir) fail('usage: validate.js --job <dir>');
const paths = jobPaths(jobDir);
const meta = JSON.parse(fs.readFileSync(paths.metaFile, 'utf8'));

try {
  const serveUrl = await bundle({
    entryPoint: paths.entryPoint,
    webpackOverride,
  });
  const composition = await selectComposition({
    serveUrl,
    id: 'Main',
    inputProps: {meta},
    logLevel: 'error',
  });
  emit({
    type: 'done',
    ok: true,
    composition: {
      width: composition.width,
      height: composition.height,
      fps: composition.fps,
      durationInFrames: composition.durationInFrames,
    },
  });
  process.exit(0);
} catch (e) {
  emit({type: 'done', ok: false, error: String(e.stack || e)});
  process.exit(1);
}
