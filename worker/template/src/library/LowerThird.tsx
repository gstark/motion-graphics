import React from 'react';
import {useTimed} from './anim';
import {defaultTheme, Theme} from './theme';

// Name/title bar that slides in from the left, like a broadcast lower third.
export const LowerThird: React.FC<{
  title: string;
  subtitle?: string;
  start: number;
  end: number;
  theme?: Theme;
  bottom?: number;
  left?: number;
}> = ({title, subtitle, start, end, theme = defaultTheme, bottom = 100, left = 80}) => {
  const {visible, enter, exit} = useTimed(start, end);
  if (!visible) return null;
  return (
    <div
      style={{
        position: 'absolute',
        left,
        bottom,
        opacity: exit,
        transform: `translateX(${(1 - enter) * -60}px)`,
        fontFamily: theme.fontFamily,
      }}
    >
      <div
        style={{
          display: 'inline-block',
          background: theme.accent,
          color: theme.textOnAccent,
          padding: '14px 34px',
          borderRadius: theme.radius,
          fontSize: 54,
          fontWeight: 700,
        }}
      >
        {title}
      </div>
      {subtitle ? (
        <div
          style={{
            display: 'block',
            marginTop: 10,
            background: theme.panel,
            border: `2px solid ${theme.panelBorder}`,
            color: theme.text,
            padding: '10px 26px',
            borderRadius: theme.radius * 0.7,
            fontSize: 36,
            fontWeight: 500,
            width: 'fit-content',
          }}
        >
          {subtitle}
        </div>
      ) : null}
    </div>
  );
};
