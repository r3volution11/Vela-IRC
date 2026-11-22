// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Tests for the Alfred workflow, with Node's own test runner:
//
//     node --test integrations/alfred/test/*.test.mjs
//
// scripts/vela.js is JavaScript for Automation, run by osascript. Here it
// runs in a Node vm with stand-ins for JXA's $, ObjC and Application, so no
// test ever sends Vela (or any app) an Apple event. On macOS, two more run
// the plain functions under osascript, to check they behave the same there,
// and compile dictionary-terms.applescript against a stand-in app that
// carries Vela/Vela.sdef.

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { describe, test } from "node:test";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const here = dirname(fileURLToPath(import.meta.url));
const workflow = join(here, "..");
const scriptPath = join(workflow, "scripts", "vela.js");
const source = readFileSync(scriptPath, "utf8");
const sdefPath = join(workflow, "..", "..", "Vela", "Vela.sdef");

const VELA = "io.github.r3volution11.Vela";
const VELA_DEV = "io.github.r3volution11.Vela.dev";

// ---------------------------------------------------------------- stand-ins

/** A stand-in for Vela's scripting interface, recording every call. */
function fakeVela({ conversations = [], errors = {}, markAllRead = 0, mismatchOnce = false } = {}) {
  const calls = [];
  let reads = 0;
  const column = (key, pick) => () => {
    calls.push(["get", key]);
    reads += 1;
    if (errors.list) throw errors.list;
    const values = conversations.map(pick);
    // The first read of "name" misses one, as if a channel closed mid-way.
    if (mismatchOnce && key === "name" && reads <= 8) values.pop();
    return values;
  };
  const elements = {
    id: column("id", (c) => c.id),
    name: column("name", (c) => c.name),
    networkName: column("networkName", (c) => c.network),
    kind: column("kind", (c) => (c.kind === "private" ? "private conversation" : "channel")),
    unreadCount: column("unreadCount", (c) => c.unread),
    mentionCount: column("mentionCount", (c) => c.mentions),
    joined: column("joined", (c) => c.joined),
    muted: column("muted", (c) => c.muted),
    byId: (id) => ({ specifier: "conversation", id }),
  };
  const command = (name) => (...args) => {
    calls.push([name, ...args]);
    if (errors[name]) throw errors[name];
    return name === "markAllRead" ? markAllRead : undefined;
  };
  const app = {
    get conversations() {
      return elements;
    },
    show: command("show"),
    catchUp: command("catchUp"),
    openRecap: command("openRecap"),
    markRead: command("markRead"),
    markAllRead: command("markAllRead"),
    sendMessage: command("sendMessage"),
    draftMessage: command("draftMessage"),
  };
  return { app, calls };
}

/** An error as JXA throws it for an Apple event that failed. */
function appleEventError(number, message) {
  return Object.assign(new Error(message), { errorNumber: number });
}

/**
 * Loads vela.js into a fresh vm context with stand-ins for JXA: `env` is
 * the process environment, `running` and `installed` the bundle ids macOS
 * knows about, and `vela` what Application() returns.
 */
function load({ env = {}, running = [], installed = [VELA, VELA_DEV], vela = fakeVela() } = {}) {
  const opened = [];
  const applications = [];
  const nsURL = (value) => ({ isNil: () => value == null, value });
  const context = vm.createContext({
    ObjC: { import() {}, deepUnwrap: (value) => value },
    $: {
      NSProcessInfo: { processInfo: { environment: env } },
      NSRunningApplication: {
        runningApplicationsWithBundleIdentifier: (id) => ({ count: running.includes(id) ? 1 : 0 }),
      },
      NSWorkspace: {
        sharedWorkspace: {
          URLForApplicationWithBundleIdentifier: (id) => nsURL(installed.includes(id) ? `/Applications/${id}.app` : null),
          openURL: (url) => {
            opened.push(url);
            return true;
          },
        },
      },
      NSURL: { URLWithString: (value) => value },
    },
    Application: (id) => {
      applications.push(id);
      return vela.app;
    },
  });
  vm.runInContext(source, context, { filename: scriptPath });
  const run = (...argv) => JSON.parse(context.run(argv));
  return { context, run, opened, applications, calls: vela.calls };
}

const plain = load().context;
const info = plain.appInfo({});

// A Libera.Chat and an OFTC, in sidebar order.
const fixture = [
  { id: "L/#vela", name: "#vela", network: "Libera.Chat", kind: "channel", unread: 14, mentions: 2, joined: true, muted: false },
  { id: "L/#swift", name: "#swift", network: "Libera.Chat", kind: "channel", unread: 40, mentions: 0, joined: true, muted: false },
  { id: "L/marisol", name: "marisol", network: "Libera.Chat", kind: "private", unread: 3, mentions: 3, joined: true, muted: false },
  { id: "L/#quiet", name: "#quiet", network: "Libera.Chat", kind: "channel", unread: 0, mentions: 0, joined: true, muted: false },
  { id: "O/#debian", name: "#debian", network: "OFTC", kind: "channel", unread: 99, mentions: 0, joined: true, muted: true },
  { id: "O/#left", name: "#left", network: "OFTC", kind: "channel", unread: 0, mentions: 0, joined: false, muted: false },
  { id: "O/#noisy", name: "#noisy", network: "OFTC", kind: "channel", unread: 7, mentions: 1, joined: true, muted: true },
  { id: "O/#ergo", name: "#ergo", network: "OFTC", kind: "channel", unread: 5, mentions: 0, joined: true, muted: false },
].map((c, order) => ({ ...c, order }));

/** Plain objects (vm objects have another realm's prototypes). */
const json = (value) => JSON.parse(JSON.stringify(value));

// ---------------------------------------------------------------- the apps

describe("app", () => {
  test("is Vela by default, Vela Dev when the configuration says so", () => {
    assert.equal(plain.appInfo({}).bundleID, VELA);
    assert.equal(plain.appInfo({ vela_app: VELA }).scheme, "vela");
    assert.equal(plain.appInfo({ vela_app: VELA_DEV }).bundleID, VELA_DEV);
    assert.equal(plain.appInfo({ vela_app: VELA_DEV }).scheme, "vela-dev");
    assert.equal(plain.appInfo({ vela_app: "dev" }).name, "Vela Dev");
  });

  test("links encode the conversation id", () => {
    assert.equal(plain.conversationLink(info, "1F2E/#vela"), "vela://open?id=1F2E%2F%23vela");
    assert.equal(plain.conversationLink(plain.appInfo({ vela_app: VELA_DEV }), "x"), "vela-dev://open?id=x");
  });

  test("search links encode the words and keep at most 500 characters", () => {
    assert.equal(plain.searchLink(info, "release notes & #vela"), "vela://search?q=release%20notes%20%26%20%23vela");
    const long = plain.searchLink(info, "é".repeat(600));
    assert.equal(decodeURIComponent(long.split("q=")[1]).length, 500);
  });
});

// ---------------------------------------------------------------- reading the list

describe("conversations from the dictionary", () => {
  test("map the columns, with kinds as JXA gives them", () => {
    const list = json(plain.conversationsFrom({
      id: ["a/#x", "a/bob"], name: ["#x", "bob"], networkName: ["Net", "Net"],
      kind: ["channel", "private conversation"], unreadCount: [1, 2], mentionCount: [0, 2],
      joined: [true, true], muted: [false, true],
    }));
    assert.deepEqual(list, [
      { id: "a/#x", name: "#x", network: "Net", kind: "channel", unread: 1, mentions: 0, joined: true, muted: false, order: 0 },
      { id: "a/bob", name: "bob", network: "Net", kind: "private", unread: 2, mentions: 2, joined: true, muted: true, order: 1 },
    ]);
  });

  test("are read again when the columns don't line up", () => {
    const columns = { id: ["a"], name: [], networkName: ["n"], kind: ["channel"], unreadCount: [0], mentionCount: [0], joined: [true], muted: [false] };
    assert.equal(plain.conversationsFrom(columns), null);
  });

  test("private conversations, however JXA spells the kind", () => {
    assert.equal(plain.kindOf("private conversation"), "private");
    assert.equal(plain.kindOf("privateConversation"), "private");
    assert.equal(plain.kindOf("VKpv"), "private");
    assert.equal(plain.kindOf("channel"), "channel");
  });
});

// ---------------------------------------------------------------- sorting

describe("sorting", () => {
  test("mentions first, then unread, then the rest in sidebar order", () => {
    const names = plain.sortConversations(fixture).map((c) => c.name);
    assert.deepEqual(json(names), [
      // Mentions: most mentions, then most unread.
      "marisol", "#vela", "#noisy",
      // Unread: most first. #debian is muted without mentions, so it's with the rest.
      "#swift", "#ergo",
      // The rest, in sidebar order.
      "#quiet", "#debian", "#left",
    ]);
  });

  test("ties keep sidebar order", () => {
    const tied = [
      { name: "b", unread: 3, mentions: 0, muted: false, order: 1 },
      { name: "a", unread: 3, mentions: 0, muted: false, order: 0 },
    ];
    assert.deepEqual(json(plain.sortConversations(tied).map((c) => c.name)), ["a", "b"]);
  });

  test("the busiest unread conversation is unmuted", () => {
    assert.equal(plain.busiestUnread(fixture).name, "#swift");
    assert.equal(plain.busiestUnread(fixture.filter((c) => c.muted)), null);
  });
});

// ---------------------------------------------------------------- results

describe("results", () => {
  const byName = (name) => fixture.find((c) => c.name === name);

  test("subtitles show the network and what's waiting", () => {
    assert.equal(plain.subtitleFor(byName("#vela")), "Libera.Chat · 2 mentions, 14 unread");
    assert.equal(plain.subtitleFor(byName("#swift")), "Libera.Chat · 40 unread");
    assert.equal(plain.subtitleFor(byName("marisol")), "Libera.Chat · 3 unread");
    assert.equal(plain.subtitleFor(byName("#quiet")), "Libera.Chat");
    assert.equal(plain.subtitleFor(byName("#debian")), "OFTC · 99 unread · muted");
    assert.equal(plain.subtitleFor(byName("#left")), "OFTC · not joined");
    assert.equal(plain.subtitleFor(byName("#noisy")), "OFTC · 1 mention, 7 unread · muted");
  });

  test("Alfred matches the name without #, the network's parts and what's waiting", () => {
    const words = plain.matchFor(byName("#vela")).split(" ");
    for (const word of ["#vela", "vela", "Libera.Chat", "Libera", "Chat", "channel", "unread", "mentions"]) {
      assert.ok(words.includes(word), `${word} in ${words}`);
    }
    assert.ok(!plain.matchFor(byName("#quiet")).includes("unread"));
    assert.ok(plain.matchFor(byName("marisol")).includes("private"));
  });

  test("a conversation's result: ↩ open, ⌘ catch up, ⌥ Recap, ⌃ write, ⇧ mark read", () => {
    const item = json(plain.conversationItem(byName("#vela"), info));
    assert.equal(item.title, "#vela");
    assert.equal(item.arg, "L/#vela");
    assert.equal(item.uid, "L/#vela");
    assert.equal(item.icon.path, "icons/channel-mention.png");
    assert.equal(item.text.copy, "vela://open?id=L%2F%23vela");
    assert.equal(item.variables.vela_action, "open");
    const actions = Object.fromEntries(Object.entries(item.mods).map(([key, mod]) => [key, mod.variables.vela_action]));
    assert.deepEqual(actions, { cmd: "catchup", alt: "recap", ctrl: "write", shift: "markread" });
    // A modifier's variables replace the item's, so each carries the conversation.
    for (const mod of Object.values(item.mods)) {
      assert.equal(mod.variables.conversation_id, "L/#vela");
      assert.equal(mod.variables.conversation_name, "#vela");
      assert.equal(mod.variables.network_name, "Libera.Chat");
    }
  });

  test("no writing to a channel you've left, and no mark read with nothing unread", () => {
    const left = json(plain.conversationItem(byName("#left"), info));
    assert.equal(left.mods.ctrl.valid, false);
    assert.match(left.mods.ctrl.subtitle, /not in #left/);
    assert.equal(left.mods.shift.valid, false);
    assert.equal(left.icon.path, "icons/channel-left.png");
    const query = json(plain.conversationItem(byName("marisol"), info));
    assert.equal(query.mods.ctrl.variables.vela_action, "write");
    assert.equal(query.mods.ctrl.variables.conversation_kind, "private");
    assert.equal(query.icon.path, "icons/private-mention.png");
  });

  test("the list: conversations in order, then the commands", () => {
    const feedback = json(plain.listFeedback(fixture, info));
    assert.equal(feedback.skipknowledge, true);
    assert.deepEqual(feedback.cache, { seconds: 5, loosereload: true });
    const titles = feedback.items.map((item) => item.title);
    assert.deepEqual(titles.slice(0, 3), ["marisol", "#vela", "#noisy"]);
    assert.deepEqual(titles.slice(-3), ["Catch Me Up", "Open Recap", "Mark All Read"]);
    const [catchUp, recap, markAll] = feedback.items.slice(-3);
    assert.equal(catchUp.valid, true);
    assert.match(catchUp.subtitle, /#swift on Libera\.Chat/);
    assert.equal(catchUp.variables.vela_action, "catchup");
    assert.equal(catchUp.variables.conversation_id, "");
    assert.equal(recap.variables.vela_action, "recap");
    // #debian is muted without mentions, so Vela doesn't count it.
    assert.equal(markAll.subtitle, "5 conversations have something unread");
    assert.equal(markAll.variables.vela_action, "markallread");
    for (const command of [catchUp, recap, markAll]) {
      for (const mod of Object.values(command.mods)) assert.equal(mod.valid, false);
    }
  });

  test("nothing unread: Catch Me Up and Mark All Read do nothing", () => {
    const quiet = fixture.map((c) => ({ ...c, unread: 0, mentions: 0 }));
    const items = json(plain.listFeedback(quiet, info).items);
    assert.equal(items.find((i) => i.title === "Catch Me Up").valid, false);
    assert.equal(items.find((i) => i.title === "Mark All Read").valid, false);
  });

  test("no conversations at all", () => {
    const feedback = json(plain.listFeedback([], info));
    assert.equal(feedback.items.length, 1);
    assert.equal(feedback.items[0].variables.vela_action, "launch");
    assert.equal(feedback.cache, undefined);
  });

  test("every icon a result names is in the workflow", () => {
    const paths = new Set();
    for (const item of plain.listFeedback(fixture, info).items) paths.add(item.icon.path);
    for (const c of fixture) paths.add(plain.iconFor({ ...c, mentions: 0 }).path);
    paths.add("icon.png");
    for (const path of paths) assert.ok(existsSync(join(workflow, path)), path);
  });
});

// ---------------------------------------------------------------- problems

describe("problems", () => {
  const first = (problem, app = info) => json(plain.problemFeedback(problem, app)).items[0];
  const dev = plain.appInfo({ vela_app: VELA_DEV });

  test("not running: ↩ opens Vela", () => {
    const item = first({ kind: "notRunning" });
    assert.equal(item.title, "Vela isn't running");
    assert.equal(item.variables.vela_action, "launch");
    assert.equal(first({ kind: "notRunning" }, dev).title, "Vela Dev isn't running");
  });

  test("not installed: velairc.app for Vela, nothing for Vela Dev", () => {
    assert.equal(first({ kind: "notInstalled" }).variables.vela_action, "website");
    assert.equal(first({ kind: "notInstalled" }, dev).valid, false);
  });

  test("Automation permission: ↩ opens Privacy & Security", () => {
    for (const number of [-1743, -1744]) {
      const item = first({ kind: "error", number, message: "Not authorized" });
      assert.equal(item.title, "Alfred isn't allowed to control Vela");
      assert.equal(item.variables.vela_action, "privacy");
    }
  });

  test("Vela quit, timed out, still starting, or too old", () => {
    assert.equal(first({ kind: "error", number: -600 }).title, "Vela isn't running");
    assert.match(first({ kind: "error", number: -1712 }).subtitle, /click Allow/);
    const starting = json(plain.problemFeedback({ kind: "error", number: 1010 }, info));
    assert.equal(starting.rerun, 1);
    assert.equal(starting.items[0].title, "Vela is still starting");
    const old = first({ kind: "error", number: -1708, message: "Message not understood." });
    assert.match(old.subtitle, /Vela 1\.5 or later/);
    assert.equal(old.variables.website_url, "https://velairc.app/guide/updates");
  });

  test("anything else shows Vela's message", () => {
    const item = first({ kind: "error", number: 42, message: "Error: Error: Something odd." });
    assert.equal(item.subtitle, "Something odd. (42)");
    assert.equal(item.valid, false);
  });
});

// ---------------------------------------------------------------- writing

describe("writing a message", () => {
  const env = { conversation_id: "L/#vela", conversation_name: "#vela", conversation_kind: "channel", network_name: "Libera.Chat" };

  test("asks for the text first", () => {
    const item = json(plain.writeFeedback("  ", env)).items[0];
    assert.equal(item.title, "Write to #vela");
    assert.equal(item.valid, false);
  });

  test("↩ sends, ⌘↩ drafts, each with the conversation", () => {
    const item = json(plain.writeFeedback("Hello all", env)).items[0];
    assert.equal(item.title, "Hello all");
    assert.equal(item.arg, "Hello all");
    assert.equal(item.variables.vela_action, "send");
    assert.equal(item.variables.conversation_id, "L/#vela");
    assert.equal(item.mods.cmd.variables.vela_action, "draft");
    assert.equal(item.mods.cmd.variables.conversation_id, "L/#vela");
    assert.equal(item.mods.ctrl.valid, false);
    assert.match(item.subtitle, /#vela on Libera\.Chat/);
    assert.equal(item.icon.path, "icons/channel.png");
  });

  test("says a slash is sent as text", () => {
    assert.match(json(plain.writeFeedback("/me waves", env)).items[0].subtitle, /not run as a command/);
  });

  test("a private conversation has the person's icon", () => {
    const item = json(plain.writeFeedback("hi", { ...env, conversation_name: "marisol", conversation_kind: "private" })).items[0];
    assert.equal(item.icon.path, "icons/private.png");
  });

  test("without a conversation", () => {
    assert.equal(json(plain.writeFeedback("hi", {})).items[0].title, "Choose a conversation first");
  });
});

// ---------------------------------------------------------------- notifications

describe("notifications", () => {
  const vela = { id: "L/#vela", name: "#vela", network: "Libera.Chat" };
  const note = (value) => json(value).alfredworkflow;

  test("Vela's own messages say what's wrong", () => {
    const result = note(plain.failureNotification("send", vela, { number: 1003, message: "Error: You're not in #vela on Libera.Chat." }, info));
    assert.equal(result.variables.notification_title, "Couldn't send to #vela");
    assert.equal(result.arg, "You're not in #vela on Libera.Chat.");
    const off = note(plain.failureNotification("catchup", vela, { number: 1007, message: "Catch me up is turned off in Vela's settings." }, info));
    assert.equal(off.variables.notification_title, "Couldn't catch you up on #vela");
    assert.equal(off.arg, "Catch me up is turned off in Vela's settings.");
  });

  test("macOS's errors are put in words", () => {
    assert.match(note(plain.failureNotification("open", vela, { number: -1743 }, info)).arg, /Privacy & Security → Automation/);
    assert.match(note(plain.failureNotification("open", vela, { number: -600 }, info)).arg, /isn't running/);
    assert.match(note(plain.failureNotification("open", vela, { number: -1712 }, info)).arg, /click Allow/);
    assert.equal(note(plain.failureNotification("open", vela, { number: -1728, message: "Can't get object." }, info)).arg,
      "Vela couldn't find #vela. It may have been closed.");
    assert.equal(note(plain.failureNotification("recap", null, { number: 1010 }, info)).variables.notification_title, "Couldn't open a Recap");
  });

  test("the AppleScript-only hint for long text becomes Alfred's", () => {
    const message = "That's 5 lines. The message box asks before sending more than 3; add “allowing multiple lines true” to send them.";
    assert.match(note(plain.failureNotification("send", vela, { number: 1005, message }, info)).arg, /⌘↩/);
  });

  test("what success says", () => {
    assert.deepEqual(note(plain.successNotification("send", vela, "Hello all")), { arg: "Hello all", variables: { notification_title: "Sent to #vela" } });
    assert.equal(note(plain.successNotification("markread", vela)).variables.notification_title, "Marked #vela read");
    assert.equal(note(plain.successNotification("markallread", null, 0)).arg, "Nothing was unread.");
    assert.equal(note(plain.successNotification("markallread", null, 1)).arg, "1 conversation had something unread.");
    assert.equal(note(plain.successNotification("markallread", null, 5)).arg, "5 conversations had something unread.");
    // Showing something brings Vela forward: no notification.
    for (const action of ["open", "catchup", "recap", "draft"]) {
      assert.equal(note(plain.successNotification(action, vela)).arg, "");
    }
  });

  test("long messages are shortened in the notification", () => {
    assert.equal(Array.from(note(plain.successNotification("send", vela, "x".repeat(500))).arg).length, 200);
  });
});

// ---------------------------------------------------------------- running it

describe("run, against a stand-in Vela", () => {
  const conversationsEnv = { vela_action: "send", conversation_id: "L/#vela", conversation_name: "#vela", network_name: "Libera.Chat" };

  test("list never launches Vela when it isn't running", () => {
    const { run, applications } = load({ running: [] });
    assert.equal(run("list").items[0].title, "Vela isn't running");
    assert.deepEqual(applications, []);
  });

  test("list says when Vela isn't installed", () => {
    const { run, applications } = load({ installed: [] });
    assert.equal(run("list").items[0].title, "Vela isn't installed");
    assert.deepEqual(applications, []);
  });

  test("list reads each property once, by bundle id", () => {
    const vela = fakeVela({ conversations: fixture });
    const { run, applications, calls } = load({ running: [VELA], vela });
    const feedback = run("list");
    assert.deepEqual(applications, [VELA]);
    assert.deepEqual(calls.map((c) => c[1]), ["id", "name", "networkName", "kind", "unreadCount", "mentionCount", "joined", "muted"]);
    assert.equal(feedback.items[0].title, "marisol");
    assert.equal(feedback.items.length, fixture.length + 3);
  });

  test("list reads again when a conversation comes or goes in between", () => {
    const vela = fakeVela({ conversations: fixture, mismatchOnce: true });
    const { run, calls } = load({ running: [VELA], vela });
    assert.equal(run("list").items.length, fixture.length + 3);
    assert.equal(calls.length, 16);
  });

  test("list turns Vela's errors into a result", () => {
    const vela = fakeVela({ conversations: fixture, errors: { list: appleEventError(-1743, "Not authorized to send Apple events to Vela.") } });
    const { run } = load({ running: [VELA], vela });
    assert.equal(run("list").items[0].variables.vela_action, "privacy");
  });

  test("Vela Dev, when the configuration says so", () => {
    const vela = fakeVela({ conversations: fixture });
    const { run, applications } = load({ env: { vela_app: VELA_DEV }, running: [VELA_DEV], vela });
    const feedback = run("list");
    assert.deepEqual(applications, [VELA_DEV]);
    assert.equal(feedback.items[0].text.copy, "vela-dev://open?id=L%2Fmarisol");
    // Vela itself running doesn't count.
    assert.equal(load({ env: { vela_app: VELA_DEV }, running: [VELA] }).run("list").items[0].title, "Vela Dev isn't running");
  });

  test("send: send message … to conversation id …", () => {
    const vela = fakeVela();
    const { run, calls } = load({ env: conversationsEnv, running: [VELA], vela });
    const result = run("act", "Hello all").alfredworkflow;
    assert.deepEqual(json(calls), [["sendMessage", "Hello all", { to: { specifier: "conversation", id: "L/#vela" } }]]);
    assert.equal(result.variables.notification_title, "Sent to #vela");
  });

  test("send: Vela's error becomes the notification", () => {
    const vela = fakeVela({ errors: { sendMessage: appleEventError(1003, "You're not in #vela on Libera.Chat.") } });
    const { run } = load({ env: conversationsEnv, running: [VELA], vela });
    assert.equal(run("act", "Hello").alfredworkflow.arg, "You're not in #vela on Libera.Chat.");
  });

  test("send: nothing to send never reaches Vela", () => {
    const { run, applications } = load({ env: conversationsEnv, running: [VELA] });
    assert.equal(run("act", "   ").alfredworkflow.arg, "There's nothing to send.");
    assert.deepEqual(applications, []);
  });

  test("each action sends its command", () => {
    const cases = [
      ["open", "x", [["show", { specifier: "conversation", id: "L/#vela" }]]],
      ["catchup", "", [["catchUp", { specifier: "conversation", id: "L/#vela" }]]],
      ["recap", "", [["openRecap", { specifier: "conversation", id: "L/#vela" }]]],
      ["markread", "", [["markRead", { specifier: "conversation", id: "L/#vela" }]]],
      ["draft", "Back in 5", [["draftMessage", "Back in 5", { to: { specifier: "conversation", id: "L/#vela" } }]]],
    ];
    for (const [action, text, expected] of cases) {
      const vela = fakeVela();
      const { run } = load({ env: { ...conversationsEnv, vela_action: action }, running: [VELA], vela });
      run("act", text);
      assert.deepEqual(json(vela.calls), expected, action);
    }
  });

  test("Catch Me Up and Open Recap without a conversation let Vela choose", () => {
    for (const [action, command] of [["catchup", "catchUp"], ["recap", "openRecap"]]) {
      const vela = fakeVela();
      const { run } = load({ env: { vela_action: action, conversation_id: "" }, running: [VELA], vela });
      run("act", action);
      assert.deepEqual(json(vela.calls), [[command]]);
    }
  });

  test("Mark All Read says how many", () => {
    const vela = fakeVela({ markAllRead: 4 });
    const { run } = load({ env: { vela_action: "markallread" }, running: [VELA], vela });
    assert.equal(run("act", "markallread").alfredworkflow.arg, "4 conversations had something unread.");
  });

  test("actions don't launch Vela either", () => {
    const { run, applications } = load({ env: { ...conversationsEnv, vela_action: "open" }, running: [] });
    assert.match(run("act", "L/#vela").alfredworkflow.arg, /isn't running/);
    assert.deepEqual(applications, []);
  });

  test("launch, privacy and website open links, not Apple events", () => {
    const launch = load({ env: { vela_action: "launch", vela_app: VELA_DEV } });
    launch.run("act", "launch");
    assert.deepEqual(launch.opened, ["vela-dev://"]);
    const privacy = load({ env: { vela_action: "privacy" } });
    privacy.run("act", "privacy");
    assert.match(privacy.opened[0], /^x-apple\.systempreferences:.*Privacy_Automation$/);
    const website = load({ env: { vela_action: "website", website_url: "https://velairc.app/guide/updates" } });
    website.run("act", "website");
    assert.deepEqual(website.opened, ["https://velairc.app/guide/updates"]);
    for (const loaded of [launch, privacy, website]) assert.deepEqual(loaded.applications, []);
  });

  test("search opens a link, even when Vela is closed", () => {
    const { run, opened, applications } = load({ running: [] });
    assert.equal(run("search", " release notes ").alfredworkflow.arg, "");
    assert.deepEqual(opened, ["vela://search?q=release%20notes"]);
    assert.deepEqual(applications, []);
    assert.match(load().run("search", "").alfredworkflow.arg, /Type the words/);
  });
});

// ---------------------------------------------------------------- the dictionary

describe("Vela's dictionary", () => {
  const sdef = readFileSync(sdefPath, "utf8");
  // JXA names a term in lower camel case: "network name" is networkName.
  const camel = (term) => term.replace(/ ([a-z])/g, (_, letter) => letter.toUpperCase());
  const classBody = (name) => sdef.match(new RegExp(`<class name="${name}"[^>]*>([\\s\\S]*?)</class>`))[1];
  const commandBody = (name) => sdef.match(new RegExp(`<command name="${name}"[^>]*>([\\s\\S]*?)</command>`))?.[1];
  const conversation = classBody("conversation");

  test("every property the list reads is a conversation property", () => {
    for (const [jxa, term] of vm.runInContext("COLUMNS", plain)) {
      assert.ok(conversation.includes(`<property name="${term}"`), `conversation has no "${term}"`);
      assert.equal(camel(term), jxa);
    }
  });

  test("every command the workflow sends is in the dictionary", () => {
    const commands = vm.runInContext("COMMANDS", plain);
    for (const [jxa, term] of Object.entries(commands)) {
      assert.ok(commandBody(term) !== undefined, `no command "${term}"`);
      assert.equal(camel(term), jxa);
    }
    for (const term of ["send message", "draft message"]) {
      assert.ok(commandBody(term).includes(`<parameter name="to"`), `${term} has no "to"`);
    }
  });

  test("commands on a conversation are ones it responds to", () => {
    for (const term of ["show", "catch up", "open recap", "mark read"]) {
      assert.ok(conversation.includes(`<responds-to command="${term}">`), `conversation doesn't respond to ${term}`);
    }
  });

  test("conversations have ids, which byId needs", () => {
    assert.match(conversation, /<property name="id" code="ID {2}"/);
    assert.match(sdef, /<enumerator name="private conversation" code="VKpv"/);
  });
});

// ---------------------------------------------------------------- the workflow

describe("info.plist", () => {
  const plist = JSON.parse(execFileSync("/usr/bin/plutil", ["-convert", "json", "-o", "-", join(workflow, "info.plist")], { encoding: "utf8" }));
  const objects = new Map(plist.objects.map((object) => [object.uid, object]));
  const connections = plist.connections;
  const outgoing = (uid) => connections[uid] ?? [];
  const byType = (type) => plist.objects.filter((object) => object.type === type);
  const MODIFIERS = { none: 0, cmd: 1048576, alt: 524288, ctrl: 262144, shift: 131072 };

  test("every connection goes to an object", () => {
    for (const [from, list] of Object.entries(connections)) {
      assert.ok(objects.has(from), from);
      for (const connection of list) assert.ok(objects.has(connection.destinationuid), connection.destinationuid);
    }
  });

  test("every script runs a command vela.js knows", () => {
    const known = new Set(["list", "write", "act", "search"]);
    for (const object of plist.objects) {
      const script = object.config?.script;
      if (!script) continue;
      const match = script.match(/^\/usr\/bin\/osascript -l JavaScript \.\/scripts\/vela\.js (\w+)/);
      assert.ok(match && known.has(match[1]), script);
      assert.equal(object.config.type, 11, "zsh --no-rcs");
      assert.equal(object.config.scriptargtype, 1, "the argument as $1");
    }
  });

  test("the vela keyword: Alfred filters, each modifier is connected", () => {
    const list = byType("alfred.workflow.input.scriptfilter").find((o) => o.config.keyword === "{var:vela_keyword}");
    assert.ok(list);
    assert.equal(list.config.alfredfiltersresults, true);
    const act = plist.objects.find((o) => o.config?.script?.includes("vela.js act"));
    const routes = Object.fromEntries(outgoing(list.uid).map((c) => [c.modifiers, objects.get(c.destinationuid)]));
    for (const key of ["none", "cmd", "alt", "shift"]) assert.equal(routes[MODIFIERS[key]], act, key);
    // ⌃: an empty argument, then the write step, with Alfred kept open.
    const ctrl = outgoing(list.uid).find((c) => c.modifiers === MODIFIERS.ctrl);
    assert.equal(ctrl.vitoclose, true);
    const argument = objects.get(ctrl.destinationuid);
    assert.equal(argument.type, "alfred.workflow.utility.argument");
    assert.equal(argument.config.argument, "");
    const write = objects.get(outgoing(argument.uid)[0].destinationuid);
    assert.match(write.config.script, /vela\.js write/);
    assert.equal(write.config.alfredfiltersresults, false);
    const writeRoutes = outgoing(write.uid).map((c) => [c.modifiers, objects.get(c.destinationuid)]);
    assert.deepEqual(writeRoutes.map(([m]) => m).sort(), [0, MODIFIERS.cmd].sort());
    for (const [, destination] of writeRoutes) assert.equal(destination, act);
    // The notification shows only when there's something to say.
    const notification = objects.get(outgoing(act.uid)[0].destinationuid);
    assert.equal(notification.type, "alfred.workflow.output.notification");
    assert.equal(notification.config.onlyshowifquerypopulated, true);
    assert.equal(notification.config.title, "{var:notification_title}");
  });

  test("search: a keyword and a Universal Action", () => {
    const search = plist.objects.find((o) => o.config?.script?.includes("vela.js search"));
    const sources = Object.entries(connections)
      .filter(([, list]) => list.some((c) => c.destinationuid === search.uid))
      .map(([uid]) => objects.get(uid).type).sort();
    assert.deepEqual(sources, ["alfred.workflow.input.keyword", "alfred.workflow.trigger.universalaction"]);
  });

  test("the configuration: keywords of three letters or more, and the app", () => {
    const config = Object.fromEntries(plist.userconfigurationconfig.map((item) => [item.variable, item]));
    assert.ok(config.vela_keyword.config.default.length >= 3);
    assert.ok(config.search_keyword.config.default.length >= 3);
    assert.equal(config.vela_app.config.default, VELA);
    assert.deepEqual(config.vela_app.config.pairs.map(([, id]) => id), [VELA, VELA_DEV]);
    for (const [, id] of config.vela_app.config.pairs) assert.equal(plain.appInfo({ vela_app: id }).bundleID, id);
    const keywords = plist.objects.map((o) => o.config?.keyword).filter(Boolean);
    assert.deepEqual(keywords.sort(), ["{var:search_keyword}", "{var:vela_keyword}"]);
  });

  test("the workflow's icon is at least 256 × 256", () => {
    const png = readFileSync(join(workflow, "icon.png"));
    assert.ok(png.readUInt32BE(16) >= 256 && png.readUInt32BE(20) >= 256);
  });
});

// ---------------------------------------------------------------- under osascript

describe("under osascript", { skip: process.platform !== "darwin" && "osascript is macOS only" }, () => {
  test("the plain functions give the same results as in Node", () => {
    // vela.js with its run() replaced by one that only calls plain
    // functions: osascript runs it without sending any app an event.
    const probe = `
      function run() {
        const fixture = ${JSON.stringify(fixture)};
        const info = appInfo({});
        const env = { conversation_id: "L/#vela", conversation_name: "#vela", conversation_kind: "channel", network_name: "Libera.Chat" };
        return JSON.stringify({
          list: listFeedback(fixture, info),
          write: writeFeedback("/me waves", env),
          problem: problemFeedback({ kind: "error", number: 1010 }, info),
          failure: failureNotification("send", { name: "#vela" }, { number: -1728, message: "Can't get object." }, info),
          search: searchLink(info, "é & #vela"),
        });
      }`;
    const folder = mkdtempSync(join(tmpdir(), "vela-alfred-"));
    try {
      const file = join(folder, "probe.js");
      writeFileSync(file, `${source}\n${probe}`);
      const fromOsascript = JSON.parse(execFileSync("/usr/bin/osascript", ["-l", "JavaScript", file], { encoding: "utf8" }));
      const context = load().context;
      vm.runInContext(probe, context);
      assert.deepEqual(fromOsascript, JSON.parse(context.run([])));
    } finally {
      rmSync(folder, { recursive: true, force: true });
    }
  });

  test("the AppleScript for each Apple event compiles against Vela's dictionary", () => {
    // A stand-in with Vela.sdef and nothing to run: osacompile reads its
    // dictionary from the bundle, and nothing launches or asks permission.
    const folder = mkdtempSync(join(tmpdir(), "vela-alfred-terms-"));
    try {
      const standIn = join(folder, "VelaTerms.app");
      mkdirSync(join(standIn, "Contents", "Resources"), { recursive: true });
      copyFileSync(sdefPath, join(standIn, "Contents", "Resources", "Vela.sdef"));
      writeFileSync(join(standIn, "Contents", "Info.plist"), `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.example.vela-alfred-terms</string>
<key>CFBundleName</key><string>VelaTerms</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSAppleScriptEnabled</key><true/>
<key>OSAScriptingDefinition</key><string>Vela.sdef</string>
</dict></plist>
`);
      const compile = (text, name) => {
        const file = join(folder, `${name}.applescript`);
        writeFileSync(file, text.replaceAll("VELA_TERMS_APP", standIn));
        execFileSync("/usr/bin/osacompile", ["-o", join(folder, `${name}.scpt`), file], { stdio: "pipe" });
        return execFileSync("/usr/bin/osadecompile", [join(folder, `${name}.scpt`)], { encoding: "utf8" });
      };
      const terms = readFileSync(join(here, "dictionary-terms.applescript"), "utf8");
      // osadecompile can't find the stand-in by the name the script keeps,
      // so it shows the raw codes each term compiled to: they must be Vela's.
      const decompiled = compile(terms, "terms");
      for (const code of [
        "every «class VCnv»", "«class VNtN» of every", "«class VKnd» of every", "«class VUnr» of every",
        "«class VMen» of every", "«class VJnd» of every", "«class VMut» of every", "«class VCnv» id conversationID",
        "«event Velashow» target", "«event VelaCtUp» target", "«event VelaRcap» target", "«event VelaMkRd» target",
        "set counted to «event VelaMkAl»", "«event VelaSend» messageText given «class VsTo»:target",
        "«event VelaDrft» messageText given «class VdTo»:target", "«constant VCkdVKch», «constant VCkdVKpv»",
      ]) {
        assert.ok(decompiled.includes(code), `${code} not in:\n${decompiled}`);
      }
      assert.ok(!decompiled.includes("«class VNet»"), "a variable is named like one of Vela's terms");
      // A term that isn't in the dictionary doesn't compile, so the check means something.
      const misspelled = terms.replace("set counted to mark all read", "set counted to mark everything read");
      assert.throws(() => compile(misspelled, "misspelled"));
    } finally {
      rmSync(folder, { recursive: true, force: true });
    }
  });
});
