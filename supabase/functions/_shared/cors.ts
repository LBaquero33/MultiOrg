export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info, x-home-plate-correlation-id",
  "Access-Control-Expose-Headers": "x-home-plate-correlation-id",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
};

export function corsPreflight(request: Request): Response | null {
  if (request.method !== "OPTIONS") return null;
  return new Response(null, { status: 204, headers: corsHeaders });
}

export function requestCorrelationId(request: Request): string {
  const supplied = request.headers.get("x-home-plate-correlation-id")?.trim() ?? "";
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
    supplied,
  )
    ? supplied.toLowerCase()
    : crypto.randomUUID();
}

export function jsonResponse(
  status: number,
  body: Record<string, unknown>,
  correlationId?: string,
): Response {
  const responseBody = correlationId ? { ...body, correlation_id: correlationId } : body;
  return new Response(JSON.stringify(responseBody), {
    status,
    headers: {
      ...corsHeaders,
      "content-type": "application/json; charset=utf-8",
      ...(correlationId
        ? { "x-home-plate-correlation-id": correlationId }
        : {}),
    },
  });
}
