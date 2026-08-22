// Runs the design agent: reads the job's transcript, metadata, and the
// user's direction, and has Claude write src/Graphics.tsx. Validates the
// result and feeds errors back to the agent, up to MAX_ATTEMPTS times.
//   node generate.js --job <dir> --direction "what the graphics should show"
import { query } from '@anthropic-ai/claude-agent-sdk'
import { execFile } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { promisify } from 'node:util'
import { arg, emit, fail, jobPaths, workerDir } from './lib.js'

const execFileAsync = promisify(execFile)

const MAX_ATTEMPTS = 3

const jobDir = arg('job')
const direction = arg('direction') ?? ''
// When set, this is a revision pass: keep the existing design and apply the
// user's feedback rather than designing from scratch.
const feedback = arg('feedback')
if (!jobDir) fail('usage: generate.js --job <dir> --direction <text> [--feedback <text>]')

// --print-prompt builds and prints the exact prompts for this job, then
// exits without running the agent. Used by the app's prompt viewer.
const printPrompt = process.argv.includes('--print-prompt')

const paths = jobPaths(jobDir)
// In print mode the job may not be prepared yet (no meta/transcript), so fall
// back to placeholders instead of failing.
const meta = fs.existsSync(paths.metaFile)
  ? JSON.parse(fs.readFileSync(paths.metaFile, 'utf8'))
  : { mode: '(not set yet)', width: 0, height: 0, fps: 0, durationInSeconds: 0 }
const transcript = fs.existsSync(paths.transcriptFile)
  ? JSON.parse(fs.readFileSync(paths.transcriptFile, 'utf8'))
  : { segments: [] }

const systemPrompt = `
You are a motion-graphics designer. You design broadcast-quality animated graphics for a video, implemented as a Remotion React composition.

## Your one job
For each line and point covered in the video, add motion graphics to highlight what is said.

## No subtitles
Do not render subtitles, captions, or a running text track of the spoken words. Use the transcript only for timing and for pulling out key words, phrases, numbers, or names worth highlighting as graphics.

## Canvas
- Size: ${meta.width}x${meta.height} pixels, ${meta.fps} fps, ${meta.durationInSeconds.toFixed(1)} seconds.

## Transcript
The transcript is in src/job/transcript.json: a JSON object with a "segments" array, each having text, start, and end (in seconds of video time). It has ${transcript.segments.length} segments. Read that file to time the graphics to what is said, rather than expecting it inline here.

## Finish
When done, reply with one short sentence describing the design. The build is validated separately; you may be asked to fix errors.`

const runAgent = async prompt => {
  const stream = query({
    prompt,
    options: {
      cwd: paths.project,
      systemPrompt,
      allowedTools: ['Read', 'Write', 'Edit', 'Glob', 'Grep'],
      permissionMode: 'acceptEdits',
      // The template ships the official Remotion skills (.claude/skills).
      settingSources: ['project'],
      skills: 'all',
      model: process.env.MG_MODEL || 'claude-fable-5',
      maxTurns: 40,
    },
  })
  for await (const message of stream) {
    if (message.type === 'assistant') {
      for (const block of message.message.content) {
        if (block.type === 'text' && block.text.trim()) {
          emit({ type: 'status', stage: 'designing', text: block.text.trim().slice(0, 300) })
        } else if (block.type === 'tool_use') {
          // Surface each tool call for the debug window.
          emit({ type: 'log', stage: 'designing', tool: block.name, text: summarizeTool(block) })
        }
      }
    } else if (message.type === 'user') {
      // Tool results (e.g. a Bash command's output) come back as user turns.
      for (const block of message.message.content ?? []) {
        if (block.type === 'tool_result') {
          const text = Array.isArray(block.content)
            ? block.content.map(c => (c.type === 'text' ? c.text : '')).join('')
            : String(block.content ?? '')
          if (text.trim()) emit({ type: 'log', stage: 'designing', text: text.trim().slice(0, 2000) })
        }
      }
    } else if (message.type === 'result') {
      if (message.subtype !== 'success') {
        throw new Error(`agent failed: ${message.subtype}`)
      }
      emit({ type: 'status', stage: 'designing', costUSD: message.total_cost_usd })
    }
  }
}

const summarizeTool = block => {
  const i = block.input ?? {}
  switch (block.name) {
    case 'Bash':
      return `$ ${i.command ?? ''}`
    case 'Read':
      return `read ${i.file_path ?? ''}`
    case 'Write':
      return `write ${i.file_path ?? ''}`
    case 'Edit':
      return `edit ${i.file_path ?? ''}`
    case 'Glob':
      return `glob ${i.pattern ?? ''}`
    case 'Grep':
      return `grep ${i.pattern ?? ''}`
    default:
      return `${block.name} ${JSON.stringify(i).slice(0, 200)}`
  }
}

const validate = async () => {
  try {
    const { stdout } = await execFileAsync(process.execPath, [path.join(workerDir, 'validate.js'), '--job', jobDir], {
      maxBuffer: 1024 * 1024 * 16,
    })
    return JSON.parse(stdout.trim().split('\n').pop())
  } catch (e) {
    const lastLine = (e.stdout || '').trim().split('\n').pop()
    try {
      return JSON.parse(lastLine)
    } catch {
      return { ok: false, error: String(e.stderr || e.message) }
    }
  }
}

let prompt = feedback
  ? `You already designed src/Graphics.tsx for this video. The user watched the result and wants changes.

Apply this feedback by editing src/Graphics.tsx. Keep everything that already works; change only what the feedback asks for. Read the current file first.

The user's feedback:
${feedback}

For reference, the original direction was:
${direction || '(none given)'}`
  : `Design the motion graphics for this video now, following the system instructions.

The user's direction:
${direction || '(none given — design tasteful graphics that support the spoken content)'}`

if (printPrompt) {
  process.stdout.write(`=== SYSTEM PROMPT ===\n${systemPrompt}\n\n=== FIRST USER MESSAGE ===\n${prompt}\n`)
  process.exit(0)
}

// Auth: "subscription" uses the claude.ai login Claude Code stored; "apikey"
// uses ANTHROPIC_API_KEY. Default follows whether a key is present.
const authMode = arg('auth') ?? (process.env.ANTHROPIC_API_KEY ? 'apikey' : 'subscription')
if (authMode === 'subscription') {
  // A stray ANTHROPIC_API_KEY would override the subscription login, so
  // clear it. The SDK then falls back to the stored OAuth token.
  delete process.env.ANTHROPIC_API_KEY
} else if (!process.env.ANTHROPIC_API_KEY) {
  fail('ANTHROPIC_API_KEY is not set')
}

// The transcript's canonical home is src/job/transcript.json, written by
// the transcribe step. Mirror it at the job root as a readable asset.
if (fs.existsSync(paths.transcriptFile)) {
  fs.copyFileSync(paths.transcriptFile, paths.transcriptExport)
}

for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
  emit({ type: 'stage', stage: 'designing', attempt })
  try {
    await runAgent(prompt)
  } catch (e) {
    const message = String(e.message || e)
    if (/credit balance/i.test(message)) {
      fail('Your Claude account has no API credits. Add credits at console.anthropic.com and try again.')
    }
    if (/usage limit|rate limit|429/i.test(message)) {
      fail('Your Claude subscription has hit its usage limit. Wait for it to reset and try again.')
    }
    if (/not logged in|no.*credentials|unauthorized|401/i.test(message)) {
      fail(
        'Claude is not signed in. Open Terminal, run "claude", and sign in with your Claude account, then try again.'
      )
    }
    if (/authentication|invalid.*api.?key/i.test(message)) {
      fail('Claude did not accept the API key. Check the key and try again.')
    }
    fail(`the design step failed: ${message.slice(0, 500)}`)
  }

  emit({ type: 'stage', stage: 'checking', attempt })
  const result = await validate()
  if (result.ok) {
    emit({ type: 'done', attempts: attempt })
    process.exit(0)
  }

  emit({ type: 'status', stage: 'checking', text: `attempt ${attempt} failed validation` })
  prompt = `Your src/Graphics.tsx does not build. Fix it. Keep the design; change only what the error requires.

Build error:
${String(result.error).slice(0, 4000)}`
}

fail(`could not produce a working Graphics.tsx after ${MAX_ATTEMPTS} attempts`)
