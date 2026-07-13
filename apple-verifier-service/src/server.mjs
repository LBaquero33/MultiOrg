import { createServer } from "node:http";
import { timingSafeEqual } from "node:crypto";
import {
  createAppleVerifierFromEnvironment,
  safeServiceError,
  signedResponseEnvelope,
  verifyTransactionRequest,
} from "./verifier.mjs";

const PORT = Number(process.env.PORT ?? 8080);
const MAX_BODY_BYTES = 64 * 1024;
const SERVICE_MARKER = "home_plate_apple_verifier_v1";

function secret(name) {
  const value = String(process.env[name] ?? "").trim();
  if (value.length < 32) throw new Error(`missing_configuration:${name}`);
  return value;
}

function authorized(request, expected) {
  const supplied = String(request.headers.authorization ?? "").replace(/^Bearer\s+/i, "");
  const left = Buffer.from(supplied);
  const right = Buffer.from(expected);
  return left.length === right.length && timingSafeEqual(left, right);
}

async function readJSON(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) throw new Error("invalid_verification_request");
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw new Error("invalid_verification_request");
  }
}

const requestToken = secret("APPLE_VERIFIER_SERVICE_TOKEN");
const responseSecret = secret("APPLE_VERIFIER_RESPONSE_HMAC_SECRET");
const configuration = createAppleVerifierFromEnvironment();

createServer(async (request, response) => {
  response.setHeader("content-type", "application/json");
  if (request.method === "GET" && request.url === "/health") {
    response.statusCode = 200;
    response.end(JSON.stringify({ ok: true, marker: SERVICE_MARKER }));
    return;
  }
  if (request.method !== "POST" || request.url !== "/v1/verify-transaction") {
    response.statusCode = 404;
    response.end(JSON.stringify({ error: "not_found" }));
    return;
  }
  if (!authorized(request, requestToken)) {
    response.statusCode = 401;
    response.end(JSON.stringify({ error: "unauthorized" }));
    return;
  }

  try {
    const payload = await verifyTransactionRequest(await readJSON(request), configuration);
    response.statusCode = 200;
    response.end(JSON.stringify(signedResponseEnvelope(payload, responseSecret)));
    console.info(JSON.stringify({ event: "apple_transaction_verified", marker: SERVICE_MARKER }));
  } catch (error) {
    const code = safeServiceError(error);
    response.statusCode = code === "apple_verification_temporarily_unavailable" ? 503 : 400;
    response.end(JSON.stringify({ error: code }));
    console.error(JSON.stringify({ event: "apple_transaction_verification_failed", marker: SERVICE_MARKER, code }));
  }
}).listen(PORT, "0.0.0.0", () => {
  console.info(JSON.stringify({ event: "apple_verifier_started", marker: SERVICE_MARKER, port: PORT }));
});
