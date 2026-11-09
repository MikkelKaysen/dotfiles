import { pathToFileURL } from "node:url";

/**
 * Pure logic for the /plan:* TUI commands.
 *
 * Plan files live in ~/.opencode/plan. Every side effect (listing,
 * selecting, confirming, deleting, creating sessions, submitting prompts)
 * is injected so the flows can be tested without a running TUI, mirroring
 * the worktree-picker pattern in opencode-bare-layout.
 */

export interface PlanEntry {
  /** Absolute path of the plan file. */
  path: string;
  /** File name, e.g. "foo.md". */
  name: string;
  /** Text of the first `# ` heading line, or "" when there is none. */
  title: string;
  /** Last-modified time, ms since the epoch. */
  mtimeMs: number;
}

export interface PlanChoice {
  title: string;
  value: string;
  description: string;
}

export interface PlanFileAttachment {
  uri: string;
  name: string;
  description: string;
}

export const DEFAULT_ATTACH_TEXT =
  "Read the attached plan and wait for my instructions. Do not implement anything yet.";

export const DEFAULT_IMPLEMENT_TEXT =
  "Implement the attached plan. Work through it step by step, verify each step, and report what changed.";

/** Returns the text of the first level-1 heading line, or "" when none exists. */
export function parsePlanTitle(content: string): string {
  for (const line of content.split("\n")) {
    const trimmed = line.trim();
    if (trimmed.startsWith("# ")) {
      const value = trimmed.slice(2).trim();
      if (value) return value;
    }
  }
  return "";
}

/** Display title for a plan: the heading title, else the file name without .md. */
export function planDisplayName(entry: Pick<PlanEntry, "title" | "name">): string {
  return entry.title || entry.name.replace(/\.md$/, "");
}

/** Builds picker choices for the given plans, sorted newest first. */
export function planChoices(entries: readonly PlanEntry[]): PlanChoice[] {
  return [...entries]
    .toSorted((a, b) => b.mtimeMs - a.mtimeMs)
    .map((entry) => ({
      title: entry.title ? `${entry.name} · ${entry.title}` : entry.name,
      value: entry.path,
      description: `${entry.name} · modified ${new Date(entry.mtimeMs).toISOString().slice(0, 10)}`,
    }));
}

/** File attachment descriptor for a plan (absolute file: URL). */
export function planFile(entry: PlanEntry): PlanFileAttachment {
  return {
    uri: pathToFileURL(entry.path).href,
    name: entry.name,
    description: `Plan: ${planDisplayName(entry)}`,
  };
}

/** Lists plans and lets the user pick one; errors, empty lists, and cancels resolve to undefined. */
export async function pickPlan(input: {
  list: () => Promise<PlanEntry[]>;
  select: (choices: readonly PlanChoice[]) => Promise<string | undefined>;
  emptyMessage?: string;
  toast: (message: string) => void;
}): Promise<PlanEntry | undefined> {
  let entries: PlanEntry[];
  try {
    entries = await input.list();
  } catch (error) {
    input.toast(`Could not list plans: ${error instanceof Error ? error.message : String(error)}`);
    return undefined;
  }
  const choices = planChoices(entries);
  if (choices.length === 0) {
    input.toast(input.emptyMessage ?? "No plans found.");
    return undefined;
  }
  const selected = await input.select(choices);
  if (selected === undefined) return undefined;
  return entries.find((entry) => entry.path === selected);
}

/**
 * /plan:existing — attaches the selected plan to a session.
 * Inside a session, targets it directly; otherwise creates a session and
 * navigates to it first. The caller may supply an optional message; when
 * none is typed, DEFAULT_ATTACH_TEXT is submitted.
 */
export async function attachPlan(input: {
  sessionID?: string;
  location: string;
  plan: PlanEntry;
  prompt: (title: string) => Promise<string | undefined>;
  create: (location: string) => Promise<{ id: string }>;
  navigate: (sessionID: string) => void;
  submit: (sessionID: string, text: string, file: PlanFileAttachment) => Promise<void>;
  toast: (message: string) => void;
}): Promise<void> {
  try {
    let sessionID = input.sessionID;
    if (sessionID === undefined) {
      const created = await input.create(input.location);
      sessionID = created.id;
      input.navigate(sessionID);
    }
    const typed = await input.prompt(`Message for "${planDisplayName(input.plan)}" (optional)`);
    const text = typed?.trim() || DEFAULT_ATTACH_TEXT;
    await input.submit(sessionID, text, planFile(input.plan));
  } catch (error) {
    input.toast(`Could not attach plan: ${error instanceof Error ? error.message : String(error)}`);
  }
}

/**
 * /plan:remove — deletes the selected plan file after an explicit confirm.
 * Cancelling is a no-op.
 */
export async function removePlan(input: {
  plan: PlanEntry;
  confirm: () => Promise<boolean | undefined>;
  unlink: (path: string) => Promise<void>;
  success: (message: string) => void;
  error: (message: string) => void;
}): Promise<void> {
  const confirmed = await input.confirm();
  if (confirmed !== true) return;
  try {
    await input.unlink(input.plan.path);
    input.success(`Deleted "${planDisplayName(input.plan)}".`);
  } catch (error) {
    input.error(`Could not delete plan: ${error instanceof Error ? error.message : String(error)}`);
  }
}

/**
 * /plan:implement — starts implementing the selected plan.
 * Targets the current session, or creates and navigates to a new one when
 * there is no active session. Switches the responding agent (default:
 * "build") when it differs, then submits DEFAULT_IMPLEMENT_TEXT with the
 * plan attached.
 */
export async function implementPlan(input: {
  sessionID?: string;
  location: string;
  plan: PlanEntry;
  agent?: string;
  create: (location: string) => Promise<{ id: string }>;
  navigate: (sessionID: string) => void;
  getAgent: (sessionID: string) => string | undefined;
  switchAgent: (sessionID: string, agent: string) => Promise<void>;
  submit: (sessionID: string, text: string, file: PlanFileAttachment) => Promise<void>;
  error: (message: string) => void;
}): Promise<void> {
  const agent = input.agent ?? "build";
  try {
    let sessionID = input.sessionID;
    if (sessionID === undefined) {
      const created = await input.create(input.location);
      sessionID = created.id;
      input.navigate(sessionID);
    }
    if (input.getAgent(sessionID) !== agent) await input.switchAgent(sessionID, agent);
    await input.submit(sessionID, DEFAULT_IMPLEMENT_TEXT, planFile(input.plan));
  } catch (error) {
    input.error(`Could not start implementation: ${error instanceof Error ? error.message : String(error)}`);
  }
}
