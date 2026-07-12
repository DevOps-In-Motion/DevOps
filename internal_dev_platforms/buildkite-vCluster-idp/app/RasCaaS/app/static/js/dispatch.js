/**
 * RaSCaaS cluster deployment UI (SSE live log)
 */
(function () {
  const $ = (id) => document.getElementById(id);

  const repoSelect = $("repo-select");
  const branchSelect = $("branch-select");
  const ttlInput = $("ttl-input");
  const reasonInput = $("reason-input");
  const ticketInput = $("ticket-input");

  const cardBranch = $("card-branch");
  const cardContext = $("card-context");
  const triggerPanel = $("trigger-panel");
  const triggerSummary = $("trigger-summary");
  const triggerBtn = $("trigger-btn");
  const historyList = $("history-list");
  const historyCount = $("history-count");

  const livePanel = $("live-panel");
  const liveLog = $("live-log");
  const livePanelStatus = $("live-panel-status");
  const liveRunLink = $("live-run-link");

  let eventSource = null;
  let activeDeploymentId = null;

  function setStepper(step) {
    document.querySelectorAll(".kovr-stepper__item").forEach((el) => {
      const n = Number(el.dataset.step);
      el.classList.toggle("is-active", n === step);
      el.classList.toggle("is-done", n < step);
    });
  }

  function unlockCard(card) {
    card.classList.remove("kovr-card--locked");
    card.classList.add("kovr-card--unlocked");
  }

  function lockCard(card) {
    card.classList.add("kovr-card--locked");
    card.classList.remove("kovr-card--unlocked");
  }

  function enableFields(...fields) {
    fields.forEach((f) => {
      if (f) f.disabled = false;
    });
  }

  function toast(msg, isError) {
    const el = document.createElement("div");
    el.className = "kovr-toast" + (isError ? " kovr-toast--error" : "");
    el.textContent = msg;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 4000);
  }

  function esc(text) {
    const d = document.createElement("div");
    d.textContent = text || "";
    return d.innerHTML;
  }

  function fmtSummaryValue(value, label) {
    const v = (value || "").trim();
    if (!v) {
      return `<span class="kovr-summary__dim">${label}: <em>not provided</em></span>`;
    }
    return `<span class="kovr-summary__dim"><strong>${label}:</strong> ${esc(v)}</span>`;
  }

  function updateSummary() {
    const repo = repoSelect.value;
    const branch = branchSelect.value;
    const ttl = ttlInput.value.trim();
    const reason = reasonInput.value.trim();
    const ticket = ticketInput.value.trim();

    if (!repo || !branch) {
      triggerPanel.hidden = true;
      return;
    }

    triggerPanel.hidden = false;
    triggerSummary.innerHTML = [
      `<span class="kovr-summary__primary"><strong>${esc(repo)}</strong> @ <strong>${esc(branch)}</strong></span>`,
      fmtSummaryValue(ttl, "TTL"),
      fmtSummaryValue(reason, "Reason"),
      fmtSummaryValue(ticket, "Linear ticket URL"),
    ].join("");
    setStepper(3);
  }

  function phaseClass(phase) {
    return `kovr-history__status--${phase || "provisioning"}`;
  }

  function renderHistoryItem(dep) {
    const li = document.createElement("li");
    li.className = "kovr-history__item";
    li.dataset.deploymentId = dep.id;
    const ghLink = dep.run_url
      ? `<a class="kovr-history__link" href="${esc(dep.run_url)}" target="_blank" rel="noopener noreferrer">GitHub</a>`
      : "";
    li.innerHTML = `
      <div class="kovr-history__body">
        <span class="kovr-history__title">${esc(dep.repo)} @ ${esc(dep.branch)}${ghLink}</span>
        <span class="kovr-history__meta">${esc(dep.message || "")}</span>
      </div>
      <span class="kovr-history__status ${phaseClass(dep.phase)}">${esc(dep.status_label || dep.phase)}</span>
    `;
    return li;
  }

  function upsertHistoryItem(dep) {
    const existing = historyList.querySelector(`[data-deployment-id="${dep.id}"]`);
    const empty = historyList.querySelector(".kovr-history__empty");
    if (empty) empty.remove();
    const node = renderHistoryItem(dep);
    if (existing) {
      existing.replaceWith(node);
    } else {
      historyList.prepend(node);
    }
    const count = historyList.querySelectorAll(".kovr-history__item").length;
    historyCount.textContent = `${count} this session`;
  }

  function renderHistoryList(deployments) {
    if (!deployments.length) {
      historyList.innerHTML =
        '<li class="kovr-history__empty">No deployments yet this session.</li>';
      historyCount.textContent = "0 this session";
      return;
    }
    historyList.innerHTML = "";
    deployments.forEach((dep) => historyList.appendChild(renderHistoryItem(dep)));
    historyCount.textContent = `${deployments.length} this session`;
  }

  async function refreshClusterList() {
    try {
      const res = await fetch("/api/clusters");
      if (!res.ok) return;
      const deployments = await res.json();
      renderHistoryList(Array.isArray(deployments) ? deployments : []);
    } catch {
      /* ignore */
    }
  }

  function appendLogLine(line, level) {
    if (!liveLog) return;
    const ts = new Date().toLocaleTimeString();
    const span = document.createElement("span");
    span.className = level === "error" ? "kovr-log__line--error" : "";
    span.textContent = `[${ts}] ${line}\n`;
    liveLog.appendChild(span);
    liveLog.scrollTop = liveLog.scrollHeight;
  }

  function closeStream() {
    if (eventSource) {
      eventSource.close();
      eventSource = null;
    }
  }

  function openStream(deploymentId, runUrl) {
    closeStream();
    activeDeploymentId = deploymentId;
    livePanel.hidden = false;
    liveLog.textContent = "";
    livePanelStatus.textContent = "Streaming live updates…";
    if (runUrl && liveRunLink) {
      liveRunLink.href = runUrl;
      liveRunLink.hidden = false;
    } else if (liveRunLink) {
      liveRunLink.hidden = true;
    }

    eventSource = new EventSource(`/api/clusters/${deploymentId}/stream`);

    eventSource.onmessage = (ev) => {
      let data;
      try {
        data = JSON.parse(ev.data);
      } catch {
        return;
      }

      if (data.run_url && liveRunLink) {
        liveRunLink.href = data.run_url;
        liveRunLink.hidden = false;
      }

      if (data.type === "log" && data.line) {
        appendLogLine(data.line, data.level);
      }

      if (data.deployment) {
        upsertHistoryItem(data.deployment);
        if (data.deployment.phase === "ready") {
          livePanelStatus.textContent = "Deployment complete";
        } else if (data.deployment.phase === "failed") {
          livePanelStatus.textContent = "Deployment failed";
        } else {
          livePanelStatus.textContent = data.deployment.message || "In progress…";
        }
      }

      if (data.type === "complete") {
        livePanelStatus.textContent = "Stream finished";
        closeStream();
        refreshClusterList();
      }

      if (data.type === "error") {
        appendLogLine(data.message || "Error", "error");
        livePanelStatus.textContent = "Stream error";
        closeStream();
      }
    };

    eventSource.onerror = () => {
      appendLogLine("Connection to live stream closed", "error");
      livePanelStatus.textContent = "Stream disconnected";
      closeStream();
    };
  }

  async function apiErrorMessage(res, fallback) {
    try {
      const data = await res.json();
      if (data.detail) {
        return typeof data.detail === "string" ? data.detail : JSON.stringify(data.detail);
      }
    } catch (_) {
      /* ignore */
    }
    return fallback;
  }

  async function loadRepos() {
    repoSelect.closest(".kovr-card")?.classList.add("is-loading");
    try {
      const res = await fetch("/api/repos");
      if (!res.ok) {
        throw new Error(await apiErrorMessage(res, "Failed to load repositories"));
      }
      const data = await res.json();
      const repos = Array.isArray(data) ? data : data.repositories || [];
      repoSelect.innerHTML = '<option value="">Select repository…</option>';
      repos.forEach((r) => {
        const name = r.full_name || r.name || r;
        const opt = document.createElement("option");
        opt.value = name;
        opt.textContent = name;
        repoSelect.appendChild(opt);
      });
      repoSelect.disabled = false;
    } catch (e) {
      toast(e.message || "Could not load repositories", true);
      repoSelect.innerHTML = '<option value="">Error loading repositories</option>';
    } finally {
      repoSelect.closest(".kovr-card")?.classList.remove("is-loading");
    }
  }

  async function loadBranches(repo) {
    branchSelect.disabled = true;
    branchSelect.innerHTML = '<option value="">Loading…</option>';
    try {
      const res = await fetch(`/api/branches?repo=${encodeURIComponent(repo)}`);
      if (!res.ok) {
        throw new Error(await apiErrorMessage(res, "Failed to load branches"));
      }
      const branches = await res.json();
      branchSelect.innerHTML = '<option value="">Select branch…</option>';
      (Array.isArray(branches) ? branches : []).forEach((b) => {
        const name = typeof b === "string" ? b : b.name;
        const opt = document.createElement("option");
        opt.value = name;
        opt.textContent = name;
        branchSelect.appendChild(opt);
      });
      branchSelect.disabled = false;
      unlockCard(cardBranch);
      setStepper(2);
    } catch (e) {
      toast(e.message || "Could not load branches", true);
    }
  }

  repoSelect.addEventListener("change", () => {
    const repo = repoSelect.value;
    lockCard(cardBranch);
    lockCard(cardContext);
    branchSelect.disabled = true;
    ttlInput.disabled = true;
    reasonInput.disabled = true;
    ticketInput.disabled = true;
    triggerPanel.hidden = true;

    if (!repo) {
      setStepper(1);
      return;
    }
    loadBranches(repo);
  });

  branchSelect.addEventListener("change", () => {
    if (branchSelect.value) {
      unlockCard(cardContext);
      enableFields(ttlInput, reasonInput, ticketInput);
      setStepper(3);
    }
    updateSummary();
  });

  [ttlInput, reasonInput, ticketInput].forEach((el) => {
    el?.addEventListener("input", updateSummary);
  });

  triggerBtn.addEventListener("click", async () => {
    const repo = repoSelect.value;
    const branch = branchSelect.value;
    if (!repo || !branch) return;

    triggerBtn.disabled = true;
    closeStream();
    try {
      const res = await fetch("/api/deploy", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          repo,
          branch,
          ttl: ttlInput.value.trim(),
          reason: reasonInput.value.trim(),
          linear_ticket: ticketInput.value.trim(),
        }),
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(body.detail || "Deployment failed");
      toast("Deployment started — streaming logs");
      upsertHistoryItem(body);
      openStream(body.deployment_id || body.id, body.run_url);
    } catch (e) {
      toast(e.message || "Deployment failed", true);
    } finally {
      triggerBtn.disabled = false;
    }
  });

  loadRepos();
  refreshClusterList();
})();
