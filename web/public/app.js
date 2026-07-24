// The idea box. Posts to the backend, shows a friendly line either way.
(function () {
  const form = document.getElementById("idea-form");
  const status = document.getElementById("idea-status");
  if (!form) return;

  form.addEventListener("submit", async function (event) {
    event.preventDefault();

    const data = {
      idea: form.idea.value.trim(),
      name: form.name.value.trim(),
      mode: form.mode.value,
      website: form.website.value, // honeypot
    };

    if (data.idea.length < 3) {
      status.textContent = "Give us a bit more than that.";
      status.className = "status err";
      return;
    }

    const button = form.querySelector('button[type="submit"]');
    button.disabled = true;
    status.textContent = "Sending…";
    status.className = "status";

    try {
      const res = await fetch("/api/idea", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(data),
      });
      const body = await res.json().catch(() => ({}));

      if (res.ok && body.ok) {
        form.reset();
        status.textContent = "Got it. The AI will read it, tidy it up, and it'll join the queue. Cheers.";
        status.className = "status ok";
      } else {
        status.textContent = body.error || "Something went wrong — try again in a bit.";
        status.className = "status err";
      }
    } catch (_) {
      status.textContent = "Couldn't reach the server. Try again in a bit.";
      status.className = "status err";
    } finally {
      button.disabled = false;
    }
  });
})();
