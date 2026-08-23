// Downloads a video with yt-dlp.
//   node download.js --url <video url> --out <dir>
// Writes <dir>/source.<ext> and emits NDJSON progress.
import {spawn} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {arg, emit, fail} from './lib.js';

// Anything the Debug panel should show. yt-dlp writes its real diagnosis to
// stderr, which never reached the app before.
const logLine = (text) => emit({type: 'log', tool: 'yt-dlp', text});

const ytdlpPath = process.env.YTDLP_PATH || 'yt-dlp';
const MAX_ATTEMPTS = 10;

const url = arg('url');
const outDir = arg('out');
if (!url || !outDir) fail('usage: download.js --url <url> --out <dir>');
fs.mkdirSync(outDir, {recursive: true});

// Chrome's cookies get us past age gates, private videos, and the sign-in
// wall that some sites show to logged-out visitors.
const cookieArgs = ['--cookies-from-browser', 'chrome'];

const runYtdlp = (withCookies) =>
  new Promise((resolve) => {
    const args = [
      '--newline',
      '--no-playlist',
      '--retries', '10',
      '--fragment-retries', '10',
      // YouTube's n challenge needs a JavaScript runtime. The app's PATH is
      // the bare launchd one, so deno is not found even when it is installed.
      // Point yt-dlp at the node we are already running on.
      '--js-runtimes', `node:${process.execPath}`,
      ...(withCookies ? cookieArgs : []),
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
    ];
    logLine(`${ytdlpPath} ${args.join(' ')}`);

    const child = spawn(ytdlpPath, args);

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
          continue;
        }
        // Everything else on stdout is yt-dlp narrating what it picked:
        // the extractor, the format, the merge. Keep it for the log.
        if (line.trim()) logLine(line.trim());
      }
    });
    child.stderr.on('data', (chunk) => {
      const text = chunk.toString();
      stderrTail = (stderrTail + text).slice(-4000);
      for (const line of text.split('\n')) {
        if (line.trim()) logLine(line.trim());
      }
    });

    child.on('error', (error) => {
      logLine(`yt-dlp could not start: ${error.message}`);
      resolve({ok: false, stderr: error.message});
    });
    child.on('close', (code) => {
      logLine(`yt-dlp exited with code ${code}`);
      resolve({ok: code === 0, stderr: stderrTail});
    });
  });

// Reading Chrome's cookie jar fails on its own terms: no Chrome installed,
// a locked Keychain, a refused unlock prompt. That says nothing about the
// URL, so drop the flag and keep going without it.
const cookieProblem = (stderr) =>
  /cookies|keychain|chrome/i.test(stderr) && !/HTTP Error|Unsupported URL|Unable to download webpage/i.test(stderr);

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const mergedVideo = () =>
  fs.readdirSync(outDir).find((f) => /^source\.(mp4|webm|mkv|mov|m4v)$/i.test(f));

logLine(`yt-dlp binary: ${ytdlpPath}`);
logLine(`node: ${process.execPath}`);
logLine(`HOME=${process.env.HOME || '(unset)'}`);
logLine(`PATH=${process.env.PATH || '(unset)'}`);

let useCookies = true;
let lastStderr = '';

for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
  if (attempt > 1) {
    emit({type: 'status', text: `Retrying the download (attempt ${attempt} of ${MAX_ATTEMPTS})`});
    // Back off a little; a rate limit is the usual reason a retry helps.
    await sleep(Math.min(2000 * attempt, 10000));
  }

  logLine(`attempt ${attempt} of ${MAX_ATTEMPTS}, cookies ${useCookies ? 'on' : 'off'}`);
  const result = await runYtdlp(useCookies);
  lastStderr = result.stderr;

  // Match only the merged output, never intermediate source.fNNN.* files.
  if (result.ok) {
    if (mergedVideo()) break;
    // yt-dlp is happy but there is nothing to edit. A retry cannot change
    // that, so stop here.
    emit({type: 'error', message: 'The download finished but produced no video file. Try a different link.'});
    process.exit(1);
  }

  if (useCookies && cookieProblem(result.stderr)) {
    useCookies = false;
    emit({type: 'status', text: 'Chrome cookies are not available; downloading without them'});
  }

  if (attempt === MAX_ATTEMPTS) {
    // The last line is the summary; the ones above it usually say why.
    const tail = lastStderr.trim().split('\n').filter((l) => l.trim());
    logLine(`giving up after ${MAX_ATTEMPTS} attempts`);
    const cause = tail[tail.length - 1] || 'no details from yt-dlp';
    emit({
      type: 'error',
      message: `We could not download the video from that link. We tried ${MAX_ATTEMPTS} times. The video may be private, region locked, or removed. Sign in to the site in Chrome and try again, or download the file yourself and open it from your computer. (${cause})`,
    });
    process.exit(1);
  }
}

const file = mergedVideo();
const subtitles = fs.readdirSync(outDir).find((f) => f.endsWith('.vtt'));
emit({
  type: 'done',
  output: path.join(outDir, file),
  subtitles: subtitles ? path.join(outDir, subtitles) : undefined,
});
