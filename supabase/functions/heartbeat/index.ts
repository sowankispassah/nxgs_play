import { corsHeaders, functionError, json, readBody, supabaseAdmin } from "../_shared/rental.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });

  try {
    const body = await readBody(req);
    const sessionId = String(body.session_id ?? "");
    if (!sessionId)
      return json({ error: true, message: "invalid_session" }, 400);

    const { data, error } = await supabaseAdmin().rpc("heartbeat_session", {
      p_session_id: sessionId,
    });
    if (error)
      throw error;

    return json({ session: data });
  } catch (error) {
    return functionError(error);
  }
});
