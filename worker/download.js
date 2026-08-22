// Downloads a video with yt-dlp.
//   node download.js --url <video url> --out <dir>
// Writes <dir>/source.<ext> and emits NDJSON progress.
import {spawn} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {arg, emit, fail} from './lib.js';

const ytdlpPath = process.env.YTDLP_PATH || 'yt-dlp';

const url = arg('url');
const outDir = arg('out');
if (!url || !outDir) fail('usage: download.js --url <url> --out <dir>');
fs.mkdirSync(outDir, {recursive: true});

const child = spawn(ytdlpPath, [
  '--newline',
  '--no-playlist',
  '--retries', '10',
  '--fragment-retries', '10',
  '-f', 'bv*[height<=1080]+ba/b[height<=1080]/b',
  '--merge-output-format', 'mp4',
  // Grab a caption track when one exists; transcription is the fallback.
  '--write-subs', '--write-auto-subs',
  '--sub-langs', 'en.*,en',
  '--sub-format', 'vtt',
  // Only pin ffmpeg when the app provides a real path; a bare command
  // name makes yt-dlp skip merging without an error.
  ...(process.env.FFMPEG_PATH ? ['--ffmpeg-location', process.env.FFMPEG_PATH] : []),
  '-o', path.join(outDir, 'source.%(ext)s'),
  url,
]);

let stderrTail = '';
let lastPercent = -1;

child.stdout.on('data', (chunk) => {
  for (const line of chunk.toString().split('\n')) {
    const match = line.match(/\[download\]\s+([\d.]+)%/);
    if (match) {
      const percent = Math.floor(Number(match[1]));
      if (percent !== lastPercent) {
        lastPercent = percent;
        emit({type: 'progress', stage: 'downloading', percent});
      }
    }
  }
});
child.stderr.on('data', (chunk) => {
  stderrTail = (stderrTail + chunk.toString()).slice(-4000);
});

child.on('close', (code) => {
  if (code !== 0) {
    // This message is shown to the user as-is; keep it friendly, with the
    // technical cause in parentheses for the curious.
    const cause = stderrTail.trim().split('\n').pop() || 'unknown error';
    emit({type: 'error', message: `The video could not be downloaded. Check the link and try again. (${cause})`});
    process.exit(1);
  }
  // Match only the merged output, never intermediate source.fNNN.* files.
  const file = fs.readdirSync(outDir).find((f) => /^source\.(mp4|webm|mkv|mov|m4v)$/i.test(f));
  if (!file) {
    emit({type: 'error', message: 'The download finished but produced no video file. Try a different link.'});
    process.exit(1);
  }
  const subtitles = fs.readdirSync(outDir).find((f) => f.endsWith('.vtt'));
  emit({
    type: 'done',
    output: path.join(outDir, file),
    subtitles: subtitles ? path.join(outDir, subtitles) : undefined,
  });
});
