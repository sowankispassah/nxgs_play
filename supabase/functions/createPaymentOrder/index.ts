import {
  activePricing,
  appSettingEnabled,
  corsHeaders,
  createRazorpayOrder,
  functionError,
  json,
  pricingForSelection,
  readBody,
  supabaseAdmin,
  asString,
} from "../_shared/rental.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS")
    return new Response("ok", { headers: corsHeaders });

  try {
    const body = await readBody(req);
    if (body.mode === "pricing")
      return json(await activePricing());

    const reservationId = asString(body.reservation_id);
    const storeId = asString(body.store_id);
    const timePlanId = asString(body.time_plan_id);
    const testPayment = body.test_payment === true || asString(body.test_payment).toLowerCase() === "true";
    if (!reservationId)
      return json({ error: true, message: "invalid_reservation" }, 400);
    if (!storeId || !timePlanId)
      return json({ error: true, message: "invalid_pricing_selection" }, 400);

    const supabase = supabaseAdmin();
    const { data: reservation, error: reservationError } = await supabase
      .from("console_reservations")
      .select("id, console_id, status, expires_at")
      .eq("id", reservationId)
      .eq("status", "reserved")
      .gt("expires_at", new Date().toISOString())
      .single();
    if (reservationError || !reservation)
      throw new Error("reservation_expired");

    const price = await pricingForSelection(storeId, timePlanId);
    const timePlan = Array.isArray(price.time_plans) ? price.time_plans[0] : price.time_plans;
    const store = Array.isArray(price.stores) ? price.stores[0] : price.stores;

    if (testPayment) {
      if (!(await appSettingEnabled(supabase, "test_payment_bypass")))
        return json({ error: true, message: "test_payment_bypass_disabled" }, 403);

      const orderId = `test_order_${crypto.randomUUID()}`;
      const { data: payment, error: paymentError } = await supabase
        .from("payments")
        .insert({
          reservation_id: reservation.id,
          console_id: reservation.console_id,
          kind: "initial",
          store_id: storeId,
          time_plan_id: timePlanId,
          duration_minutes: timePlan.duration_minutes,
          amount_paise: price.amount_paise,
          currency: price.currency,
          razorpay_order_id: orderId,
        })
        .select()
        .single();
      if (paymentError)
        throw paymentError;

      const { data, error } = await supabase.rpc("confirm_initial_payment", {
        p_payment_id: payment.id,
        p_razorpay_payment_id: `test_pay_${crypto.randomUUID()}`,
        p_razorpay_signature: "test_payment_bypass",
      });
      if (error)
        throw error;
      const row = Array.isArray(data) ? data[0] : null;
      if (!row)
        throw new Error("test_payment_confirm_failed");

      return json({
        payment: row.payment,
        session: row.session,
        console: row.console,
        order: {
          id: orderId,
          amount: price.amount_paise,
          currency: price.currency,
          status: "paid",
        },
        test_payment: true,
      });
    }

    const order = await createRazorpayOrder({
      amount: price.amount_paise,
      currency: price.currency,
      receipt: `res_${reservation.id}`.slice(0, 40),
      notes: {
        reservation_id: reservation.id,
        console_id: reservation.console_id,
        store_id: storeId,
        store_name: String(store?.name ?? ""),
        time_plan_id: timePlanId,
        duration_minutes: String(timePlan.duration_minutes),
        kind: "initial",
      },
    });

    const { data: payment, error: paymentError } = await supabase
      .from("payments")
      .insert({
        reservation_id: reservation.id,
        console_id: reservation.console_id,
        kind: "initial",
        store_id: storeId,
        time_plan_id: timePlanId,
        duration_minutes: timePlan.duration_minutes,
        amount_paise: price.amount_paise,
        currency: price.currency,
        razorpay_order_id: order.id,
      })
      .select()
      .single();
    if (paymentError)
      throw paymentError;

    return json({ payment, order });
  } catch (error) {
    return functionError(error);
  }
});
