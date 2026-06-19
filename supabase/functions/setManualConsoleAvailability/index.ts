import {
  asString,
  corsHeaders,
  functionError,
  json,
  readBody,
  requireControllerAdmin,
  supabaseAdmin,
} from "../_shared/rental.ts";

const allowedActions = new Set(["available", "reserved", "occupied", "maintenance", "disabled"]);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });

  try {
    const body = await readBody(req);
    await requireControllerAdmin(body);

    const consoleId = asString(body.id);
    const action = asString(body.action).toLowerCase();
    if (!consoleId || !allowedActions.has(action))
      throw new Error("invalid_manual_console_action");

    let durationMinutes: number | null = null;
    if (action === "reserved" || action === "occupied") {
      if (body.duration_minutes !== null && body.duration_minutes !== undefined && body.duration_minutes !== "") {
        durationMinutes = Number(body.duration_minutes);
        if (!Number.isInteger(durationMinutes) || durationMinutes < 1 || durationMinutes > 43200)
          throw new Error("invalid_manual_lock_duration");
      }
    }

    const supabase = supabaseAdmin();
    const { data, error } = await supabase.rpc("set_manual_console_availability", {
      p_console_id: consoleId,
      p_action: action,
      p_duration_minutes: durationMinutes,
      p_note: asString(body.note) || null,
    });
    if (error)
      throw error;

    return json(data ?? { ok: true });
  } catch (error) {
    return functionError(error);
  }
});
