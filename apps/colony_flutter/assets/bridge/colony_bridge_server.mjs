import { randomUUID } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import http from "node:http";
import os from "node:os";
import path from "node:path";

const port = Number(process.env.BRIDGE_PORT || 8787);
const host = process.env.BRIDGE_HOST || "0.0.0.0";
const bridgeToken = process.env.BRIDGE_TOKEN || "";
const defaultWorkingDirectory = process.env.BRIDGE_WORKDIR || process.cwd();
const sessions = new Map();

const codexProbe = spawnSync("codex", ["--version"], { encoding: "utf8" });
const codexAvailable = codexProbe.status === 0;

function createJsonResponse(response, statusCode, payload) {
  response.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  });
  response.end(JSON.stringify(payload, null, 2));
}

function readJson(request) {
  return new Promise((resolve, reject) => {
    let raw = "";
    request.on("data", (chunk) => {
      raw += chunk;
      if (raw.length > 1024 * 1024) {
        reject(new Error("Request body too large"));
        request.destroy();
      }
    });
    request.on("end", () => {
      if (!raw) {
        resolve({});
        return;
      }

      try {
        resolve(JSON.parse(raw));
      } catch (error) {
        reject(error);
      }
    });
    request.on("error", reject);
  });
}

function authorize(request) {
  if (!bridgeToken) {
    return true;
  }

  const value = request.headers.authorization || "";
  return value === `Bearer ${bridgeToken}`;
}

function now() {
  return new Date().toISOString();
}

function makeMessage(role, content, metadata = null) {
  return {
    id: randomUUID(),
    role,
    content,
    createdAt: now(),
    metadata,
  };
}

function serializeSession(session) {
  return {
    session: {
      id: session.id,
      workingDirectory: session.workingDirectory,
      executionMode: session.executionMode,
      createdAt: session.createdAt,
      updatedAt: session.updatedAt,
      isRunning: session.isRunning,
      lastError: session.lastError,
      messages: session.messages,
    },
    server: {
      name: os.hostname(),
      codexAvailable,
      defaultWorkingDirectory,
    },
  };
}

function createSession({ workingDirectory, executionMode }) {
  const resolvedDirectory = path.resolve(workingDirectory || defaultWorkingDirectory);
  const session = {
    id: randomUUID(),
    workingDirectory: resolvedDirectory,
    executionMode: executionMode || "balanced",
    createdAt: now(),
    updatedAt: now(),
    isRunning: false,
    lastError: null,
    queue: Promise.resolve(),
    messages: [
      makeMessage(
        "assistant",
        "Colony bridge 已连接。你现在发出的消息会由这台 Mac 转发给本机 `codex exec`。",
        `cwd=${resolvedDirectory}`
      ),
    ],
  };

  sessions.set(session.id, session);
  return session;
}

function buildPrompt(session) {
  const transcript = session.messages
    .filter((message) => message.role !== "status")
    .slice(-12)
    .map((message) => `[${message.role}]\n${message.content}`)
    .join("\n\n");

  const modeInstruction = {
    balanced: "Work normally. Be concise but do not skip important execution details.",
    quick: "Prefer short answers, lightweight changes, and minimal exploration.",
    deep: "Spend more effort on planning, verification, and edge cases before replying.",
  }[session.executionMode] || "Work normally.";

  return [
    "You are Codex running on a Mac through a remote Colony bridge.",
    "The user's messages come from a mobile Colony UI that mirrors this transcript.",
    `Primary working directory: ${session.workingDirectory}`,
    modeInstruction,
    "If the user asks you to modify files, do the work in the working directory and then summarize what changed.",
    "Reply in concise Markdown.",
    "",
    "Conversation transcript:",
    transcript,
    "",
    "Write the next assistant response only.",
  ].join("\n");
}

async function runCodexTurn(session) {
  if (!codexAvailable) {
    throw new Error("`codex` CLI is not available on this Mac.");
  }

  session.isRunning = true;
  session.lastError = null;
  session.updatedAt = now();

  const prompt = buildPrompt(session);
  const args = [
    "exec",
    "--json",
    "--skip-git-repo-check",
    "--dangerously-bypass-approvals-and-sandbox",
    "--ephemeral",
    "-C",
    session.workingDirectory,
    prompt,
  ];

  const child = spawn("codex", args, {
    cwd: session.workingDirectory,
    env: process.env,
  });

  const events = [];
  let stdout = "";
  let stderr = "";

  child.stdout.on("data", (chunk) => {
    stdout += chunk.toString();
  });

  child.stderr.on("data", (chunk) => {
    stderr += chunk.toString();
  });

  const exitCode = await new Promise((resolve, reject) => {
    child.on("error", reject);
    child.on("close", resolve);
  });

  const lines = stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);

  let assistantText = "";
  for (const line of lines) {
    try {
      const event = JSON.parse(line);
      events.push(event);
      if (event.type === "item.completed" && event.item?.type === "agent_message" && event.item.text) {
        assistantText = event.item.text;
      }
    } catch {
      if (!line.includes("AuthRequired")) {
        stderr += `${line}\n`;
      }
    }
  }

  if (exitCode !== 0) {
    throw new Error(stderr.trim() || `codex exited with code ${exitCode}`);
  }

  if (!assistantText) {
    throw new Error(stderr.trim() || "codex completed without an assistant message");
  }

  const usageEvent = events.find((event) => event.type === "turn.completed");
  const usage = usageEvent?.usage
    ? `input=${usageEvent.usage.input_tokens} output=${usageEvent.usage.output_tokens}`
    : null;

  session.messages.push(makeMessage("assistant", assistantText, usage));
  session.updatedAt = now();
}

async function enqueueTurn(session) {
  session.queue = session.queue
    .catch(() => {})
    .then(async () => {
      try {
        await runCodexTurn(session);
      } catch (error) {
        session.lastError = error.message;
        session.messages.push(makeMessage("status", `Bridge error: ${error.message}`));
      } finally {
        session.isRunning = false;
        session.updatedAt = now();
      }
    });

  return session.queue;
}

const server = http.createServer(async (request, response) => {
  const url = new URL(request.url || "/", `http://${request.headers.host || "localhost"}`);

  if (request.method === "OPTIONS") {
    createJsonResponse(response, 204, {});
    return;
  }

  if (!authorize(request)) {
    createJsonResponse(response, 401, { error: "Unauthorized" });
    return;
  }

  if (request.method === "GET" && url.pathname === "/health") {
    createJsonResponse(response, 200, {
      ok: true,
      codexAvailable,
      hostname: os.hostname(),
      defaultWorkingDirectory,
    });
    return;
  }

  if (request.method === "POST" && url.pathname === "/api/sessions") {
    try {
      const body = await readJson(request);
      const session = createSession(body);
      createJsonResponse(response, 200, serializeSession(session));
    } catch (error) {
      createJsonResponse(response, 400, { error: error.message });
    }
    return;
  }

  const sessionMatch = url.pathname.match(/^\/api\/sessions\/([^/]+)$/);
  if (request.method === "GET" && sessionMatch) {
    const session = sessions.get(sessionMatch[1]);
    if (!session) {
      createJsonResponse(response, 404, { error: "Session not found" });
      return;
    }

    createJsonResponse(response, 200, serializeSession(session));
    return;
  }

  const messageMatch = url.pathname.match(/^\/api\/sessions\/([^/]+)\/messages$/);
  if (request.method === "POST" && messageMatch) {
    const session = sessions.get(messageMatch[1]);
    if (!session) {
      createJsonResponse(response, 404, { error: "Session not found" });
      return;
    }

    try {
      const body = await readJson(request);
      const content = String(body.content || "").trim();
      if (!content) {
        createJsonResponse(response, 400, { error: "Message content is required" });
        return;
      }

      session.messages.push(makeMessage("user", content));
      session.updatedAt = now();
      void enqueueTurn(session);
      createJsonResponse(response, 200, serializeSession(session));
    } catch (error) {
      createJsonResponse(response, 400, { error: error.message });
    }
    return;
  }

  createJsonResponse(response, 404, { error: "Not found" });
});

server.listen(port, host, () => {
  console.log(
    JSON.stringify({
      event: "listening",
      host,
      port,
      tokenProtected: bridgeToken.length > 0,
      codexAvailable,
      defaultWorkingDirectory,
    })
  );
});
