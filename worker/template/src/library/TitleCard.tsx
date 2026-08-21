import React from 'react';
import {useTimed} from './anim';
import {defaultTheme, Theme} from './theme';

// A big centered title, optionally with a subtitle, for openings and
// section breaks.
export const TitleCard: React.FC<{
  title: string;
  subtitle?: string;
  start: number;
  end: number;
  theme?: Theme;
}> = ({title, subtitle, start, end, theme = defaultTheme}) => {
  const {visible, enter, exit} = useTimed(start, end);
  if (!visible) return null;
  return (
    <div
      style={{
        position: 'absolute',
        inset: 0,
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        fontFamily: theme.fontFamily,
        textAlign: 'center',
        opacity: exit,
        padding: '0 8%',
      }}
    >
      <div
        style={{
          fontSize: 110,
          fontWeight: 800,
          color: theme.text,
          lineHeight: 1.1,
          transform: `translateY(${(1 - enter) * 50}px)`,
          opacity: enter,
        }}
      >
        {title}
      </div>
      {subtitle ? (
        <div
          style={{
            marginTop: 28,
            fontSize: 48,
            fontWeight: 500,
            color: theme.accent,
            transform: `translateY(${(1 - enter) * 70}px)`,
            opacity: enter,
          }}
        >
          {subtitle}
        </div>
      ) : null}
    </div>
  );
};
