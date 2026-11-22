// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// Vela for Alfred: one JavaScript for Automation (JXA) script for every
// step of the workflow. Alfred runs it from the workflow's folder as
//
//     /usr/bin/osascript -l JavaScript ./scripts/vela.js <command> [argument]
//
// Commands:
//   list          The vela keyword's Script Filter: your channels and private
//                 conversations (mentions first, then unread, then the rest),
//                 then Catch Me Up, Open Recap and Mark All Read. Alfred
//                 filters them as you type.
//   write <text>  The step after ⌃↩: the message you're typing, which ↩
//                 sends and ⌘↩ puts in Vela's message box instead.
//   act [text]    Does what the chosen result asks, from the variables it
//                 set: vela_action (open, catchup, recap, markread,
//                 markallread, send, draft, launch, privacy, website) and
//                 conversation_id. Prints {"alfredworkflow": …} with what the
//                 notification after it says, or nothing to say.
//   search <text> Opens Vela's message search on the words, with a vela://
//                 link: it needs no permission, and opens Vela if it's closed.
//
// It talks to Vela through Vela's AppleScript dictionary (Vela/Vela.sdef in
// Vela's repository; velairc.app/guide/automation), by bundle id, so the
// app's name doesn't matter. The Workflow's Configuration picks Vela or
// Vela Dev (vela_app). Listing never launches Vela: macOS is asked whether
// it's running first, which sends Vela nothing. Reading the list takes one
// Apple event per property, however many conversations you have.
//
// Everything above "JXA only" is plain JavaScript, which
// integrations/alfred/test/vela.test.mjs runs in Node, without Vela.

"use strict";

// ---------------------------------------------------------------- the apps

const APPS = {
  vela: { bundleID: "io.github.r3volution11.Vela", name: "Vela", scheme: "vela" },
  dev: { bundleID: "io.github.r3volution11.Vela.dev", name: "Vela Dev", scheme: "vela-dev" },
};

/** Vela or Vela Dev, from the Workflow's Configuration (vela_app). */
function appInfo(env) {
  const value = String((env && env.vela_app) || "").trim().toLowerCase();
  const dev = [APPS.dev.bundleID.toLowerCase(), "dev", "vela-dev", "vela dev"].includes(value);
  return dev ? APPS.dev : APPS.vela;
}

/** A conversation's vela:// link, which shows it without asking for permission. */
function conversationLink(info, id) {
  return `${info.scheme}://open?id=${encodeURIComponent(id)}`;
}

/** Vela's message search on `text`, as a link. Vela takes at most 500 characters. */
function searchLink(info, text) {
  return `${info.scheme}://search?q=${encodeURIComponent(Array.from(text).slice(0, 500).join(""))}`;
}

const PRIVACY_URL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation";
const UPDATES_URL = "https://velairc.app/guide/updates";
const INSTALL_URL = "https://velairc.app/guide/install";

// ---------------------------------------------------------------- the dictionary

// The conversation properties the list reads, as JXA names them, with their
// AppleScript terms (test/vela.test.mjs checks each against Vela.sdef).
const COLUMNS = [
  ["id", "id"],
  ["name", "name"],
  ["networkName", "network name"],
  ["kind", "kind"],
  ["unreadCount", "unread count"],
  ["mentionCount", "mention count"],
  ["joined", "joined"],
  ["muted", "muted"],
];

// The commands the workflow sends, and their parameters, likewise.
const COMMANDS = {
  show: "show",
  catchUp: "catch up",
  openRecap: "open recap",
  markRead: "mark read",
  markAllRead: "mark all read",
  sendMessage: "send message",
  draftMessage: "draft message",
};
const PARAMETERS = { to: "to" };

/** "channel" or "private", from what JXA gives for `kind`. */
function kindOf(value) {
  const text = String(value || "").toLowerCase().replace(/\s+/g, "");
  return text === "privateconversation" || text === "vkpv" ? "private" : "channel";
}

/**
 * Conversations from the list's columns (one array per property, in sidebar
 * order), or null if they don't line up: a conversation came or went between
 * two Apple events, so the list should be read again.
 */
function conversationsFrom(columns) {
  const ids = columns.id || [];
  for (const [key] of COLUMNS) {
    if (!Array.isArray(columns[key]) || columns[key].length !== ids.length) return null;
  }
  return ids.map((id, order) => ({
    id: String(id),
    name: String(columns.name[order]),
    network: String(columns.networkName[order]),
    kind: kindOf(columns.kind[order]),
    unread: Number(columns.unreadCount[order]) || 0,
    mentions: Number(columns.mentionCount[order]) || 0,
    joined: columns.joined[order] === true,
    muted: columns.muted[order] === true,
    order,
  }));
}

// ---------------------------------------------------------------- sorting

/**
 * "mentions", "unread" or "other". A muted conversation counts as unread
 * only when it mentions you, as Vela's `unread conversations` has it.
 */
function bucketOf(conversation) {
  if (conversation.mentions > 0) return "mentions";
  if (conversation.unread > 0 && !conversation.muted) return "unread";
  return "other";
}

const BUCKET_RANK = { mentions: 0, unread: 1, other: 2 };

/**
 * Mentions first (most mentions, then most unread), then unread (most
 * first), then the rest, each in Vela's sidebar order where they tie.
 */
function sortConversations(conversations) {
  return conversations.slice().sort((a, b) => {
    const bucketA = bucketOf(a);
    const bucketB = bucketOf(b);
    if (bucketA !== bucketB) return BUCKET_RANK[bucketA] - BUCKET_RANK[bucketB];
    if (bucketA === "mentions" && a.mentions !== b.mentions) return b.mentions - a.mentions;
    if (bucketA !== "other" && a.unread !== b.unread) return b.unread - a.unread;
    return a.order - b.order;
  });
}

/** The unmuted conversation with the most unread messages: what `catch up` picks. */
function busiestUnread(conversations) {
  let busiest = null;
  for (const conversation of conversations) {
    if (conversation.muted || conversation.unread <= 0) continue;
    if (!busiest || conversation.unread > busiest.unread) busiest = conversation;
  }
  return busiest;
}

/** Whether anything in `conversations` is unread, as `mark all read` counts it. */
function hasUnread(conversation) {
  return conversation.unread > 0 || conversation.mentions > 0;
}

// ---------------------------------------------------------------- results

function plural(count, one, many) {
  return `${count} ${count === 1 ? one : many}`;
}

/**
 * The network and what's waiting: "Libera.Chat · 2 mentions, 14 unread".
 * In a private conversation every new message is a mention, so it says
 * only how many are unread.
 */
function subtitleFor(conversation) {
  const parts = [conversation.network];
  const counts = [];
  if (conversation.kind === "private") {
    const waiting = Math.max(conversation.unread, conversation.mentions);
    if (waiting > 0) counts.push(`${waiting} unread`);
  } else {
    if (conversation.mentions > 0) counts.push(plural(conversation.mentions, "mention", "mentions"));
    if (conversation.unread > 0) counts.push(`${conversation.unread} unread`);
  }
  if (counts.length) parts.push(counts.join(", "));
  if (conversation.muted) parts.push("muted");
  if (conversation.kind === "channel" && !conversation.joined) parts.push("not joined");
  return parts.filter(Boolean).join(" · ");
}

/**
 * The words Alfred matches what you type against: the name with and without
 * its "#", the network and its parts, the kind, and "unread", "mentions" or
 * "muted", so `vela unread` lists what's waiting.
 */
function matchFor(conversation) {
  const words = [conversation.name, conversation.name.replace(/^[#&!+]+/, ""), conversation.network];
  words.push(...conversation.network.split(/[^\p{L}\p{N}]+/u));
  words.push(conversation.kind === "private" ? "private dm" : "channel");
  if (hasUnread(conversation)) words.push("unread");
  if (conversation.mentions > 0) words.push("mentions");
  if (conversation.muted) words.push("muted");
  const seen = new Set();
  return words.filter((word) => {
    const key = word.toLowerCase();
    if (!word || seen.has(key)) return false;
    seen.add(key);
    return true;
  }).join(" ");
}

function iconFor(conversation) {
  if (conversation.kind === "private") {
    return { path: conversation.mentions > 0 ? "icons/private-mention.png" : "icons/private.png" };
  }
  if (!conversation.joined) return { path: "icons/channel-left.png" };
  return { path: conversation.mentions > 0 ? "icons/channel-mention.png" : "icons/channel.png" };
}

/** What every action of a conversation passes on (a modifier's variables replace the item's). */
function variablesFor(action, conversation) {
  return {
    vela_action: action,
    conversation_id: conversation ? conversation.id : "",
    conversation_name: conversation ? conversation.name : "",
    conversation_kind: conversation ? conversation.kind : "",
    network_name: conversation ? conversation.network : "",
  };
}

/** A modifier that does nothing on this result, saying why. */
function unavailable(subtitle) {
  return { valid: false, subtitle };
}

/** No modifiers: for results that only have ↩. */
function noModifiers(subtitle) {
  const mod = unavailable(subtitle);
  return { cmd: mod, alt: mod, ctrl: mod, shift: mod };
}

/** A conversation's result: ↩ open, ⌘ Catch me up, ⌥ Recap, ⌃ write, ⇧ mark read. */
function conversationItem(conversation, info) {
  const name = conversation.name;
  const writable = conversation.kind === "private" || conversation.joined;
  return {
    uid: conversation.id,
    title: name,
    subtitle: subtitleFor(conversation),
    arg: conversation.id,
    match: matchFor(conversation),
    autocomplete: name,
    icon: iconFor(conversation),
    text: { copy: conversationLink(info, conversation.id), largetype: `${name} on ${conversation.network}` },
    variables: variablesFor("open", conversation),
    mods: {
      cmd: { arg: conversation.id, subtitle: `Catch me up on ${name}`, variables: variablesFor("catchup", conversation) },
      alt: { arg: conversation.id, subtitle: `Open a Recap of ${name}`, variables: variablesFor("recap", conversation) },
      ctrl: writable
        ? { arg: conversation.id, subtitle: `Write a message to ${name}…`, variables: variablesFor("write", conversation) }
        : unavailable(`You're not in ${name}: join it in ${info.name} to write there`),
      shift: hasUnread(conversation)
        ? { arg: conversation.id, subtitle: `Mark ${name} read`, variables: variablesFor("markread", conversation) }
        : unavailable(`Nothing unread in ${name}`),
    },
  };
}

/** Catch Me Up, Open Recap and Mark All Read, after the conversations. */
function commandItems(conversations, info) {
  const busiest = busiestUnread(conversations);
  const unreadCount = conversations.filter((c) => (c.muted ? c.mentions > 0 : hasUnread(c))).length;
  const catchUp = {
    uid: "vela-catch-up",
    title: "Catch Me Up",
    subtitle: busiest
      ? `What you missed in ${busiest.name} on ${busiest.network}, your busiest unread conversation`
      : "Nothing unread to catch up on",
    arg: "catchup",
    valid: Boolean(busiest),
    match: "catch me up summary summarize missed",
    icon: { path: "icon.png" },
    variables: variablesFor("catchup", null),
    mods: noModifiers("Catch Me Up has no other actions"),
  };
  const recap = {
    uid: "vela-recap",
    title: "Open Recap",
    subtitle: "A report of what was said on every network since you last read",
    arg: "recap",
    match: "open recap report everything",
    icon: { path: "icon.png" },
    variables: variablesFor("recap", null),
    mods: noModifiers("Open Recap has no other actions"),
  };
  const markAll = {
    uid: "vela-mark-all-read",
    title: "Mark All Read",
    subtitle: unreadCount
      ? `${plural(unreadCount, "conversation has", "conversations have")} something unread`
      : `Nothing is unread in ${info.name}`,
    arg: "markallread",
    valid: unreadCount > 0,
    match: "mark all read clear everything",
    icon: { path: "icon.png" },
    variables: variablesFor("markallread", null),
    mods: noModifiers("Mark All Read has no other actions"),
  };
  return [catchUp, recap, markAll];
}

/** The vela keyword's results, from the conversations Vela listed. */
function listFeedback(conversations, info) {
  if (!conversations.length) {
    return {
      items: [{
        title: "No channels or conversations yet",
        subtitle: `Add a network or join a channel in ${info.name}. ↩ shows ${info.name}`,
        arg: "launch",
        icon: { path: "icon.png" },
        variables: variablesFor("launch", null),
        mods: noModifiers(`↩ shows ${info.name}`),
      }],
    };
  }
  return {
    // Keep this order (mentions, unread, the rest) rather than Alfred's
    // learned one, and show what Alfred saw last at once, reading again
    // behind it when it's more than a few seconds old.
    skipknowledge: true,
    cache: { seconds: 5, loosereload: true },
    items: [...sortConversations(conversations).map((c) => conversationItem(c, info)), ...commandItems(conversations, info)],
  };
}

// ---------------------------------------------------------------- problems

/** The text of an error, without the "Error: " JXA puts before it. */
function cleanMessage(message) {
  return String(message || "").replace(/^(\s*Error:\s*)+/, "").trim();
}

/**
 * The result to show instead of the list: Vela isn't running, isn't
 * installed, can't be scripted yet, or answered with an error.
 */
function problemFeedback(problem, info) {
  const item = (fields) => ({ icon: { path: "icon.png" }, mods: noModifiers(fields.subtitle), ...fields });
  switch (problem.kind) {
    case "notRunning":
      return { items: [item({
        title: `${info.name} isn't running`,
        subtitle: `↩ Open ${info.name} to see your channels and conversations`,
        arg: "launch",
        variables: variablesFor("launch", null),
      })] };
    case "notInstalled":
      return { items: [item({
        title: `${info.name} isn't installed`,
        subtitle: info === APPS.dev
          ? "Build it with scripts/run.sh --dev, or choose Vela in the Workflow's Configuration"
          : "↩ Get Vela at velairc.app",
        arg: "website",
        valid: info !== APPS.dev,
        variables: { ...variablesFor("website", null), website_url: INSTALL_URL },
      })] };
    default:
      break;
  }
  const number = problem.number;
  if (number === -1743 || number === -1744) {
    return { items: [item({
      title: `Alfred isn't allowed to control ${info.name}`,
      subtitle: `↩ Open Privacy & Security → Automation, and turn on ${info.name} under Alfred`,
      arg: "privacy",
      variables: variablesFor("privacy", null),
    })] };
  }
  if (number === -600 || number === -609) return problemFeedback({ kind: "notRunning" }, info);
  if (number === -1712) {
    return { items: [item({
      title: `${info.name} didn't answer`,
      subtitle: `If macOS is asking whether Alfred may control ${info.name}, click Allow, then try again`,
      valid: false,
    })] };
  }
  if (number === 1010) {
    // Vela was just opened: ask again every second until it's ready.
    return { rerun: 1, items: [item({
      title: `${info.name} is still starting`,
      subtitle: "Your channels and conversations will be here in a moment",
      valid: false,
    })] };
  }
  if (number === -1708 || number === -1728 || number === -10000) {
    return { items: [item({
      title: `This ${info.name} can't talk to Alfred yet`,
      subtitle: "The workflow needs Vela 1.5 or later. ↩ How to update",
      arg: "website",
      variables: { ...variablesFor("website", null), website_url: UPDATES_URL },
    })] };
  }
  const detail = cleanMessage(problem.message);
  return { items: [item({
    title: `${info.name} couldn't list your conversations`,
    subtitle: detail ? `${detail}${number != null ? ` (${number})` : ""}` : `Error ${number}`,
    valid: false,
  })] };
}

// ---------------------------------------------------------------- writing

/** The step after ⌃↩: what you're typing, to send (↩) or draft in Vela (⌘↩). */
function writeFeedback(text, env) {
  const info = appInfo(env);
  const conversation = {
    id: String(env.conversation_id || ""),
    name: String(env.conversation_name || ""),
    network: String(env.network_name || ""),
    kind: env.conversation_kind === "private" ? "private" : "channel",
    joined: true,
    mentions: 0,
  };
  const icon = iconFor(conversation);
  if (!conversation.id) {
    return { items: [{
      title: "Choose a conversation first",
      subtitle: "Type vela, pick a channel or private conversation and press ⌃↩",
      valid: false,
      icon: { path: "icon.png" },
      mods: noModifiers("Choose a conversation first"),
    }] };
  }
  const where = conversation.network ? `${conversation.name} on ${conversation.network}` : conversation.name;
  if (!text.trim()) {
    return { items: [{
      title: `Write to ${conversation.name}`,
      subtitle: `Type your message, then ↩ sends it to ${where}`,
      valid: false,
      icon,
      mods: noModifiers("Type your message first"),
    }] };
  }
  const asText = text.trim().startsWith("/") ? " (as text: it's not run as a command)" : "";
  const busy = noModifiers("↩ sends it, ⌘↩ puts it in the message box");
  return { items: [{
    title: text,
    subtitle: `↩ Send to ${where}${asText} · ⌘↩ Put it in ${info.name}'s message box`,
    arg: text,
    icon,
    text: { copy: text, largetype: text },
    variables: variablesFor("send", conversation),
    mods: {
      ...busy,
      cmd: {
        arg: text,
        subtitle: `Put it in ${conversation.name}'s message box in ${info.name}, without sending it`,
        variables: variablesFor("draft", conversation),
      },
    },
  }] };
}

// ---------------------------------------------------------------- actions

/** What the Run Script passes on: the notification's text and title, if any. */
function notification(title, text) {
  return { alfredworkflow: { arg: text || "", variables: { notification_title: title || "" } } };
}

const QUIET = notification("", "");

function shorten(text, limit) {
  const characters = Array.from(String(text));
  return characters.length > limit ? `${characters.slice(0, limit - 1).join("")}…` : characters.join("");
}

/** The notification's title when `action` fails. */
function failureTitle(action, name) {
  switch (action) {
    case "open": return name ? `Couldn't show ${name}` : "Couldn't show that conversation";
    case "catchup": return name ? `Couldn't catch you up on ${name}` : "Couldn't catch you up";
    case "recap": return "Couldn't open a Recap";
    case "markread": return name ? `Couldn't mark ${name} read` : "Couldn't mark that read";
    case "markallread": return "Couldn't mark everything read";
    case "send": return name ? `Couldn't send to ${name}` : "Couldn't send that";
    case "draft": return name ? `Couldn't draft in ${name}` : "Couldn't draft that";
    default: return "Vela couldn't do that";
  }
}

/**
 * A failed action's notification: Vela's own message, which already says
 * what's wrong in words ("You're not in #vela on Libera.Chat."), or ours
 * for macOS's errors. Vela's numbers are in velairc.app/guide/automation#errors.
 */
function failureNotification(action, conversation, error, info) {
  const number = error && typeof error.number === "number" ? error.number : null;
  const message = cleanMessage(error && error.message);
  const name = conversation && conversation.name;
  let text;
  switch (number) {
    case -1743:
    case -1744:
      text = `Alfred isn't allowed to control ${info.name}. Turn it on in System Settings → Privacy & Security → Automation.`;
      break;
    case -600:
    case -609:
      text = `${info.name} isn't running. Open it, then try again.`;
      break;
    case -1712:
      text = `${info.name} didn't answer in time. If macOS is asking whether Alfred may control ${info.name}, click Allow.`;
      break;
    case -1728:
      text = message && !/^Can.t get/i.test(message)
        ? message
        : `${info.name} couldn't find ${name || "it"}. It may have been closed.`;
      break;
    case 1005:
      text = /allowing multiple lines/.test(message)
        ? `That's more lines than ${info.name} sends at once from Alfred. Put it in the message box with ⌘↩ instead, and send it from there.`
        : message;
      break;
    case 1010:
      text = `${info.name} is still starting. Try again in a moment.`;
      break;
    default:
      text = message || `Something went wrong (error ${number}).`;
  }
  return notification(failureTitle(action, name), text);
}

/** The notification after a successful action, if it says anything. */
function successNotification(action, conversation, result) {
  switch (action) {
    case "send":
      return notification(`Sent to ${conversation.name}`, shorten(result, 200));
    case "markread":
      return notification(`Marked ${conversation.name} read`, conversation.network || conversation.name);
    case "markallread": {
      const count = Number(result) || 0;
      return notification("Marked everything read",
        count ? `${plural(count, "conversation", "conversations")} had something unread.` : "Nothing was unread.");
    }
    default:
      // Showing, Catch me up, Recap and drafts bring Vela forward: that says it.
      return QUIET;
  }
}

// ================================================================ JXA only
// Below here runs only under osascript (the tests stand in for $, ObjC and
// Application).

function environment() {
  return ObjC.deepUnwrap($.NSProcessInfo.processInfo.environment) || {};
}

/** "running", "notRunning" or "notInstalled", asking macOS, not Vela. */
function appState(info) {
  ObjC.import("AppKit");
  if ($.NSRunningApplication.runningApplicationsWithBundleIdentifier(info.bundleID).count > 0) return "running";
  const url = $.NSWorkspace.sharedWorkspace.URLForApplicationWithBundleIdentifier(info.bundleID);
  return url.isNil() ? "notInstalled" : "notRunning";
}

function openURL(url) {
  ObjC.import("AppKit");
  return $.NSWorkspace.sharedWorkspace.openURL($.NSURL.URLWithString(url));
}

/** An error from osascript as {number, message}. */
function scriptError(error) {
  return {
    number: error && typeof error.errorNumber === "number" ? error.errorNumber : null,
    message: error && error.message ? String(error.message) : String(error),
  };
}

/**
 * Every conversation, one Apple event per property. Read again (up to
 * three times) if a conversation came or went in between.
 */
function readConversations(app) {
  for (let attempt = 0; attempt < 3; attempt++) {
    const conversations = app.conversations;
    const columns = {};
    for (const [key] of COLUMNS) columns[key] = conversations[key]();
    const list = conversationsFrom(columns);
    if (list) return list;
  }
  throw Object.assign(new Error("Your conversations kept changing while Alfred read them. Try again."), { errorNumber: null });
}

function list(env) {
  const info = appInfo(env);
  const state = appState(info);
  if (state !== "running") return problemFeedback({ kind: state }, info);
  try {
    return listFeedback(readConversations(Application(info.bundleID)), info);
  } catch (error) {
    return problemFeedback({ kind: "error", ...scriptError(error) }, info);
  }
}

function act(env, text) {
  const info = appInfo(env);
  const action = String(env.vela_action || "open");
  const conversation = {
    id: String(env.conversation_id || ""),
    name: String(env.conversation_name || ""),
    network: String(env.network_name || ""),
  };
  // Results that open something rather than ask Vela.
  switch (action) {
    case "launch":
      return openURL(`${info.scheme}://`) ? QUIET : notification(`Couldn't open ${info.name}`, `Is ${info.name} installed?`);
    case "privacy":
      openURL(PRIVACY_URL);
      return QUIET;
    case "website":
      openURL(String(env.website_url || INSTALL_URL));
      return QUIET;
    default:
      break;
  }
  if ((action === "send" || action === "draft") && !text.trim()) {
    return notification(failureTitle(action, conversation.name), "There's nothing to send.");
  }
  if (appState(info) !== "running") {
    return notification(failureTitle(action, conversation.name), `${info.name} isn't running. Open it, then try again.`);
  }
  const app = Application(info.bundleID);
  const target = () => app.conversations.byId(conversation.id);
  try {
    switch (action) {
      case "open":
        app.show(target());
        return successNotification(action, conversation);
      case "catchup":
        if (conversation.id) app.catchUp(target());
        else app.catchUp();
        return successNotification(action, conversation);
      case "recap":
        if (conversation.id) app.openRecap(target());
        else app.openRecap();
        return successNotification(action, conversation);
      case "markread":
        app.markRead(target());
        return successNotification(action, conversation);
      case "markallread":
        return successNotification(action, conversation, app.markAllRead());
      case "send":
        app.sendMessage(text, { to: target() });
        return successNotification(action, conversation, text);
      case "draft":
        app.draftMessage(text, { to: target() });
        return successNotification(action, conversation);
      default:
        return notification("Vela couldn't do that", `The workflow doesn't know “${action}”.`);
    }
  } catch (error) {
    return failureNotification(action, conversation, scriptError(error), info);
  }
}

function search(env, text) {
  const info = appInfo(env);
  if (!text.trim()) return notification(`Search ${info.name}`, "Type the words to search for.");
  return openURL(searchLink(info, text.trim()))
    ? QUIET
    : notification(`Couldn't search ${info.name}`, `Is ${info.name} installed?`);
}

// osascript calls run() with the arguments after the script's path, and
// prints what it returns.
function run(argv) {
  const [command = "list", argument = ""] = argv;
  const env = environment();
  switch (command) {
    case "list": return JSON.stringify(list(env));
    case "write": return JSON.stringify(writeFeedback(String(argument), env));
    case "act": return JSON.stringify(act(env, String(argument)));
    case "search": return JSON.stringify(search(env, String(argument)));
    default: return JSON.stringify(notification("Vela for Alfred", `Unknown command “${command}”.`));
  }
}
