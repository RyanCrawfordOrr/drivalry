// Drivalry push fan-out. One Supabase Edge Function, invoked by Database Webhooks
// (docs/03-architecture.md §10: one invocation per notification batch).
//
// Handles INSERTs on feed_reactions, feed_comments, friendships, crash_alerts and
// UPDATEs on friendships (accepted). Resolves recipients with the service role,
// loads their push_tokens, and sends through APNs (token-based auth, HTTP/2) and
// FCM HTTP v1 (service-account OAuth). Invalid tokens are deleted.
//
// Secrets (supabase secrets set ...): PUSH_WEBHOOK_SECRET, APNS_TEAM_ID, APNS_KEY_ID,
// APNS_PRIVATE_KEY (the .p8 PEM), APNS_BUNDLE_ID (app.drivalry), APNS_SANDBOX ("true"
// for development builds), FCM_SERVICE_ACCOUNT_JSON (the whole service-account file).
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by the platform.

import { createClient } from "npm:@supabase/supabase-js@2.49.4";
import * as jose from "npm:jose@5.9.6";

type WebhookPayload = {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  schema: string;
  record: Record<string, unknown> | null;
  old_record: Record<string, unknown> | null;
};

type Notification = {
  recipients: string[]; // profile ids
  title: string;
  body: string;
  category: "social" | "friends" | "crash";
  data: Record<string, string>;
};

const env = (k: string) => Deno.env.get(k) ?? "";
const admin = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
  auth: { persistSession: false },
});

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });
  const secret = env("PUSH_WEBHOOK_SECRET");
  if (secret && req.headers.get("x-push-secret") !== secret) {
    return new Response("forbidden", { status: 403 });
  }

  let payload: WebhookPayload;
  try {
    payload = await req.json();
  } catch {
    return new Response("bad json", { status: 400 });
  }

  const note = await buildNotification(payload);
  if (!note || note.recipients.length === 0) return json({ sent: 0, reason: "nothing to send" });

  const { data: tokens, error } = await admin
    .from("push_tokens")
    .select("token, platform, user_id")
    .in("user_id", note.recipients);
  if (error) return json({ error: error.message }, 500);

  const results = await Promise.allSettled(
    (tokens ?? []).map((t) =>
      // Raw APNs device tokens are 64 hex characters; FCM registration tokens
      // are longer and contain ':'. Both platforms currently register FCM
      // tokens (firebase_messaging), so APNs is a dormant path.
      /^[0-9a-f]{64}$/i.test(t.token) ? sendApns(t.token, note) : sendFcm(t.token, note)
    ),
  );

  const dead: string[] = [];
  let sent = 0;
  results.forEach((r, i) => {
    if (r.status === "fulfilled") {
      if (r.value === "ok") sent++;
      if (r.value === "dead") dead.push(tokens![i].token);
    } else {
      console.error("push failed", r.reason);
    }
  });
  if (dead.length) await admin.from("push_tokens").delete().in("token", dead);

  return json({ sent, dead: dead.length, recipients: note.recipients.length });
});

// ---------------------------------------------------------------------------
// What to say, and to whom
// ---------------------------------------------------------------------------

async function buildNotification(p: WebhookPayload): Promise<Notification | null> {
  const r = p.record ?? {};
  switch (`${p.table}:${p.type}`) {
    case "feed_reactions:INSERT": {
      const post = await postAuthor(r.post_id as string);
      if (!post || post.author_id === r.user_id) return null;
      const who = await handle(r.user_id as string);
      return {
        recipients: [post.author_id],
        title: "Drivalry",
        body: `${who} reacted ${emoji(r.kind as string)} to your ${postNoun(post.kind)}`,
        category: "social",
        data: { route: `/friends/post/${r.post_id}` },
      };
    }
    case "feed_comments:INSERT": {
      const post = await postAuthor(r.post_id as string);
      if (!post || post.author_id === r.author_id) return null;
      const who = await handle(r.author_id as string);
      const body = String(r.body ?? "");
      return {
        recipients: [post.author_id],
        title: `${who} commented`,
        body: body.length > 120 ? body.slice(0, 117) + "…" : body,
        category: "social",
        data: { route: `/friends/post/${r.post_id}` },
      };
    }
    case "friendships:INSERT": {
      if (r.status !== "pending") return null;
      const who = await handle(r.requester_id as string);
      return {
        recipients: [r.addressee_id as string],
        title: "Friend request",
        body: `${who} wants to be friends on Drivalry`,
        category: "friends",
        data: { route: "/friends/requests" },
      };
    }
    case "friendships:UPDATE": {
      if (r.status !== "accepted" || p.old_record?.status === "accepted") return null;
      const who = await handle(r.addressee_id as string);
      return {
        recipients: [r.requester_id as string],
        title: "Friend request accepted",
        body: `${who} accepted. Start a league?`,
        category: "friends",
        data: { route: "/friends" },
      };
    }
    case "crash_alerts:INSERT": {
      const who = await handle(r.user_id as string);
      const { data: members } = await admin
        .from("circle_members")
        .select("circle_id")
        .eq("user_id", r.user_id as string);
      const circleIds = (members ?? []).map((m) => m.circle_id);
      const { data: peers } = circleIds.length === 0
        ? { data: [] as { user_id: string }[] }
        : await admin
          .from("circle_members")
          .select("user_id")
          .in("circle_id", circleIds)
          .neq("user_id", r.user_id as string);
      const named = Array.isArray(r.notify_user_ids) ? (r.notify_user_ids as string[]) : [];
      const recipients = [...new Set([...(peers ?? []).map((m) => m.user_id as string), ...named])]
        .filter((id) => id !== r.user_id);
      return {
        recipients,
        title: "Possible crash",
        body: `${who}'s phone detected a possible crash and they did not respond. Tap to see where.`,
        category: "crash",
        data: {
          route: `/friends/crash/${r.id}`,
          lat: String(r.lat),
          lon: String(r.lon),
        },
      };
    }
    default:
      return null;
  }
}

async function postAuthor(postId: string): Promise<{ author_id: string; kind: string } | null> {
  const { data } = await admin.from("feed_posts").select("author_id, kind").eq("id", postId).maybeSingle();
  return data ?? null;
}

async function handle(userId: string): Promise<string> {
  const { data } = await admin.from("profiles").select("handle").eq("id", userId).maybeSingle();
  return data?.handle ? `@${data.handle}` : "Someone";
}

function postNoun(kind: string): string {
  switch (kind) {
    case "trip": return "trip";
    case "badge": return "badge";
    case "shame": return "Wall of Shame post";
    case "league": return "league result";
    case "convoy": return "convoy recap";
    default: return "post";
  }
}

function emoji(kind: string): string {
  return ({ fire: "🔥", clap: "👏", laugh: "😂", skull: "💀", clown: "🤡", snitch: "🚨" } as Record<string, string>)[kind] ?? "👍";
}

// ---------------------------------------------------------------------------
// APNs (token-based auth)
// ---------------------------------------------------------------------------

let apnsJwt: { token: string; issuedAt: number } | null = null;

async function apnsToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (apnsJwt && now - apnsJwt.issuedAt < 50 * 60) return apnsJwt.token; // Apple allows 20–60 min
  const key = await jose.importPKCS8(env("APNS_PRIVATE_KEY").replace(/\\n/g, "\n"), "ES256");
  const token = await new jose.SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: env("APNS_KEY_ID") })
    .setIssuer(env("APNS_TEAM_ID"))
    .setIssuedAt(now)
    .sign(key);
  apnsJwt = { token, issuedAt: now };
  return token;
}

async function sendApns(deviceToken: string, n: Notification): Promise<"ok" | "dead" | "error"> {
  if (!env("APNS_PRIVATE_KEY")) return "error";
  const host = env("APNS_SANDBOX") === "true" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
  const crash = n.category === "crash";
  const body = {
    aps: {
      alert: { title: n.title, body: n.body },
      sound: crash ? "default" : "default",
      "thread-id": n.category,
      "interruption-level": crash ? "time-sensitive" : "active",
    },
    ...n.data,
  };
  const res = await fetch(`${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await apnsToken()}`,
      "apns-topic": env("APNS_BUNDLE_ID") || "app.drivalry",
      "apns-push-type": "alert",
      "apns-priority": crash ? "10" : "5",
      "apns-expiration": String(Math.floor(Date.now() / 1000) + (crash ? 3600 : 86400)),
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
  if (res.ok) return "ok";
  const text = await res.text();
  if (res.status === 410 || text.includes("BadDeviceToken") || text.includes("Unregistered")) return "dead";
  console.error("apns", res.status, text);
  return "error";
}

// ---------------------------------------------------------------------------
// FCM HTTP v1
// ---------------------------------------------------------------------------

let fcmAccess: { token: string; expiresAt: number } | null = null;

async function fcmAccessToken(): Promise<{ token: string; projectId: string }> {
  const sa = JSON.parse(env("FCM_SERVICE_ACCOUNT_JSON"));
  const now = Math.floor(Date.now() / 1000);
  if (fcmAccess && fcmAccess.expiresAt - 60 > now) return { token: fcmAccess.token, projectId: sa.project_id };
  const key = await jose.importPKCS8(sa.private_key, "RS256");
  const assertion = await new jose.SignJWT({ scope: "https://www.googleapis.com/auth/firebase.messaging" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!res.ok) throw new Error(`fcm oauth ${res.status}: ${await res.text()}`);
  const data = await res.json();
  fcmAccess = { token: data.access_token, expiresAt: now + Number(data.expires_in ?? 3600) };
  return { token: fcmAccess.token, projectId: sa.project_id };
}

async function sendFcm(deviceToken: string, n: Notification): Promise<"ok" | "dead" | "error"> {
  if (!env("FCM_SERVICE_ACCOUNT_JSON")) return "error";
  const { token, projectId } = await fcmAccessToken();
  const crash = n.category === "crash";
  const message = {
    message: {
      token: deviceToken,
      notification: { title: n.title, body: n.body },
      data: { ...n.data, category: n.category },
      android: {
        priority: crash ? "HIGH" : "NORMAL",
        ttl: crash ? "3600s" : "86400s",
        notification: { channel_id: crash ? "crash" : n.category, tag: n.category },
      },
    },
  };
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify(message),
  });
  if (res.ok) return "ok";
  const text = await res.text();
  if (res.status === 404 || text.includes("UNREGISTERED") || text.includes("INVALID_ARGUMENT")) return "dead";
  console.error("fcm", res.status, text);
  return "error";
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}
