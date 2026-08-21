export type LayoutMode = 'separate' | 'video-top' | 'video-bottom';

export type JobMeta = {
  mode: LayoutMode;
  width: number;
  height: number;
  fps: number;
  durationInSeconds: number;
  sourceFileName: string;
};

export type TranscriptSegment = {
  text: string;
  start: number; // seconds
  end: number; // seconds
};

export type Transcript = {
  language: string;
  text: string;
  segments: TranscriptSegment[];
};
