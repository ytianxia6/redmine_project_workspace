(function () {
  'use strict';

  var STORAGE_PROJECT = 'redmine_project_workspace.last_project_id';
  var STORAGE_GROUPS = 'redmine_project_workspace.collapsed_groups';

  function onReady(fn) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', fn);
    } else {
      fn();
    }
  }

  function readJSON(key, fallback) {
    try {
      var raw = window.localStorage.getItem(key);
      return raw ? JSON.parse(raw) : fallback;
    } catch (e) {
      return fallback;
    }
  }

  function writeJSON(key, value) {
    try {
      window.localStorage.setItem(key, JSON.stringify(value));
    } catch (e) {
      /* storage may be unavailable (private mode); ignore */
    }
  }

  function readString(key) {
    try {
      return window.localStorage.getItem(key);
    } catch (e) {
      return null;
    }
  }

  function writeString(key, value) {
    try {
      window.localStorage.setItem(key, value);
    } catch (e) {
      /* ignore */
    }
  }

  onReady(function () {
    var root = document.getElementById('ws-root');
    if (!root) { return; }

    var endpoint = root.getAttribute('data-ws-endpoint');
    var main = document.getElementById('ws-main');
    var tree = root.querySelector('[data-ws-tree]');
    var errorBox = root.querySelector('[data-ws-error]');
    var inflight = null;
    var seq = 0;
    var selectedId = root.getAttribute('data-ws-selected-project');

    if (!main || !endpoint) { return; }

    function panel() {
      return main.querySelector('[data-ws-panel]');
    }

    function panelData() {
      var el = panel();
      if (!el) { return {}; }
      return {
        projectId: el.getAttribute('data-project-id'),
        scope: el.getAttribute('data-scope'),
        perPage: el.getAttribute('data-per-page')
      };
    }

    function showError(show) {
      if (!errorBox) { return; }
      errorBox.hidden = !show;
    }

    function setBusy(busy) {
      if (!main) { return; }
      main.classList.toggle('is-loading', !!busy);
      main.setAttribute('aria-busy', busy ? 'true' : 'false');
    }

    function selectInTree(id) {
      if (!tree || !id) { return; }
      var links = tree.querySelectorAll('.ws-project');
      for (var i = 0; i < links.length; i++) {
        var link = links[i];
        var isSelected = link.getAttribute('data-project-id') === String(id);
        link.classList.toggle('selected', isSelected);
        if (isSelected) {
          link.setAttribute('aria-current', 'true');
        } else {
          link.removeAttribute('aria-current');
        }
      }
    }

    function workspaceUrl(params) {
      var url = new URL(window.location.href);
      url.pathname = url.pathname.replace(/\/issues$/, '');
      url.search = params.toString();
      return url.pathname + url.search;
    }

    function endpointUrl(params) {
      var url = new URL(endpoint, window.location.origin);
      url.search = params.toString();
      return url.toString();
    }

    function load(url, options) {
      options = options || {};
      showError(false);
      if (inflight) { inflight.abort(); }
      inflight = (typeof AbortController !== 'undefined') ? new AbortController() : null;
      var current = ++seq;
      setBusy(true);

      var request = fetch(url, {
        credentials: 'same-origin',
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Accept': 'text/html'
        },
        signal: inflight ? inflight.signal : undefined
      });

      request.then(function (response) {
        if (!response.ok) {
          var error = new Error('HTTP ' + response.status);
          error.status = response.status;
          throw error;
        }
        return response.text();
      }).then(function (html) {
        if (current !== seq) { return; }
        main.innerHTML = html;
        setBusy(false);
        if (options.selectedId) {
          selectedId = String(options.selectedId);
          root.setAttribute('data-ws-selected-project', selectedId);
          selectInTree(selectedId);
          writeString(STORAGE_PROJECT, selectedId);
        }
        if (options.historyUrl) {
          window.history.replaceState({}, '', options.historyUrl);
        }
        var table = main.querySelector('table.ws-table');
        if (table) {
          table.setAttribute('tabindex', '-1');
        }
      }).catch(function (error) {
        if (error && error.name === 'AbortError') { return; }
        if (current !== seq) { return; }
        setBusy(false);
        showError(true);
      });
    }

    function projectClick(event) {
      var link = event.target.closest ? event.target.closest('a.ws-project') : null;
      if (!link) { return; }
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) { return; }
      event.preventDefault();

      var projectId = link.getAttribute('data-project-id');
      var data = panelData();
      var params = new URLSearchParams();
      params.set('project_id', projectId);
      if (data.scope) { params.set('scope', data.scope); }
      if (data.perPage && data.perPage !== '25') { params.set('per_page', data.perPage); }

      load(endpointUrl(params), {
        selectedId: projectId,
        historyUrl: workspaceUrl(params)
      });
    }

    function panelNav(event) {
      var link = event.target.closest ? event.target.closest('a[data-ws-nav]') : null;
      if (!link) { return; }
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) { return; }
      event.preventDefault();

      load(link.href, { historyUrl: link.href });
    }

    if (tree) {
      tree.addEventListener('click', projectClick);
      initSearch(tree);
      initCollapse(tree);
    }
    main.addEventListener('click', panelNav);

    restoreLastProject();
    selectInTree(selectedId);

    function initSearch(treeElement) {
      var input = treeElement.querySelector('[data-ws-project-search]');
      var noMatch = treeElement.querySelector('[data-ws-no-match]');
      if (!input) { return; }

      input.addEventListener('input', function () {
        var term = input.value.trim().toLowerCase();
        var groups = treeElement.querySelectorAll('[data-ws-group]');
        var anyVisible = false;
        for (var i = 0; i < groups.length; i++) {
          var group = groups[i];
          var items = group.querySelectorAll('[data-ws-project-item]');
          var groupVisible = false;
          for (var j = 0; j < items.length; j++) {
            var item = items[j];
            var name = (item.getAttribute('data-project-name') || '').toLowerCase();
            var match = term === '' || name.indexOf(term) !== -1;
            item.hidden = !match;
            if (match) { groupVisible = true; }
          }
          group.hidden = !groupVisible;
          if (groupVisible) { anyVisible = true; }
        }
        if (noMatch) { noMatch.hidden = anyVisible; }
      });
    }

    function initCollapse(treeElement) {
      var stored = readJSON(STORAGE_GROUPS, {});
      var groups = treeElement.querySelectorAll('[data-ws-group]');

      function apply(group, collapsed) {
        var toggle = group.querySelector('[data-ws-group-toggle]');
        group.classList.toggle('collapsed', collapsed);
        if (toggle) { toggle.setAttribute('aria-expanded', collapsed ? 'false' : 'true'); }
      }

      for (var i = 0; i < groups.length; i++) {
        var group = groups[i];
        var key = group.getAttribute('data-ws-group');
        var collapsed = !!(stored && stored[key]);
        apply(group, collapsed);
        (function (groupElement, groupKey) {
          var toggle = groupElement.querySelector('[data-ws-group-toggle]');
          if (!toggle) { return; }
          toggle.addEventListener('click', function () {
            var isCollapsed = !groupElement.classList.contains('collapsed');
            apply(groupElement, isCollapsed);
            var state = readJSON(STORAGE_GROUPS, {});
            state[groupKey] = isCollapsed;
            writeJSON(STORAGE_GROUPS, state);
          });
        })(group, key);
      }
    }

    function restoreLastProject() {
      var stored = readString(STORAGE_PROJECT);
      if (!stored || !tree) { return; }
      if (stored === String(selectedId)) { return; }
      var link = tree.querySelector('.ws-project[data-project-id="' + stored + '"]');
      if (!link) { return; }

      var data = panelData();
      var params = new URLSearchParams();
      params.set('project_id', stored);
      if (data.scope) { params.set('scope', data.scope); }
      load(endpointUrl(params), { selectedId: stored });
    }
  });
})();
