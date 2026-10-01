// Same-origin calls: CloudFront routes /api/* to the ALB, so no CORS is needed.
const API = "/api";
const $ = (id) => document.getElementById(id);

async function checkHealth() {
  try {
    const [health, ready] = await Promise.all([
      fetch(`${API}/health`).then((r) => r.json()),
      fetch(`${API}/ready`).then((r) => r.json()),
    ]);
    $("status").textContent = `API ${health.version} (${health.env}) · database ${ready.database}`;
    $("status").className = ready.database === "up" ? "status ok" : "status bad";
  } catch {
    $("status").textContent = "API unreachable";
    $("status").className = "status bad";
  }
}

async function loadMessages() {
  const res = await fetch(`${API}/messages`);
  const list = $("messages");
  list.replaceChildren();
  for (const m of await res.json()) {
    const li = document.createElement("li");
    const who = document.createElement("strong");
    who.textContent = m.author;
    const when = document.createElement("time");
    when.textContent = new Date(m.created_at).toLocaleString();
    const body = document.createElement("p");
    body.textContent = m.body; // textContent, never innerHTML: no XSS
    li.append(who, when, body);
    list.append(li);
  }
}

$("form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const res = await fetch(`${API}/messages`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ author: $("author").value, body: $("body").value }),
  });
  if (res.ok) {
    $("body").value = "";
    loadMessages();
  }
});

checkHealth();
loadMessages();
