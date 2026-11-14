import assert from "node:assert/strict";
import { test } from "node:test";
import {
  attachPlan,
  DEFAULT_ATTACH_TEXT,
  DEFAULT_IMPLEMENT_TEXT,
  implementPlan,
  parsePlanTitle,
  pickPlan,
  planChoices,
  planDisplayName,
  planFile,
  removePlan,
  type PlanEntry,
  type PlanChoice,
} from "./plan-picker.ts";

// ── shared fixture ────────────────────────────────────────────────────

const base = Date.parse("2026-10-27");

const planA: PlanEntry = {
  path: "/home/u/.opencode/plan/demo.md",
  name: "demo.md",
  title: "Demo plan",
  mtimeMs: base,
};

const planB: PlanEntry = {
  path: "/home/u/.opencode/plan/todo.md",
  name: "todo.md",
  title: "Todo list",
  mtimeMs: base + 1000, // newer
};

// ── 1. parsePlanTitle ─────────────────────────────────────────────────

test("parsePlanTitle: returns first '# ' heading text", () => {
  assert.equal(parsePlanTitle("# My Plan\nSome body"), "My Plan");
  assert.equal(parsePlanTitle("# Another\n\n## Sub"), "Another");
});

test("parsePlanTitle: returns '' when no heading", () => {
  assert.equal(parsePlanTitle("no heading here"), "");
  assert.equal(parsePlanTitle("#no-space"), "");
  assert.equal(parsePlanTitle("## sub only"), "");
  assert.equal(parsePlanTitle(""), "");
});

// ── 2. planDisplayName ────────────────────────────────────────────────

test("planDisplayName: uses title when present", () => {
  assert.equal(planDisplayName(planA), "Demo plan");
});

test("planDisplayName: falls back to name without .md", () => {
  const noTitle: Pick<PlanEntry, "title" | "name"> = { path: "/x/a.md", name: "a.md", title: "", mtimeMs: 0 };
  assert.equal(planDisplayName(noTitle as PlanEntry), "a");
});

// ── 3. planChoices ────────────────────────────────────────────────────

test("planChoices: sorts newest-first by mtimeMs", () => {
  const choices = planChoices([planA, planB]);
  assert.equal(choices.length, 2);
  assert.equal(choices[0].title, "todo.md · Todo list"); // newer
  assert.equal(choices[1].title, "demo.md · Demo plan");
});

test("planChoices: titled plan label is 'filename · heading title'", () => {
  const [choice] = planChoices([{
    path: "/p/atoz-codegraph-integration.md",
    name: "atoz-codegraph-integration.md",
    title: "ATOZ CodeGraph integration plan",
    mtimeMs: base,
  }]);
  assert.equal(choice.title, "atoz-codegraph-integration.md · ATOZ CodeGraph integration plan");
});

test("planChoices: untitled plan label is the filename only, not duplicated", () => {
  const [choice] = planChoices([{ path: "/p/notes.md", name: "notes.md", title: "", mtimeMs: base }]);
  assert.equal(choice.title, "notes.md");
});

test("planChoices: value is the absolute path", () => {
  const [c0, c1] = planChoices([planA, planB]);
  assert.equal(c0.value, "/home/u/.opencode/plan/todo.md");
  assert.equal(c1.value, "/home/u/.opencode/plan/demo.md");
});

test("planChoices: description includes file name and ISO date", () => {
  const choices = planChoices([planA]);
  assert.match(choices[0].description, /demo\.md · modified 2026-10-27$/);
});

test("planChoices: empty input yields empty output", () => {
  assert.deepEqual(planChoices([]), []);
});

// ── 4. planFile ───────────────────────────────────────────────────────

test("planFile: uri equals pathToFileURL(path).href", () => {
  const f = planFile(planA);
  assert.equal(f.uri, "file:///home/u/.opencode/plan/demo.md");
});

test("planFile: name is the file name", () => {
  assert.equal(planFile(planA).name, "demo.md");
});

test("planFile: description starts with 'Plan: '", () => {
  assert.match(planFile(planA).description, /^Plan: Demo plan$/);
});

// ── 5. pickPlan ───────────────────────────────────────────────────────

test("pickPlan: list rejects → error toast, returns undefined, select not called", async () => {
  const effects: string[] = [];
  let called = false;
  const result = await pickPlan({
    list: async () => { throw new Error("fs fail"); },
    select: async () => { called = true; return undefined; },
    toast: (m) => effects.push(`toast:${m}`),
  });
  assert.equal(result, undefined);
  assert.equal(called, false);
  assert.match(effects[0], /Could not list plans: fs fail/);
  assert.equal(effects.length, 1);
});

test("pickPlan: empty list → emptyMessage toast, select not called", async () => {
  const effects: string[] = [];
  let called = false;
  const result = await pickPlan({
    list: async () => [],
    select: async () => { called = true; return undefined; },
    emptyMessage: "Nothing here.",
    toast: (m) => effects.push(`toast:${m}`),
  });
  assert.equal(result, undefined);
  assert.equal(called, false);
  assert.equal(effects[0], "toast:Nothing here.");
  assert.equal(effects.length, 1);
});

test("pickPlan: select returns undefined (cancel) → undefined, no toast", async () => {
  const effects: string[] = [];
  await pickPlan({
    list: async () => [planA],
    select: async () => undefined,
    toast: (m) => effects.push(`toast:${m}`),
  });
  assert.deepEqual(effects, []);
});

test("pickPlan: select returns a path → returns the matching entry", async () => {
  const result = await pickPlan({
    list: async () => [planA, planB],
    select: async () => planA.path,
    toast: () => {},
  });
  assert.deepEqual(result, planA);
});

test("pickPlan: select given exactly the planChoices output (assert titles/descriptions)", async () => {
  const expectedChoices = planChoices([planA, planB]);
  const capturedChoices: readonly PlanChoice[] = [];
  const result = await pickPlan({
    list: async () => [planA, planB],
    select: async (choices) => {
      capturedChoices.push(...choices);
      return planB.path; // pick the newer one
    },
    toast: () => {},
  });
  assert.equal(result, planB);
  // choices received must match planChoices exactly
  assert.deepEqual(capturedChoices, expectedChoices);
});

// ── 6. attachPlan ─────────────────────────────────────────────────────

test("attachPlan: with sessionID → prompt called, typed text trimmed, create/navigate NOT called, submit called with correct args", async () => {
  const created: string[] = [];
  const navigated: string[] = [];
  const submitted: Array<{ sessionID: string; text: string; file: unknown }> = [];
  const effects: string[] = [];

  await attachPlan({
    sessionID: "ses-1",
    location: "/repo",
    plan: planA,
    prompt: async () => "  yes please  ",
    create: async (loc) => { created.push(loc); return { id: "new" }; },
    navigate: (id) => navigated.push(id),
    submit: async (sid, text, file) => submitted.push({ sessionID: sid, text, file }),
    toast: (m) => effects.push(m),
  });

  assert.deepEqual(created, []);
  assert.deepEqual(navigated, []);
  assert.equal(submitted.length, 1);
  assert.equal(submitted[0].sessionID, "ses-1");
  assert.equal(submitted[0].text, "yes please"); // trimmed
  assert.deepEqual(submitted[0].file, planFile(planA));
  assert.deepEqual(effects, []);
});

test("attachPlan: prompt returns '' or undefined → DEFAULT_ATTACH_TEXT is submitted", async () => {
  const submitted: Array<{ text: string }> = [];

  await attachPlan({
    sessionID: "s1",
    location: "/repo",
    plan: planA,
    prompt: async () => "",
    create: async () => ({ id: "n" }),
    navigate: () => {},
    submit: async (sid, text) => submitted.push({ text }),
    toast: () => {},
  });
  assert.equal(submitted[0].text, DEFAULT_ATTACH_TEXT);

  submitted.length = 0;
  await attachPlan({
    sessionID: "s2",
    location: "/repo",
    plan: planA,
    prompt: async () => undefined,
    create: async () => ({ id: "n" }),
    navigate: () => {},
    submit: async (sid, text) => submitted.push({ text }),
    toast: () => {},
  });
  assert.equal(submitted[0].text, DEFAULT_ATTACH_TEXT);
});

test("attachPlan: without sessionID → create(location) called, navigate(created id) called, submit targets created id", async () => {
  const created: Array<{ loc: string }> = [];
  const navigated: string[] = [];
  const submitted: string[] = [];

  await attachPlan({
    sessionID: undefined,
    location: "/repo",
    plan: planA,
    prompt: async () => "go",
    create: async (loc) => { created.push({ loc }); return { id: "new-99" }; },
    navigate: (id) => navigated.push(id),
    submit: async (sid) => submitted.push(sid),
    toast: () => {},
  });

  assert.deepEqual(created, [{ loc: "/repo" }]);
  assert.deepEqual(navigated, ["new-99"]);
  assert.deepEqual(submitted, ["new-99"]);
});

test("attachPlan: submit rejects → toast containing error", async () => {
  const messages: string[] = [];
  await attachPlan({
    sessionID: "s1",
    location: "/repo",
    plan: planA,
    prompt: async () => "go",
    create: async () => ({ id: "n" }),
    navigate: () => {},
    submit: async () => { throw new Error("api down"); },
    toast: (m) => messages.push(m),
  });
  assert.match(messages[0], /Could not attach plan/);
  assert.match(messages[0], /api down/);
});

// ── 7. removePlan ─────────────────────────────────────────────────────

test("removePlan: confirm returns false → unlink NOT called, no toasts", async () => {
  const unlinked: string[] = [];
  const effects: string[] = [];
  await removePlan({
    plan: planA,
    confirm: async () => false,
    unlink: async (p) => unlinked.push(p),
    success: (m) => effects.push(m),
    error: (m) => effects.push(m),
  });
  assert.deepEqual(unlinked, []);
  assert.deepEqual(effects, []);
});

test("removePlan: confirm returns undefined → unlink NOT called", async () => {
  const unlinked: string[] = [];
  const effects: string[] = [];
  await removePlan({
    plan: planA,
    confirm: async () => undefined,
    unlink: async (p) => unlinked.push(p),
    success: (m) => effects.push(m),
    error: (m) => effects.push(m),
  });
  assert.deepEqual(unlinked, []);
  assert.deepEqual(effects, []);
});

test("removePlan: confirm returns true → unlink(plan.path) called + success toast with display name", async () => {
  const unlinked: string[] = [];
  const effects: string[] = [];
  await removePlan({
    plan: planA,
    confirm: async () => true,
    unlink: async (p) => unlinked.push(p),
    success: (m) => effects.push(m),
    error: (m) => effects.push(m),
  });
  assert.deepEqual(unlinked, ["/home/u/.opencode/plan/demo.md"]);
  assert.equal(effects[0], 'Deleted "Demo plan".');
});

test("removePlan: unlink rejects → error toast containing 'Could not delete plan'", async () => {
  const messages: string[] = [];
  await removePlan({
    plan: planA,
    confirm: async () => true,
    unlink: async () => { throw new Error("permission denied"); },
    success: () => {},
    error: (m) => messages.push(m),
  });
  assert.match(messages[0], /Could not delete plan/);
  assert.match(messages[0], /permission denied/);
});

// ── 8. implementPlan ──────────────────────────────────────────────────

test("implementPlan: sessionID present, getAgent returns 'build' → switchAgent NOT called, submit called", async () => {
  const switched: string[] = [];
  const submitted: string[] = [];

  await implementPlan({
    sessionID: "s1",
    location: "/repo",
    plan: planA,
    create: async () => ({ id: "n" }),
    navigate: () => {},
    getAgent: () => "build",
    switchAgent: async () => switched.push("s1"),
    submit: async (sid) => submitted.push(sid),
    error: () => {},
  });

  assert.deepEqual(switched, []);
  assert.deepEqual(submitted, ["s1"]);
});

test("implementPlan: getAgent returns 'quick-message' → switchAgent(id, 'build') called then submit", async () => {
  const switched: string[] = [];
  const submitted: string[] = [];

  await implementPlan({
    sessionID: "s2",
    location: "/repo",
    plan: planA,
    create: async () => ({ id: "n" }),
    navigate: () => {},
    getAgent: () => "quick-message",
    switchAgent: async (id, agent) => switched.push(`${id}:${agent}`),
    submit: async (sid) => submitted.push(sid),
    error: () => {},
  });

  assert.deepEqual(switched, ["s2:build"]);
  assert.deepEqual(submitted, ["s2"]);
});

test("implementPlan: no sessionID → create + navigate + getAgent of new id + submit to created id", async () => {
  const created: Array<{ loc: string }> = [];
  const navigated: string[] = [];
  const agentChecked: string[] = [];
  const switched: string[] = [];
  const submitted: string[] = [];

  await implementPlan({
    sessionID: undefined,
    location: "/repo",
    plan: planA,
    create: async (loc) => { created.push({ loc }); return { id: "new-ses" }; },
    navigate: (id) => navigated.push(id),
    getAgent: (id) => { agentChecked.push(id); return undefined; },
    switchAgent: async (id, agent) => switched.push(`${id}:${agent}`),
    submit: async (sid) => submitted.push(sid),
    error: () => {},
  });

  assert.deepEqual(created, [{ loc: "/repo" }]);
  assert.deepEqual(navigated, ["new-ses"]);
  assert.deepEqual(agentChecked, ["new-ses"]);
  assert.deepEqual(switched, ["new-ses:build"]); // agent differs from "build"
  assert.deepEqual(submitted, ["new-ses"]);
});

test("implementPlan: custom agent option is respected", async () => {
  const switched: string[] = [];

  await implementPlan({
    sessionID: "s1",
    location: "/repo",
    plan: planA,
    agent: "architect",
    create: async () => ({ id: "n" }),
    navigate: () => {},
    getAgent: () => "quick-message", // different from "architect"
    switchAgent: async (id, agent) => switched.push(`${id}:${agent}`),
    submit: async () => {},
    error: () => {},
  });

  assert.deepEqual(switched, ["s1:architect"]);
});

test("implementPlan: create rejects → error toast containing 'Could not start implementation'", async () => {
  const messages: string[] = [];
  await implementPlan({
    sessionID: undefined,
    location: "/repo",
    plan: planA,
    create: async () => { throw new Error("no create"); },
    navigate: () => {},
    getAgent: () => "build",
    switchAgent: async () => {},
    submit: async () => {},
    error: (m) => messages.push(m),
  });
  assert.match(messages[0], /Could not start implementation/);
  assert.match(messages[0], /no create/);
});

test("implementPlan: assert submitted text === DEFAULT_IMPLEMENT_TEXT and file === planFile(plan)", async () => {
  const submitted: Array<{ text: string; file: unknown }> = [];

  await implementPlan({
    sessionID: "s1",
    location: "/repo",
    plan: planA,
    create: async () => ({ id: "n" }),
    navigate: () => {},
    getAgent: () => "build",
    switchAgent: async () => {},
    submit: async (_sid, text, file) => submitted.push({ text, file }),
    error: () => {},
  });

  assert.equal(submitted[0].text, DEFAULT_IMPLEMENT_TEXT);
  assert.deepEqual(submitted[0].file, planFile(planA));
});
