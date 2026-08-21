import React from 'react';
import {useTimed} from './anim';
import {defaultTheme, Theme} from './theme';

// An animated rounded outline that draws attention to a rectangular
// region of the canvas (in pixels). Useful in 'separate' mode where the
// graphics sit on top of the original video.
export const Highlight: React.FC<{
  start: number;
  end: number;
  x: number;
  y: number;
  width: number;
  height: number;
  theme?: Theme;
  strokeWidth?: number;
}> = ({start, end, x, y, width, height, theme = defaultTheme, strokeWidth = 6}) => {
  const {visible, enter, exit} = useTimed(start, end);
  if (!visible) return null;
  const grow = 1 + (1 - enter) * 0.15;
  return (
    <div
      style={{
        position: 'absolute',
        left: x,
        top: y,
        width,
        height,
        border: `${strokeWidth}px solid ${theme.accent}`,
        borderRadius: theme.radius,
        boxShadow: `0 0 0 ${strokeWidth}px ${theme.accentSoft}`,
        opacity: enter * exit,
        transform: `scale(${grow})`,
      }}
    />
  );
};
