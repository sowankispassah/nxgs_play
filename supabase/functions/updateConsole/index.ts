import {
  asString,
  corsHeaders,
  functionError,
  json,
  readBody,
  requireControllerAdmin,
  supabaseAdmin,
} from "../_shared/rental.ts";

const allowedStates = new Set(["available", "offline", "maintenance", "disabled"]);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });

  try {
    const body = await readBody(req);
    await requireControllerAdmin(body);

    const id = asString(body.id);
    if (!id)
      throw new Error("invalid_console");

    const state = asString(body.state);
    if (state && !allowedStates.has(state))
      throw new Error("invalid_console_state");

    const updates: Record<string, string | null> = {
      name: asString(body.name),
      console_pin: asString(body.console_pin),
    };
    if (state) {
      updates.state = state;
      updates.disabled_at = state === "disabled" ? new Date().toISOString() : null;
    }

    const supabase = supabaseAdmin();
    const { data, error } = await supabase
      .from("consoles")
      .update(updates)
      .eq("id", id)
      .select("*")
      .single();
    if (error)
      throw error;

    return json({ console: data });
  } catch (error) {
    return functionError(error);
  }
});
