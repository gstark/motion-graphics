import React from 'react';
import {interpolate} from 'remotion';
import {useTimed} from './anim';
import {defaultTheme, Theme} from './theme';

// A big number that counts up from 0 when it appears, with a label under it.
export const StatCounter: React.FC<{
  value: number;
  label: string;
  start: number;
  end: number;
  x: number;
  y: number;
  prefix?: string;
  suffix?: string;
  decimals?: number;
  theme?: Theme;
}> = ({value, label, start, end, x, y, prefix = '', suffix = '', decimals = 0, theme = defaultTheme}) => {
  const {visible, enter, exit, frame, fps} = useTimed(start, end);
  if (!visible) return null;
  const countProgress = interpolate(frame - Math.round(start * fps), [0, fps], [0, 1], {
    extrapolateLeft: 'clamp',
    extrapolateRight: 'clamp',
  });
  const shown = (value * countProgress).toFixed(decimals);
  return (
    <div
      style={{
        position: 'absolute',
        left: x,
        top: y,
        textAlign: 'center',
        fontFamily: theme.fontFamily,
        opacity: exit,
        transform: `translateY(${(1 - enter) * 30}px)`,
      }}
    >
      <div style={{fontSize: 120, fontWeight: 800, color: theme.accent, lineHeight: 1}}>
        {prefix}
        {shown}
        {suffix}
      </div>
      <div style={{fontSize: 40, fontWeight: 600, color: theme.text, marginTop: 12}}>{label}</div>
    </div>
  );
};
