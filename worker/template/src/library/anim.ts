import {interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';

// Timing helper shared by all library components. Times are in seconds of
// video time, matching the transcript.
export const useTimed = (startSec: number, endSec: number) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const start = Math.round(startSec * fps);
  const end = Math.round(endSec * fps);
  const visible = frame >= start && frame < end;

  const enter = spring({
    frame: frame - start,
    fps,
    config: {damping: 200, stiffness: 160},
  });

  const exitFrames = Math.min(12, Math.max(1, end - start));
  const exit = interpolate(frame, [end - exitFrames, end], [1, 0], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });

  return {visible, enter, exit, progress: enter * exit, frame, fps};
};
