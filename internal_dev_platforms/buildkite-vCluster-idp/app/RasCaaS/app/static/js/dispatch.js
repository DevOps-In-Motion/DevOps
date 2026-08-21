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
  const historyListActive = $("history-list-active");
  const historyListFailed = $("history-list-failed");
  const historyCountActive = $("history-count-active");
  const historyCountFailed = $("history-count-failed");
  const tabActive = $("tab-active");
  const tabFailed = $("tab-failed");

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
    const ttlLabel = { "3d": "3 days", "5d": "5 days", "7d": "7 days" }[ttl] || ttl;

    if (!repo || !branch) {
      triggerPanel.hidden = true;
      return;
    }

    triggerPanel.hidden = false;
    triggerSummary.innerHTML = [
      `<span class="kovr-summary__primary"><strong>${esc(repo)}</strong> @ <strong>${esc(branch)}</strong></span>`,
      fmtSummaryValue(ttlLabel, "TTL"),
      fmtSummaryValue(reason, "Reason"),
      fmtSummaryValue(ticket, "Linear ticket URL"),
    ].join("");
    setStepper(3);
  }

  function phaseClass(dep) {
    if (dep.lifecycle === "deleting") return "kovr-history__status--deleting";
    if (dep.phase === "provisioning" || dep.phase === "syncing") {
      return "kovr-history__status--inflight";
    }
    return `kovr-history__status--${dep.phase || "provisioning"}`;
  }

  function statusLabel(dep) {
    if (dep.lifecycle === "deleting") return "Deleting…";
    if (dep.phase === "provisioning" || dep.phase === "syncing") return "in-flight";
    return dep.status_label || dep.phase;
  }

  // Tabs partition by status (phase). Within each tab: groupby repo @ branch.
  // Client re-partitions even when the API already returns {active, failed}
  // groups — never trust a misplaced row to stay in the wrong tab.
  let historyCache = [];

  function isActiveDeployment(dep) {
    if (!dep) return false;
    if (dep.lifecycle === "deleted" || dep.lifecycle === "superseded") return false;
    const phase = String(dep.phase || "");
    return phase === "ready" || phase === "provisioning" || phase === "syncing";
  }

  function isFailedDeployment(dep) {
    if (!dep) return false;
    if (dep.lifecycle === "deleted") return false;
    // Superseded failed rows still belong on the Failed tab (history).
    return String(dep.phase || "") === "failed";
  }

  function groupKey(dep) {
    return `${dep.repo || ""}@@${dep.branch || ""}`;
  }

  function flattenGroups(groups) {
    const out = [];
    for (const g of groups || []) {
      for (const dep of g.deployments || []) out.push(dep);
    }
    return out;
  }

  function groupByRepoBranch(rows) {
    const map = new Map();
    const order = [];
    const sorted = (rows || []).slice().sort((a, b) => {
      const ta = Date.parse(a.created_at || a.updated_at || 0) || 0;
      const tb = Date.parse(b.created_at || b.updated_at || 0) || 0;
      return tb - ta;
    });
    for (const dep of sorted) {
      const key = groupKey(dep);
      if (!map.has(key)) {
        map.set(key, []);
        order.push(key);
      }
      map.get(key).push(dep);
    }
    return order.map((key) => {
      const deployments = map.get(key);
      const first = deployments[0] || {};
      return {
        key,
        label: `${first.repo || "?"} @ ${first.branch || "?"}`,
        count: deployments.length,
        deployments,
      };
    });
  }

  function partitionByStatus(deps) {
    const active = [];
    const failed = [];
    for (const dep of deps || []) {
      if (isFailedDeployment(dep)) failed.push(dep);
      else if (isActiveDeployment(dep)) active.push(dep);
    }
    return {
      active: groupByRepoBranch(active),
      failed: groupByRepoBranch(failed),
    };
  }

  function refreshHistoryCount() {
    if (!historyListActive || !historyListFailed) return;

    const activeCount = historyListActive.querySelectorAll(".kovr-history__item").length;
    const failedCount = historyListFailed.querySelectorAll(".kovr-history__item").length;

    if (historyCountActive) historyCountActive.textContent = activeCount;
    if (historyCountFailed) historyCountFailed.textContent = failedCount;

    if (activeCount === 0 && !historyListActive.querySelector(".kovr-history__empty")) {
      historyListActive.innerHTML =
        '<li class="kovr-history__empty">No active deployments.</li>';
    }

    if (failedCount === 0 && !historyListFailed.querySelector(".kovr-history__empty")) {
      historyListFailed.innerHTML =
        '<li class="kovr-history__empty">No failed deployments.</li>';
    }
  }

  function renderHistoryItem(dep, { compactTitle } = {}) {
    const li = document.createElement("li");
    li.className = "kovr-history__item";
    li.dataset.deploymentId = dep.id;
    li.dataset.groupKey = groupKey(dep);
    li.dataset.phase = String(dep.phase || "");
    li.title = "Click to show deployment log";
    const ghLink = dep.run_url
      ? ` <a class="kovr-history__link" href="${esc(dep.run_url)}" target="_blank" rel="noopener noreferrer">Actions run</a>`
      : "";
    const linear = (dep.linear_ticket || "").trim();
    const linearOk = /^https?:\/\//i.test(linear);
    const linearLink = linearOk
      ? ` <a class="kovr-history__link kovr-history__link--linear" href="${esc(linear)}" target="_blank" rel="noopener noreferrer">Linear</a>`
      : "";
    const label = statusLabel(dep);
    const ttlMeta = dep.ttl ? `TTL ${esc(dep.ttl)}` : "";
    const title = compactTitle
      ? `${esc(dep.vcluster_name || dep.id)}${ghLink}${linearLink}`
      : `${esc(dep.repo)} @ ${esc(dep.branch)}${ghLink}${linearLink}`;
    li.innerHTML = `
      <div class="kovr-history__body">
        <span class="kovr-history__title">${title}</span>
        <span class="kovr-history__meta">${esc(dep.message || "")}${ttlMeta ? " · " + ttlMeta : ""}</span>
      </div>
      <span class="kovr-history__status ${phaseClass(dep)}">${esc(label)}</span>
    `;
    li.querySelectorAll(".kovr-history__link").forEach((link) => {
      link.addEventListener("click", (e) => e.stopPropagation());
    });
    li.addEventListener("click", () => {
      openStream(dep.id, dep.run_url || "");
    });
    return li;
  }

  function fillHistoryFromGroups(ul, groups, emptyMsg) {
    ul.innerHTML = "";
    if (!groups || groups.length === 0) {
      ul.innerHTML = `<li class="kovr-history__empty">${emptyMsg}</li>`;
      return;
    }
    for (const group of groups) {
      const header = document.createElement("li");
      header.className = "kovr-history__group";
      header.setAttribute("role", "presentation");
      const n = group.count != null ? group.count : (group.deployments || []).length;
      header.innerHTML = `<span class="kovr-history__group-label">${esc(group.label || "?")}</span>` +
        (n > 1 ? `<span class="kovr-history__group-count">${n}</span>` : "");
      ul.appendChild(header);
      for (const dep of group.deployments || []) {
        ul.appendChild(renderHistoryItem(dep, { compactTitle: true }));
      }
    }
  }

  function upsertHistoryItem(dep) {
    if (!dep || !dep.id) return;
    const idx = historyCache.findIndex((d) => d.id === dep.id);
    if (idx >= 0) historyCache[idx] = { ...historyCache[idx], ...dep };
    else historyCache.unshift(dep);
    // Re-fetch so Active/Failed stay on authoritative server + client partition.
    refreshClusterList();
  }

  function applyHistoryPartition(deps) {
    if (!historyListActive || !historyListFailed) return;
    historyCache = Array.isArray(deps) ? deps.slice() : [];
    const partitioned = partitionByStatus(historyCache);
    fillHistoryFromGroups(historyListActive, partitioned.active, "No active deployments.");
    fillHistoryFromGroups(historyListFailed, partitioned.failed, "No failed deployments.");
    if (historyCountActive) {
      historyCountActive.textContent = flattenGroups(partitioned.active).length;
    }
    if (historyCountFailed) {
      historyCountFailed.textContent = flattenGroups(partitioned.failed).length;
    }
  }

  function renderHistoryGroups(payload) {
    // Flatten API groups then re-partition by phase so status tabs cannot mix.
    applyHistoryPartition(flattenGroups(payload.active).concat(flattenGroups(payload.failed)));
  }

  /** Flat-list fallback if an older API still returns an array. */
  function renderHistoryList(deployments) {
    applyHistoryPartition(deployments);
  }

  async function loadVersion() {
    try {
      const res = await fetch("/api/version");
      if (!res.ok) return;
      const data = await res.json();
      const app = data.app_version || "";
      const helm = data.helm_chart_version || "";
      const appBadge = $("app-version-badge");
      const helmBadge = $("helm-version-badge");
      const helmStat = $("stat-helm-version");
      if (appBadge && app) appBadge.textContent = `App ${app}`;
      if (helmBadge && helm) helmBadge.textContent = `Helm ${helm}`;
      if (helmStat && helm) helmStat.textContent = helm;
    } catch {
      /* ignore */
    }
  }

  async function refreshClusterList() {
    try {
      const res = await fetch("/api/clusters");
      if (!res.ok) return;
      const body = await res.json();
      if (body && Array.isArray(body.active) && Array.isArray(body.failed)) {
        renderHistoryGroups(body);
      } else if (Array.isArray(body)) {
        renderHistoryList(body);
      } else {
        applyHistoryPartition([]);
      }
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

  function setRunLink(url) {
    if (!liveRunLink) return;
    if (url) {
      liveRunLink.href = url;
      liveRunLink.hidden = false;
    }
  }

  function openStream(deploymentId, runUrl) {
    closeStream();
    activeDeploymentId = deploymentId;
    livePanel.hidden = false;
    liveLog.textContent = "";
    livePanelStatus.textContent = "Streaming live updates…";
    setRunLink(runUrl);

    eventSource = new EventSource(`/api/clusters/${deploymentId}/stream`);

    eventSource.onmessage = (ev) => {
      let data;
      try {
        data = JSON.parse(ev.data);
      } catch {
        return;
      }

      if (data.run_url) setRunLink(data.run_url);
      if (data.deployment && data.deployment.run_url) setRunLink(data.deployment.run_url);

      if (data.type === "log" && data.line) {
        appendLogLine(data.line, data.level);
      }

      // Keep Active list in sync for in-flight + terminal phases.
      if (data.deployment && data.type !== "deployment_created" && data.type !== "complete") {
        const ph = data.deployment.phase;
        if (ph === "failed") {
          upsertHistoryItem(data.deployment);
          livePanelStatus.textContent = "Deployment failed";
          tabFailed?.click();
        } else if (ph === "provisioning" || ph === "syncing") {
          upsertHistoryItem(data.deployment);
          livePanelStatus.textContent = data.deployment.message || "In progress…";
        } else if (ph !== "ready") {
          livePanelStatus.textContent = data.deployment.message || "In progress…";
        }
      }

      // Same signal as Redis lock: workflow posted phase=ready.
      if (data.type === "deployment_created" && data.deployment) {
        upsertHistoryItem(data.deployment);
        livePanelStatus.textContent = "Deployment complete";
        toast("Deployment created — branch locked");
      }

      if (data.type === "complete") {
        const ph = data.deployment && data.deployment.phase;
        if (ph === "ready") {
          upsertHistoryItem(data.deployment);
          livePanelStatus.textContent = "Deployment complete";
        } else if (ph === "failed") {
          upsertHistoryItem(data.deployment);
          livePanelStatus.textContent = "Deployment failed";
          tabFailed?.click();
        } else {
          livePanelStatus.textContent = "Stream ended";
        }
        closeStream();
        refreshClusterList();
      }

      if (data.type === "idle") {
        appendLogLine(data.message || "Stream idle — refresh to fetch latest.", "info");
        livePanelStatus.textContent = "Idle — refresh to fetch latest status";
        closeStream();
        refreshClusterList();
      }

      if (data.type === "error") {
        appendLogLine(data.message || "Error", "error");
        livePanelStatus.textContent = "Stream error";
        closeStream();
        refreshClusterList();
      }
    };

    eventSource.onerror = () => {
      appendLogLine("Connection to live stream closed", "error");
      livePanelStatus.textContent = "Stream disconnected";
      closeStream();
      refreshClusterList();
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
    el?.addEventListener("change", updateSummary);
  });

    triggerBtn.addEventListener("click", async () => {
    const repo = repoSelect.value;
    const branch = branchSelect.value;
    if (!repo || !branch) return;

    triggerBtn.disabled = true;
    closeStream();
    try {
      const payload = {
        repo,
        branch,
        ttl: ttlInput.value.trim(),
        reason: reasonInput.value.trim(),
        linear_ticket: ticketInput.value.trim(),
        force: false,
      };
      let res = await fetch("/api/deploy", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      let body = await res.json().catch(() => ({}));
      if (res.status === 409) {
        const detail = typeof body.detail === "string" ? body.detail : "Conflict";
        if (window.confirm(`${detail}\n\nForce redeploy?`)) {
          payload.force = true;
          res = await fetch("/api/deploy", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(payload),
          });
          body = await res.json().catch(() => ({}));
        } else {
          throw new Error(detail);
        }
      }
      if (!res.ok) {
        const detail = typeof body.detail === "string" ? body.detail : "Deployment failed";
        throw new Error(detail);
      }
      toast("Deployment started — streaming logs");
      // Show under Active immediately as in-flight.
      if (body.id || body.deployment_id) {
        upsertHistoryItem(body);
      }
      openStream(body.deployment_id || body.id, body.run_url || "");
      if (body.run_url) setRunLink(body.run_url);
    } catch (e) {
      toast(e.message || "Deployment failed", true);
    } finally {
      triggerBtn.disabled = false;
    }
  });

  loadVersion();
  loadRepos();
  refreshClusterList();
  
  // Tab switching for active/failed deployments
  tabActive?.addEventListener("click", () => {
    tabActive.classList.add("kovr-tab--active");
    tabFailed.classList.remove("kovr-tab--active");
    historyListActive.hidden = false;
    historyListFailed.hidden = true;
  });
  
  tabFailed?.addEventListener("click", () => {
    tabFailed.classList.add("kovr-tab--active");
    tabActive.classList.remove("kovr-tab--active");
    historyListActive.hidden = true;
    historyListFailed.hidden = false;
  });
})();
