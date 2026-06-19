import { corsHeaders, functionError, json, readBody, supabaseAdmin } from "../_shared/rental.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });

  try {
    const body = await readBody(req);
    const reservationId = String(body.reservation_id ?? "");
    if (!reservationId)
      return json({ error: true, message: "invalid_reservation" }, 400);

    const { data, error } = await supabaseAdmin().rpc("release_reservation", {
      p_reservation_id: reservationId,
    });
    if (error)
      throw error;

    return json({ reservation: data });
  } catch (error) {
    return functionError(error);
  }
});
