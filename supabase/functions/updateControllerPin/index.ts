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

    const newPin = asString(body.new_pin);
    if (newPin.length < 4)
      throw new Error("invalid_controller_pin");

    const supabase = supabaseAdmin();
    const { error } = await supabase.rpc("set_controller_admin_pin", { p_new_pin: newPin });
    if (error)
      throw error;

    return json({ ok: true });
  } catch (error) {
    return functionError(error);
  }
});
