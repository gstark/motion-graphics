import React from 'react';
import {useCurrentFrame, useVideoConfig} from 'remotion';
import {defaultTheme, Theme} from './theme';

// A thin bar that fills across the full video duration, or across
// an explicit start/end window when given.
export const ProgressBar: React.FC<{
  theme?: Theme;
  y?: number;
  height?: number;
  start?: number;
  end?: number;
}> = ({theme = defaultTheme, y = 0, height = 12, start, end}) => {
  const frame = useCurrentFrame();
  const {fps, durationInFrames} = useVideoConfig();
  const from = (start ?? 0) * fps;
  const to = end === undefined ? durationInFrames : end * fps;
  const progress = Math.min(1, Math.max(0, (frame - from) / Math.max(1, to - from)));
  return (
    <div style={{position: 'absolute', left: 0, right: 0, top: y, height, background: theme.accentSoft}}>
      <div style={{width: `${progress * 100}%`, height: '100%', background: theme.accent}} />
    </div>
  );
};
