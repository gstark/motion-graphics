import React from 'react';
import {Composition} from 'remotion';
import metaJson from './job/meta.json';
import {Layout} from './Layout';
import type {JobMeta} from './types';

const meta = metaJson as JobMeta;

export const Root: React.FC = () => {
  return (
    <Composition
      id="Main"
      component={Layout}
      width={meta.width}
      height={meta.height}
      fps={meta.fps}
      durationInFrames={Math.max(1, Math.round(meta.durationInSeconds * meta.fps))}
      defaultProps={{meta}}
    />
  );
};
