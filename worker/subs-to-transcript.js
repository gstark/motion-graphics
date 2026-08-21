// Converts a WebVTT caption file into the job's transcript.json.
// Handles YouTube auto-captions: inline word timestamps, styling tags,
// and rolling duplicate lines.
//   node subs-to-transcript.js --vtt <file> --job <dir> [--lang en-US]
import fs from 'node:fs';
import {arg, emit, fail, jobPaths} from './lib.js';

const vttFile = arg('vtt');
const jobDir = arg('job');
const lang = arg('lang') ?? 'en';
if (!vttFile || !jobDir) fail('usage: subs-to-transcript.js --vtt <file> --job <dir>');

const toSeconds = (stamp) => {
  const parts = stamp.trim().split(':').map(Number);
  const [h, m, s] = parts.length === 3 ? parts : [0, parts[0], parts[1]];
  return h * 3600 + m * 60 + s;
};

const clean = (text) =>
  text
    .replace(/<[^>]+>/g, '') // <c>, </c>, <00:00:01.500>
    .replace(/&amp;/g, '&')
    .replace(/&gt;/g, '>')
    .replace(/&lt;/g, '<')
    .replace(/\s+/g, ' ')
    .trim();

const raw = fs.readFileSync(vttFile, 'utf8');
const cueRegex = /(\d[\d:.]*)\s+-->\s+(\d[\d:.]*)[^\n]*\n([\s\S]*?)(?=\n\s*\n|$)/g;

const cues = [];
for (const match of raw.matchAll(cueRegex)) {
  const lines = match[3].split('\n').map(clean).filter(Boolean);
  if (!lines.length) continue;
  cues.push({start: toSeconds(match[1]), end: toSeconds(match[2]), lines});
}

// Rolling auto-captions repeat the previous line above the new one.
// Keep only text we have not shown yet.
const segments = [];
let lastText = '';
for (const cue of cues) {
  let lines = cue.lines;
  if (lines.length > 1 && lines[0] === lastText) lines = lines.slice(1);
  const text = lines.join(' ').trim();
  if (!text || text === lastText) continue;
  segments.push({text, start: cue.start, end: cue.end});
  lastText = text;
}

// Caption cues break mid-sentence. Merge them into sentence-sized
// segments so the design agent gets meaningful timing anchors.
const merged = [];
for (const seg of segments) {
  const current = merged[merged.length - 1];
  const endsSentence = (t) => /[.!?…]"?$/.test(t);
  if (current && !current.closed && current.end - current.start < 12) {
    current.text += ' ' + seg.text;
    current.end = seg.end;
    current.closed = endsSentence(current.text);
  } else {
    merged.push({text: seg.text, start: seg.start, end: seg.end, closed: endsSentence(seg.text)});
  }
}
segments.length = 0;
segments.push(...merged.map(({text, start, end}) => ({text, start, end})));

// Fix zero-length or overlapping windows left by rolling captions.
for (let i = 0; i < segments.length; i++) {
  const next = segments[i + 1];
  if (next && segments[i].end > next.start) segments[i].end = next.start;
  if (segments[i].end - segments[i].start < 0.2) {
    segments[i].end = segments[i].start + (next ? Math.min(2, next.start - segments[i].start) : 2);
  }
}

const paths = jobPaths(jobDir);
const transcript = {
  language: lang,
  text: segments.map((s) => s.text).join(' '),
  segments,
};
fs.writeFileSync(paths.transcriptFile, JSON.stringify(transcript, null, 2));
emit({type: 'done', segments: segments.length, output: paths.transcriptFile});
