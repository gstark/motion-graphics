// This is the file the design agent writes. Everything visual lives here.
// The default below shows captions and a progress bar so a fresh job
// still renders something sensible.
import React from 'react';
import {AbsoluteFill} from 'remotion';
import {Caption, ProgressBar} from './library';
import transcriptJson from './job/transcript.json';
import type {Transcript} from './types';

const transcript = transcriptJson as Transcript;

export const Graphics: React.FC = () => {
  return (
    <AbsoluteFill>
      <ProgressBar y={0} />
      <Caption segments={transcript.segments} />
    </AbsoluteFill>
  );
};
