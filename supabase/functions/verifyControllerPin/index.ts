import {
  createControllerAdminToken,
  corsHeaders,
  functionError,
  json,
  readBody,
  supabaseAdmin,
  asString,
} from "../_shared/rental.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });

  try {
    const body = await readBody(req);
    const pin = asString(body.pin);
    const supabase = supabaseAdmin();
    const { data, error } = await supabase.rpc("verify_controller_admin_pin", { p_pin: pin });
    if (error)
      throw error;
    if (data !== true)
      return json({ error: true, message: "invalid_controller_pin" }, 401);

    const token = await createControllerAdminToken();
    return json({
      authenticated: true,
      admin_token: token.token,
      expires_at: token.expires_at,
    });
  } catch (error) {
    return functionError(error);
  }
});
