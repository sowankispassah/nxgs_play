import { corsHeaders, functionError, json, readBody, supabaseAdmin } from "../_shared/rental.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });
  await readBody(req);

  try {
    const { data, error } = await supabaseAdmin().rpc("release_expired_reservations_sql");
    if (error)
      throw error;
    return json({ released: data ?? 0 });
  } catch (error) {
    return functionError(error);
  }
});
