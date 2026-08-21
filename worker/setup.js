// First-run setup: download the headless browser Remotion renders with.
//   node setup.js
import {ensureBrowser} from '@remotion/renderer';
import {emit, workerDir} from './lib.js';

// Remotion picks its browser cache dir by walking up from process.cwd() to
// the nearest package.json. When the app is launched from Finder the cwd is
// "/", so that walk fails and Remotion falls back to "/.remotion", which it
// cannot create. Anchor the cwd to the worker so it resolves to
// node_modules/.remotion here.
process.chdir(workerDir);

let lastPercent = -1;
await ensureBrowser({
  onBrowserDownload: () => ({
    version: null,
    onProgress: ({percent}) => {
      const p = Math.floor((percent ?? 0) * 100);
      if (p !== lastPercent) {
        lastPercent = p;
        emit({type: 'progress', stage: 'browser-download', percent: p});
      }
    },
  }),
});
emit({type: 'done'});
