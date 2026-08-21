import React from 'react';
import {useCurrentFrame, useVideoConfig} from 'remotion';
import {useTimed} from './anim';
import {defaultTheme, Theme} from './theme';
import type {TranscriptSegment} from '../types';

// Shows the transcript phrase that is active at the current time,
// as a pill anchored near the bottom of the canvas.
export const Caption: React.FC<{
  segments: TranscriptSegment[];
  theme?: Theme;
  fontSize?: number;
  bottom?: number;
}> = ({segments, theme = defaultTheme, fontSize = 52, bottom = 80}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const t = frame / fps;
  const active = segments.find((s) => t >= s.start && t < s.end);
  if (!active) return null;
  return <CaptionPill key={active.start} segment={active} theme={theme} fontSize={fontSize} bottom={bottom} />;
};

const CaptionPill: React.FC<{
  segment: TranscriptSegment;
  theme: Theme;
  fontSize: number;
  bottom: number;
}> = ({segment, theme, fontSize, bottom}) => {
  const {progress} = useTimed(segment.start, segment.end);
  return (
    <div
      style={{
        position: 'absolute',
        left: 0,
        right: 0,
        bottom,
        display: 'flex',
        justifyContent: 'center',
        opacity: progress,
      }}
    >
      <div
        style={{
          maxWidth: '80%',
          padding: `${fontSize * 0.35}px ${fontSize * 0.7}px`,
          background: theme.panel,
          border: `2px solid ${theme.panelBorder}`,
          borderRadius: theme.radius,
          color: theme.text,
          fontFamily: theme.fontFamily,
          fontSize,
          fontWeight: 600,
          textAlign: 'center',
          lineHeight: 1.3,
          transform: `translateY(${(1 - progress) * 24}px)`,
        }}
      >
        {segment.text}
      </div>
    </div>
  );
};
