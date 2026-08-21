import React from 'react';
import {useTimed} from './anim';
import {defaultTheme, Theme} from './theme';

// A floating rounded box of text at an arbitrary position, for pointing
// something out. Position is in canvas pixels.
export const Callout: React.FC<{
  text: string;
  start: number;
  end: number;
  x: number;
  y: number;
  theme?: Theme;
  fontSize?: number;
  maxWidth?: number;
}> = ({text, start, end, x, y, theme = defaultTheme, fontSize = 40, maxWidth = 560}) => {
  const {visible, enter, exit} = useTimed(start, end);
  if (!visible) return null;
  return (
    <div
      style={{
        position: 'absolute',
        left: x,
        top: y,
        maxWidth,
        padding: `${fontSize * 0.4}px ${fontSize * 0.6}px`,
        background: theme.panel,
        border: `2px solid ${theme.accent}`,
        borderRadius: theme.radius,
        color: theme.text,
        fontFamily: theme.fontFamily,
        fontSize,
        fontWeight: 600,
        lineHeight: 1.35,
        opacity: exit,
        transform: `scale(${0.85 + enter * 0.15})`,
        transformOrigin: 'top left',
      }}
    >
      {text}
    </div>
  );
};
