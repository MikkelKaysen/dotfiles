import { readdir, readFile, stat, unlink } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { Plugin } from "@opencode/plugin/tui";
import {
  attachPlan,
  implementPlan,
  parsePlanTitle,
  pickPlan,
  planDisplayName,
  removePlan,
  type PlanEntry,
} from "./plan-picker.ts";

const PLANS_DIR = join(homedir(), ".opencode", "plan");

/** Lists .md plans in ~/.opencode/plan, taking titles from the first heading. */
async function listPlans(): Promise<PlanEntry[]> {
  const dirents = await readdir(PLANS_DIR, { withFileTypes: true });
  const files = dirents.filter((d) => d.isFile() && d.name.endsWith(".md"));
  return Promise.all(
    files.map(async (d) => {
      const path = join(PLANS_DIR, d.name);
      const [s, head] = await Promise.all([
        stat(path),
        readFile(path, "utf8")
          .then((content) => content.slice(0, 4096))
          .catch(() => ""),
      ]);
      return { path, name: d.name, title: parsePlanTitle(head), mtimeMs: s.mtimeMs };
    }),
  );
}

export default Plugin.define({
  id: "plan-commands",
  setup(ctx) {
    const pick = () =>
      pickPlan({
        list: listPlans,
        select: (choices) =>
          ctx.ui.dialog.select({
            title: "Choose a plan",
            placeholder: "Search plans…",
            options: choices,
          }),
        emptyMessage: `No plans found in ${ctx.ui.format.path(PLANS_DIR)}.`,
        toast: (message) => ctx.ui.toast.show({ title: "Plan", message, variant: "error" }),
      });

    const locationOf = () => ctx.location?.directory ?? ctx.data.location.default().directory;

    const createSession = (directory: string) =>
      ctx.client.session.create({ location: { directory } });

    const navigateTo = (sessionID: string) =>
      ctx.ui.router.navigate({ type: "session", sessionID });

    const submit = (
      sessionID: string,
      text: string,
      file: { uri: string; name: string; description: string },
    ) => ctx.client.session.prompt({ sessionID, text, files: [file], delivery: "steer" });

    ctx.keymap.layer(() => ({
      mode: "global",
      commands: [
        {
          id: "plan-commands.existing",
          title: "Attach a plan",
          description: `Pick a plan from ${ctx.ui.format.path(PLANS_DIR)} and attach it to this session`,
          group: "Plan",
          bind: false,
          palette: true,
          slash: { name: "plan:existing" },
          run: async () => {
            const route = ctx.ui.router.current();
            const sessionID = route.type === "session" ? route.sessionID : undefined;
            const plan = await pick();
            if (!plan) return;
            await attachPlan({
              sessionID,
              location: locationOf(),
              plan,
              prompt: (title) => ctx.ui.dialog.prompt({ title }),
              create: createSession,
              navigate: navigateTo,
              submit,
              toast: (message) => ctx.ui.toast.show({ title: "Plan", message, variant: "error" }),
            });
          },
        },
        {
          id: "plan-commands.remove",
          title: "Delete a plan",
          description: `Pick a plan from ${ctx.ui.format.path(PLANS_DIR)} and delete it`,
          group: "Plan",
          bind: false,
          palette: true,
          slash: { name: "plan:remove" },
          run: async () => {
            const plan = await pick();
            if (!plan) return;
            await removePlan({
              plan,
              confirm: () =>
                ctx.ui.dialog.confirm({
                  title: "Delete plan",
                  message: `Delete "${planDisplayName(plan)}" from ${ctx.ui.format.path(PLANS_DIR)}/${plan.name}? This cannot be undone.`,
                  label: { confirm: "Delete", cancel: "Cancel" },
                }),
              unlink: (path) => unlink(path),
              success: (message) =>
                ctx.ui.toast.show({ title: "Plan", message, variant: "success" }),
              error: (message) => ctx.ui.toast.show({ title: "Plan", message, variant: "error" }),
            });
          },
        },
        {
          id: "plan-commands.implement",
          title: "Implement a plan",
          description: `Pick a plan from ${ctx.ui.format.path(PLANS_DIR)} and start implementing it`,
          group: "Plan",
          bind: false,
          palette: true,
          slash: { name: "plan:implement" },
          run: async () => {
            const route = ctx.ui.router.current();
            const sessionID = route.type === "session" ? route.sessionID : undefined;
            const plan = await pick();
            if (!plan) return;
            await implementPlan({
              sessionID,
              location: locationOf(),
              plan,
              create: createSession,
              navigate: navigateTo,
              getAgent: (id) => ctx.data.session.get(id)?.agent,
              switchAgent: (id, agent) =>
                ctx.client.session.switchAgent({ sessionID: id, agent }),
              submit,
              error: (message) =>
                ctx.ui.toast.show({ title: "Implement", message, variant: "error" }),
            });
          },
        },
      ],
    }));
  },
});
