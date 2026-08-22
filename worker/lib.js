import path from 'node:path';
import {fileURLToPath} from 'node:url';

export const workerDir = path.dirname(fileURLToPath(import.meta.url));

export const ffmpegPath = process.env.FFMPEG_PATH || 'ffmpeg';
export const ffprobePath = process.env.FFPROBE_PATH || 'ffprobe';

// One NDJSON event per line on stdout; the Swift app parses these.
export const emit = (event) => {
  process.stdout.write(JSON.stringify(event) + '\n');
};

export const fail = (message) => {
  emit({type: 'error', message});
  process.exit(1);
};

// Job dirs live outside the worker, so webpack must be told where the
// worker's node_modules are.
export const webpackOverride = (config) => ({
  ...config,
  resolve: {
    ...config.resolve,
    modules: [
      path.join(workerDir, 'node_modules'),
      'node_modules',
      ...(config.resolve?.modules ?? []),
    ],
  },
});

export const arg = (name) => {
  const i = process.argv.indexOf(`--${name}`);
  return i === -1 ? undefined : process.argv[i + 1];
};

export const jobPaths = (jobDir) => {
  const project = path.join(jobDir, 'project');
  return {
    jobDir,
    project,
    entryPoint: path.join(project, 'src', 'index.ts'),
    metaFile: path.join(project, 'src', 'job', 'meta.json'),
    transcriptFile: path.join(project, 'src', 'job', 'transcript.json'),
    // Readable copy at the job root, next to source.mp4, for inspection.
    transcriptExport: path.join(jobDir, 'transcript.json'),
    outputDir: path.join(jobDir, 'output'),
  };
};
