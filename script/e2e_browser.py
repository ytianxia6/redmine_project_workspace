"""Browser E2E for the Redmine project workspace plugin (dev environment only).

Requires: pip install playwright, Google Chrome installed (channel="chrome").
Run:  python script/e2e_browser.py
"""

import os
import re
import sys
import time
import traceback

from playwright.sync_api import sync_playwright

BASE = os.environ.get("REDMINE_URL", "http://127.0.0.1:3002")
PASSWORD = "11111111"
SHOT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs", "screenshots")
os.makedirs(SHOT_DIR, exist_ok=True)

results = []


def check(name, condition, detail=""):
    status = "PASS" if condition else "FAIL"
    results.append((name, status, detail))
    print(f"[{status}] {name} {detail}")


def login(page, user):
    page.goto(f"{BASE}/login")
    page.fill("#username", user)
    page.fill("#password", PASSWORD)
    page.click("input[type=submit]")
    page.wait_for_load_state("networkidle")


def goto_workspace(page, query=""):
    page.goto(f"{BASE}/project_workspace{query}")
    page.wait_for_load_state("networkidle")


def panel_title(page):
    return page.locator(".ws-panel__title").inner_text(timeout=5000).strip()


def run():
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True, args=["--no-sandbox"])
        context = browser.new_context(viewport={"width": 1440, "height": 900}, locale="zh-CN")
        page = context.new_page()

        # 1. anonymous redirects to login for private project
        page.goto(f"{BASE}/project_workspace/issues?project_id=3")
        check("anonymous private project redirects to login", "/login" in page.url, page.url)

        # 2. admin workspace
        login(page, "admin")
        goto_workspace(page)
        check("top menu shows 项目工作台", page.locator("a.project-workspace").count() == 1)
        groups = page.locator("[data-ws-group]").count()
        check("project groups rendered", groups == 4, f"groups={groups}")
        labels = page.locator(".ws-group__label").all_inner_texts()
        check("group order 调研/开发/维护/未分类", labels == ["调研", "开发", "维护", "未分类"], str(labels))
        check("default first project selected", panel_title(page) == "调研项目A", panel_title(page))
        page.screenshot(path=os.path.join(SHOT_DIR, "01-workspace-admin.png"), full_page=True)

        # 3. project click updates right panel only
        page.click("a.ws-project:has-text('开发项目C')")
        page.wait_for_selector(".ws-panel[data-project-id='3']")
        check("click project updates panel", panel_title(page) == "开发项目C", panel_title(page))
        row_count = page.locator("tr.hascontextmenu").count()
        check("panel count matches rows", page.locator(".ws-panel__count strong").inner_text() == str(row_count),
              f"count={page.locator('.ws-panel__count strong').inner_text()} rows={row_count}")
        ids = page.eval_on_selector_all("tr.hascontextmenu", "els => els.map(e => e.id)")
        check("dev-c rows rendered", len(ids) == row_count, str(ids))
        check("closed issue not listed", "已关闭任务：历史需求" not in page.content())
        check("child project issue not listed", "不应出现在开发项目C" not in page.content())

        # 4. context menu + time logging (admin)
        page.click("tr#issue-4", button="right")
        page.wait_for_selector("#context-menu", state="visible")
        menu_text = page.locator("#context-menu").inner_text()
        check("context menu visible", "登记工时" in menu_text, menu_text.replace("\n", " | ")[:120])
        page.screenshot(path=os.path.join(SHOT_DIR, "02-context-menu.png"), full_page=False)
        log_link = page.locator("#context-menu a", has_text="登记工时").first
        href = log_link.get_attribute("href")
        check("log time link points to native form", href == "/issues/4/time_entries/new", href)
        log_link.click()
        page.wait_for_load_state("networkidle")
        check("native time entry form opened", "/issues/4/time_entries/new" in page.url, page.url)
        page.fill("#time_entry_hours", "0.5")
        page.fill("#time_entry_comments", "E2E 右键登记工时")
        activity = page.eval_on_selector(
            "select[name='time_entry[activity_id]']",
            "el => { const o = [...el.options].find(x => x.value); return o ? o.value : ''; }",
        )
        if activity:
            page.select_option("select[name='time_entry[activity_id]']", value=activity)
        page.screenshot(path=os.path.join(SHOT_DIR, "03-time-entry-form.png"), full_page=True)
        page.click("input[type=submit][name=commit]")
        page.wait_for_load_state("networkidle")
        page.goto(f"{BASE}/time_entries?issue_id=4")
        page.wait_for_load_state("networkidle")
        check("time entry submitted and listed", "E2E 右键登记工时" in page.content(), page.url)

        # 5. repeated right clicks (5x) never keep a stale menu/ids
        goto_workspace(page, "?project_id=3")
        page.wait_for_selector("tr#issue-4")
        stale = False
        for issue_id in ["4", "5", "11", "6", "7"]:
            page.click(f"tr#issue-{issue_id}", button="right")
            page.wait_for_selector("#context-menu", state="visible")
            link = page.locator("#context-menu a", has_text="登记工时").first
            expected = f"/issues/{issue_id}/time_entries/new"
            if link.get_attribute("href") != expected:
                stale = True
            page.click(".ws-filters")
            page.wait_for_selector("#context-menu", state="hidden")
        check("5 consecutive context menus target the right issue", not stale)

        # 6. new issue from workspace
        goto_workspace(page, "?project_id=3")
        page.wait_for_selector(".ws-new-issue")
        page.click(".ws-new-issue")
        page.wait_for_load_state("networkidle")
        check("new issue form preselects project", "/projects/dev-c/issues/new" in page.url, page.url)
        subject = f"E2E 工作台新建任务 {int(time.time())}"
        page.fill("#issue_subject", subject)
        page.click("input[type=submit][name=commit]")
        page.wait_for_load_state("networkidle")
        check("issue created", re.search(r"/issues/\d+$", page.url) is not None, page.url)
        goto_workspace(page, "?project_id=3")
        page.wait_for_selector("tr.hascontextmenu")
        check("new issue visible in workspace", subject in page.content())

        # 7. collapse persists, search filters, last project restored
        goto_workspace(page, "")
        page.click("[data-ws-group='调研'] [data-ws-group-toggle]")
        check("group collapses", page.locator("[data-ws-group='调研'].collapsed").count() == 1)
        page.reload()
        page.wait_for_load_state("networkidle")
        check("collapse persisted after reload", page.locator("[data-ws-group='调研'].collapsed").count() == 1)
        page.click("a.ws-project:has-text('开发项目C')")
        page.wait_for_selector(".ws-panel[data-project-id='3']")
        page.reload()
        page.wait_for_load_state("networkidle")
        page.wait_for_selector(".ws-panel[data-project-id='3']", timeout=8000)
        check("last project restored from local storage", panel_title(page) == "开发项目C", panel_title(page))

        page.fill("[data-ws-project-search]", "维护")
        visible = page.eval_on_selector_all(
            "[data-ws-project-item]:not([hidden])", "els => els.map(e => e.getAttribute('data-project-name'))"
        )
        check("project search filters tree", visible == ["维护项目E"], str(visible))
        page.fill("[data-ws-project-search]", "")

        # 8. rapid project switching: last response wins
        page.evaluate(
            """() => {
                const names = ['调研项目A', '开发项目D', '维护项目E'];
                for (const n of names) {
                    const a = [...document.querySelectorAll('a.ws-project')].find(x => x.textContent.trim() === n);
                    if (a) { a.click(); }
                }
            }"""
        )
        page.wait_for_selector(".ws-panel[data-project-id='6']", timeout=8000)
        page.wait_for_timeout(800)
        check("rapid switching ends on last project", panel_title(page) == "维护项目E", panel_title(page))

        # 9. dev1: right-click time logging + new issue (non-admin user)
        dev_context = browser.new_context(viewport={"width": 1440, "height": 900}, locale="zh-CN")
        dev_page = dev_context.new_page()
        login(dev_page, "dev1")
        dev_page.goto(f"{BASE}/project_workspace?project_id=3")
        dev_page.wait_for_load_state("networkidle")
        dev_page.wait_for_selector("tr.hascontextmenu")
        dev_page.click("tr#issue-7", button="right")
        dev_page.wait_for_selector("#context-menu", state="visible")
        dev_page.locator("#context-menu a", has_text="登记工时").first.click()
        dev_page.wait_for_load_state("networkidle")
        check("dev1 log time form opened", "/issues/7/time_entries/new" in dev_page.url, dev_page.url)
        dev_page.fill("#time_entry_hours", "0.75")
        dev_page.fill("#time_entry_comments", "E2E dev1 工时")
        activity = dev_page.eval_on_selector(
            "select[name='time_entry[activity_id]']",
            "el => { const o = [...el.options].find(x => x.value); return o ? o.value : ''; }",
        )
        if activity:
            dev_page.select_option("select[name='time_entry[activity_id]']", value=activity)
        dev_page.click("input[type=submit][name=commit]")
        dev_page.wait_for_load_state("networkidle")
        dev_page.goto(f"{BASE}/time_entries?issue_id=7")
        dev_page.wait_for_load_state("networkidle")
        check("dev1 time entry created", "E2E dev1 工时" in dev_page.content(), dev_page.url)

        dev_page.goto(f"{BASE}/project_workspace?project_id=3")
        dev_page.wait_for_load_state("networkidle")
        dev_page.click(".ws-new-issue")
        dev_page.wait_for_load_state("networkidle")
        dev_subject = f"E2E dev1 新建任务 {int(time.time())}"
        dev_page.fill("#issue_subject", dev_subject)
        dev_page.click("input[type=submit][name=commit]")
        dev_page.wait_for_load_state("networkidle")
        dev_page.goto(f"{BASE}/project_workspace?project_id=3")
        dev_page.wait_for_load_state("networkidle")
        dev_page.wait_for_selector("tr.hascontextmenu")
        check("dev1 new issue visible", dev_subject in dev_page.content())
        dev_context.close()

        # 10. viewer1 permission isolation (separate browser context)
        viewer_context = browser.new_context(viewport={"width": 1440, "height": 900}, locale="zh-CN")
        viewer_page = viewer_context.new_page()
        login(viewer_page, "viewer1")
        viewer_page.goto(f"{BASE}/project_workspace?project_id=3")
        viewer_page.wait_for_load_state("networkidle")
        viewer_page.wait_for_selector("tr.hascontextmenu")
        viewer_rows = viewer_page.locator("tr.hascontextmenu").count()
        viewer_count = viewer_page.locator(".ws-panel__count strong").inner_text()
        check("viewer sees only visible issues", str(viewer_rows) == viewer_count, f"rows={viewer_rows} count={viewer_count}")
        check("viewer does not see private issue", "私有缺陷修复" not in viewer_page.content())
        check("viewer has no new issue button", viewer_page.locator(".ws-new-issue").count() == 0)
        viewer_page.click("tr#issue-4", button="right")
        viewer_page.wait_for_selector("#context-menu", state="visible")
        menu_text = viewer_page.locator("#context-menu").inner_text()
        check("viewer context menu has no log time", "登记工时" not in menu_text)
        viewer_page.screenshot(path=os.path.join(SHOT_DIR, "04-viewer1.png"), full_page=True)
        viewer_page.click(".ws-filters")
        resp = viewer_page.goto(f"{BASE}/issues/4/time_entries/new")
        check("viewer direct time entry URL denied", resp is not None and resp.status == 403, str(resp.status if resp else None))
        viewer_context.close()

        browser.close()

    failed = [r for r in results if r[1] == "FAIL"]
    print(f"\n{len(results) - len(failed)}/{len(results)} checks passed")
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        sys.exit(run())
    except Exception:
        traceback.print_exc()
        sys.exit(2)
