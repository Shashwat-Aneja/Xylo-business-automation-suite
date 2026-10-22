import test from "node:test";
import assert from "node:assert/strict";
import { createEmailRouter } from "../src/email-router.js";
import { invoiceReminderEmail, testEmail } from "../src/templates.js";
import { createResendClient, MailConfigurationError, MailDeliveryError } from "../src/resend.js";

function responseRecorder() {
  return {
    statusCode: 200, body: undefined,
    status(code) { this.statusCode = code; return this; },
    json(body) { this.body = body; return this; },
  };
}
function invoke(router, req) {
  const route = router.stack.find((layer) => layer.route?.path === "/test").route;
  const res = responseRecorder();
  let index = 0;
  const next = (err) => { if (err) throw err; const handler = route.stack[index++].handle; if (handler) return handler(req, res, next); };
  return Promise.resolve(next()).then(() => res);
}

test("test email escapes user-controlled names", () => {
  const msg = testEmail({ recipientName: "<script>alert(1)</script>" });
  assert.equal(msg.html.includes("<script>"), false);
  assert.equal(msg.html.includes("&lt;script&gt;"), true);
});

test("invoice reminder requires HTTPS and escapes invoice content", () => {
  assert.throws(() => invoiceReminderEmail({ businessName:"A", invoiceNumber:"1", amount:"1", dueDate:"today", invoiceUrl:"http://example.com" }), /HTTPS/);
  const msg = invoiceReminderEmail({ recipientName:"Sam", businessName:"<b>Shop</b>", invoiceNumber:"INV-1", amount:"₹100", dueDate:"today", invoiceUrl:"https://example.com/i/1" });
  assert.equal(msg.html.includes("<b>Shop</b>"), false);
  assert.match(msg.html, /&lt;b&gt;Shop&lt;\/b&gt;/);
});

test("Resend adapter validates configuration and returns only provider ID", async () => {
  assert.throws(() => createResendClient({ apiKey:"", from:"Xylo <mail@example.com>" }), MailConfigurationError);
  let request;
  const client = createResendClient({ apiKey:"test-secret", from:"Xylo <mail@example.com>", fetchImpl:async (url, options) => {
    request = { url, options };
    return { ok:true, status:200, json:async()=>({id:"msg_test_123"}) };
  }});
  assert.deepEqual(await client.send({ to:"user@example.com", subject:"Hello", text:"Test", html:"<p>Test</p>" }), {id:"msg_test_123"});
  assert.equal(request.options.headers.Authorization, "Bearer test-secret");
  assert.equal(JSON.parse(request.options.body).to[0], "user@example.com");
});

test("Resend errors do not disclose provider response content", async () => {
  const client = createResendClient({ apiKey:"test-secret", from:"Xylo <mail@example.com>", fetchImpl:async()=>({ok:false,status:403,json:async()=>({message:"secret diagnostic"})}) });
  await assert.rejects(client.send({to:"user@example.com",subject:"Hello",text:"Test"}), (error) => error instanceof MailDeliveryError && !error.message.includes("secret diagnostic"));
});

test("test route sends only to authenticated account email and logs success", async () => {
  let sent, logged;
  const router = createEmailRouter({
    requireUser:(req,_res,next)=>{ req.xyloUser={id:"user-1",email:"owner@example.com",name:"Owner"}; return next(); },
    mailClient:{send:async(message)=>{sent=message;return {id:"msg_1"};}},
    logAttempt:async(entry)=>{logged=entry;},
  });
  const res = await invoke(router,{xyloUser:{id:"user-1",email:"owner@example.com",name:"Owner"}});
  assert.equal(res.statusCode,202);
  assert.equal(sent.to,"owner@example.com");
  assert.equal(logged.providerMessageId,"msg_1");
  assert.equal(logged.status,"accepted");
});

test("test route rate limits repeated requests", async () => {
  let time=1000, sends=0;
  const router = createEmailRouter({
    requireUser:(req,_res,next)=>next(),
    mailClient:{send:async()=>{sends++;return {id:"msg"};}},
    logAttempt:async()=>{},
    now:()=>time,limit:1,windowMs:1000,
  });
  const req={xyloUser:{id:"u",email:"u@example.com",name:"U"}};
  assert.equal((await invoke(router,req)).statusCode,202);
  assert.equal((await invoke(router,req)).statusCode,429);
  assert.equal(sends,1);
  time=3000;
});
