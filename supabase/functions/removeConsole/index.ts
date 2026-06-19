import {
  asString,
  corsHeaders,
  functionError,
  json,
  readBody,
  requireControllerAdmin,
  supabaseAdmin,
} from "../_shared/rental.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });

  try {
    const body = await readBody(req);
    await requireControllerAdmin(body);

    const id = asString(body.id);
    if (!id)
      throw new Error("invalid_console");

    const supabase = supabaseAdmin();
    const { data: sessions, error: sessionError } = await supabase
      .from("play_sessions")
      .select("id")
      .eq("console_id", id)
      .in("status", ["pending", "active", "extended", "expired"]);
    if (sessionError)
      throw sessionError;

    const { data: reservations, error: reservationError } = await supabase
      .from("console_reservations")
      .select("id")
      .eq("console_id", id)
      .eq("status", "reserved")
      .gt("expires_at", new Date().toISOString());
    if (reservationError)
      throw reservationError;

    if ((sessions?.length ?? 0) > 0 || (reservations?.length ?? 0) > 0)
      return json({ error: true, message: "console_not_safe_to_remove" }, 409);

    const { error } = await supabase.from("consoles").delete().eq("id", id);
    if (error)
      throw error;

    return json({ ok: true });
  } catch (error) {
    return functionError(error);
  }
});
