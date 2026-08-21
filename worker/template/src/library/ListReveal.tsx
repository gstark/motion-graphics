import React from 'react';
import {useCurrentFrame, useVideoConfig, spring} from 'remotion';
import {useTimed} from './anim';
import {defaultTheme, Theme} from './theme';

// A vertical list whose items pop in one after another.
export const ListReveal: React.FC<{
  items: string[];
  start: number;
  end: number;
  x: number;
  y: number;
  theme?: Theme;
  fontSize?: number;
  staggerSeconds?: number;
}> = ({items, start, end, x, y, theme = defaultTheme, fontSize = 46, staggerSeconds = 0.5}) => {
  const {visible, exit} = useTimed(start, end);
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  if (!visible) return null;
  return (
    <div
      style={{
        position: 'absolute',
        left: x,
        top: y,
        display: 'flex',
        flexDirection: 'column',
        gap: fontSize * 0.5,
        fontFamily: theme.fontFamily,
        opacity: exit,
      }}
    >
      {items.map((item, i) => {
        const itemStart = Math.round((start + i * staggerSeconds) * fps);
        const enter = spring({
          frame: frame - itemStart,
          fps,
          config: {damping: 200, stiffness: 170},
        });
        return (
          <div
            key={i}
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: fontSize * 0.5,
              opacity: enter,
              transform: `translateX(${(1 - enter) * -40}px)`,
            }}
          >
            <div
              style={{
                width: fontSize * 0.45,
                height: fontSize * 0.45,
                borderRadius: '50%',
                background: theme.accent,
                flexShrink: 0,
              }}
            />
            <div style={{fontSize, fontWeight: 600, color: theme.text, lineHeight: 1.3}}>{item}</div>
          </div>
        );
      })}
    </div>
  );
};
